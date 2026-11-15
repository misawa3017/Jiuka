import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';

/// 待審核的入隊申請（groups/{gid}/joinRequests/{uid}）。
class JoinRequest {
  final String userId;
  final String displayName;
  final DateTime? createdAt;

  const JoinRequest({
    required this.userId,
    required this.displayName,
    this.createdAt,
  });

  factory JoinRequest.fromMap(Map<String, dynamic> map, String id) {
    final created = map['createdAt'];
    return JoinRequest(
      userId: id,
      displayName: map['displayName'] is String
          ? (map['displayName'] as String).trim()
          : '',
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

class GroupRepository extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final firebase_auth.FirebaseAuth _auth;
  final FirebaseFunctions? _functions;
  final Future<void> Function(String groupId, String userId, bool approve)?
  _submitReview;

  List<Group> _groups = [];
  StreamSubscription<firebase_auth.User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSubscription;
  String? _userId;
  bool _receivedAuthState = false;
  bool _isLoading = true;
  Object? _error;

  List<Group> get groups => List.unmodifiable(_groups);
  bool get isLoading => _isLoading;
  Object? get error => _error;

  GroupRepository({
    FirebaseFirestore? firestore,
    firebase_auth.FirebaseAuth? auth,
    FirebaseFunctions? functions,
    Future<void> Function(String groupId, String userId, bool approve)?
    submitReview,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance,
       _functions = functions,
       _submitReview = submitReview {
    _authSubscription = _auth.authStateChanges().listen(
      _handleAuthChange,
      onError: (Object error) {
        unawaited(_groupsSubscription?.cancel());
        _groupsSubscription = null;
        _userId = null;
        _groups = [];
        _error = error;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void _handleAuthChange(firebase_auth.User? user) {
    final nextUserId = user?.uid;
    if (_receivedAuthState && nextUserId == _userId) return;
    _receivedAuthState = true;
    _userId = nextUserId;
    unawaited(_groupsSubscription?.cancel());
    _groupsSubscription = null;
    _groups = [];
    _error = null;

    if (nextUserId == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _listenToGroups();
  }

  void _listenToGroups() {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _groupsSubscription = _firestore
        .collection('groups')
        .snapshots()
        .listen(
          (snapshot) {
            _groups = snapshot.docs
                .map((doc) => Group.fromMap(doc.data(), doc.id))
                .toList();
            _isLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (Object error) {
            _isLoading = false;
            _error = error;
            notifyListeners();
          },
        );
  }

  void retry() {
    if (_userId == null) return;
    unawaited(_groupsSubscription?.cancel());
    _listenToGroups();
  }

  List<Group> getGroupsForUser(String userId) =>
      _groups.where((group) => group.memberIds.contains(userId)).toList();

  Future<void> createGroup(Group group) async {
    try {
      final docRef = _firestore.collection('groups').doc();
      final groupWithId = Group(
        id: docRef.id,
        name: group.name,
        description: group.description,
        adminId: group.adminId,
        maxPlayersDefault: group.maxPlayersDefault,
        recurringEventSettings: group.recurringEventSettings,
        memberIds: group.memberIds,
        memberNames: group.memberNames,
      );
      await docRef.set(groupWithId.toMap());
    } catch (error) {
      debugPrint('Error creating group: $error');
      rethrow;
    }
  }

  DocumentReference<Map<String, dynamic>> _group(String groupId) =>
      _firestore.collection('groups').doc(groupId);

  DocumentReference<Map<String, dynamic>> _request(
    String groupId,
    String userId,
  ) => _group(groupId).collection('joinRequests').doc(userId);

  /// 申請加入球隊；規則會檢查暱稱等於本人的暱稱。隊長會收到通知。
  Future<void> requestToJoin(String groupId, String userId, String name) =>
      _request(groupId, userId).set({
        'userId': userId,
        'displayName': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// 撤回自己的入隊申請。
  Future<void> withdrawRequest(String groupId, String userId) =>
      _request(groupId, userId).delete();

  /// 自己是否有待審核的申請。
  Stream<bool> watchMyRequest(String groupId, String userId) =>
      _request(groupId, userId).snapshots().map((doc) => doc.exists);

  /// 隊長看待審核的申請，由舊到新。
  Stream<List<JoinRequest>> watchJoinRequests(String groupId) => _group(groupId)
      .collection('joinRequests')
      .orderBy('createdAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => JoinRequest.fromMap(doc.data(), doc.id))
            .toList(),
      );

  /// 隊長核准或拒絕；由 Cloud Function 加入成員並通知申請人。
  Future<void> reviewJoinRequest(
    String groupId,
    String userId, {
    required bool approve,
  }) async {
    if (_submitReview case final submit?) {
      await submit(groupId, userId, approve);
      return;
    }
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'asia-east1');
    await functions.httpsCallable('reviewJoinRequest').call({
      'groupId': groupId,
      'userId': userId,
      'approve': approve,
    });
  }

  /// 隊長移除成員，或成員自己退出：一併清掉暱稱與幹部身分。
  Future<void> removeMember(String groupId, String userId) =>
      _group(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId]),
        'memberNames.$userId': FieldValue.delete(),
        'officerIds': FieldValue.arrayRemove([userId]),
      });

  /// 隊長任免幹部。
  Future<void> setOfficer(String groupId, String userId, bool officer) =>
      _group(groupId).update({
        'officerIds': officer
            ? FieldValue.arrayUnion([userId])
            : FieldValue.arrayRemove([userId]),
      });

  /// 隊長轉移給其他成員；新隊長同時從幹部名單移除，原隊長變成一般隊員。
  Future<void> transferCaptain(String groupId, String newCaptainId) =>
      _group(groupId).update({
        'adminId': newCaptainId,
        'officerIds': FieldValue.arrayRemove([newCaptainId]),
      });

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_groupsSubscription?.cancel());
    super.dispose();
  }
}
