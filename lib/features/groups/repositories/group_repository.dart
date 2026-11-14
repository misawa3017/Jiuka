import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';

class GroupRepository extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final firebase_auth.FirebaseAuth _auth;

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
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? firebase_auth.FirebaseAuth.instance {
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
      );
      await docRef.set(groupWithId.toMap());
    } catch (error) {
      debugPrint('Error creating group: $error');
      rethrow;
    }
  }

  Future<void> joinGroup(String groupId, String userId) async {
    try {
      await _firestore.collection('groups').doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId]),
      });
    } catch (error) {
      debugPrint('Error joining group: $error');
      rethrow;
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_groupsSubscription?.cancel());
    super.dispose();
  }
}
