import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';

class AuthRepository extends ChangeNotifier {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final Future<firebase_auth.UserCredential> Function()? _googleLogin;
  late final StreamSubscription<firebase_auth.User?> _subscription;
  Future<void>? _googleInitialization;
  User? _currentUser;
  bool _isLoading = true;
  bool _signingIn = false;
  bool _disposed = false;
  int _revision = 0;
  String? _errorMessage;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;
  String? get errorMessage => _errorMessage;

  AuthRepository({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    Future<firebase_auth.UserCredential> Function()? googleLogin,
  }) : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _googleLogin = googleLogin {
    _subscription = _firebaseAuth.authStateChanges().listen(
      (user) {
        if (!_signingIn) unawaited(_restoreSession(user));
      },
      onError: (Object error) {
        _revision++;
        _currentUser = null;
        _isLoading = false;
        _errorMessage = '無法恢復登入狀態，請重新登入。';
        _notify();
      },
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _hasGoogleProvider(firebase_auth.User user) =>
      user.providerData.any((provider) => provider.providerId == 'google.com');

  /// 使用交易避免不同分頁首次登入時覆寫已建立的個人資料。
  Future<User> _loadOrCreateProfile(firebase_auth.User user) async {
    if (!_hasGoogleProvider(user)) {
      throw StateError('Google sign-in required');
    }
    final ref = _firestore.collection('users').doc(user.uid);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) return User.fromMap(snapshot.data()!, user.uid);
      final name = user.displayName?.trim();
      final email = user.email?.trim();
      if (name == null || name.isEmpty || email == null || email.isEmpty) {
        throw StateError('Incomplete Google profile');
      }
      final profile = User(
        id: user.uid,
        name: name,
        email: email,
        avatarUrl: user.photoURL,
      );
      transaction.set(ref, profile.toMap());
      return profile;
    });
  }

  Future<void> _restoreSession(firebase_auth.User? user) async {
    final revision = ++_revision;
    _currentUser = null;
    _isLoading = true;
    _notify();
    try {
      // 停用密碼供應商後，Firebase 仍可能恢復先前的本機工作階段。
      if (user != null && !_hasGoogleProvider(user)) {
        await _firebaseAuth.signOut();
        return;
      }
      final profile = user == null ? null : await _loadOrCreateProfile(user);
      if (revision == _revision) {
        _currentUser = profile;
        if (profile != null) unawaited(backfillOrganizerName(profile));
      }
    } catch (_) {
      if (revision == _revision) {
        _errorMessage = '無法載入帳號資料，請使用 Google 重新登入。';
        try {
          await _firebaseAuth.signOut();
        } catch (_) {
          // 資料載入失敗時，App 仍維持未登入狀態。
        }
      }
    } finally {
      if (revision == _revision) {
        _isLoading = false;
        _notify();
      }
    }
  }

  /// 補上自己發布場次中缺少或過期的主揪暱稱（舊版場次沒有 organizerName）。
  ///
  /// 登入後在背景執行，不阻擋登入；失敗只記錄，下次登入會再試。
  @visibleForTesting
  Future<void> backfillOrganizerName(User profile) async {
    try {
      final organized = await _firestore
          .collection('events')
          .where('organizerId', isEqualTo: profile.id)
          .get();
      final stale = [
        for (final event in organized.docs)
          if (event.data()['organizerName'] != profile.name) event.reference,
      ];
      // 每批最多 500 筆寫入。
      for (var start = 0; start < stale.length; start += 500) {
        final batch = _firestore.batch();
        for (final reference in stale.skip(start).take(500)) {
          batch.update(reference, {'organizerName': profile.name});
        }
        await batch.commit();
      }
    } catch (error) {
      debugPrint('補上主揪暱稱失敗：$error');
    }
  }

  Future<firebase_auth.UserCredential> _openGoogleLogin() async {
    if (_googleLogin != null) return _googleLogin();
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(
        firebase_auth.GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'}),
      );
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize();
    try {
      await _googleInitialization;
    } catch (_) {
      _googleInitialization = null;
      rethrow;
    }
    final account = await GoogleSignIn.instance.authenticate();
    return _firebaseAuth.signInWithCredential(
      firebase_auth.GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      ),
    );
  }

  Future<void> signInWithGoogle() async {
    if (_isLoading) return;
    final revision = ++_revision;
    _signingIn = true;
    _isLoading = true;
    _errorMessage = null;
    _notify();
    try {
      final result = await _openGoogleLogin();
      final user = result.user;
      if (user == null) throw StateError('Missing Google user');
      final profile = await _loadOrCreateProfile(user);
      if (revision == _revision) {
        _currentUser = profile;
        unawaited(backfillOrganizerName(profile));
      }
    } catch (error) {
      if (revision == _revision) {
        _currentUser = null;
        _errorMessage = _loginError(error);
        try {
          await _firebaseAuth.signOut();
        } catch (_) {
          // 原始登入錯誤優先顯示；App 仍維持未登入狀態。
        }
      }
    } finally {
      _signingIn = false;
      if (revision == _revision) {
        _isLoading = false;
        _notify();
      }
    }
  }

  String _loginError(Object error) {
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return '已取消登入，可以再次嘗試。';
    }
    if (error is firebase_auth.FirebaseAuthException) {
      return switch (error.code) {
        'popup-closed-by-user' || 'cancelled-popup-request' => '已取消登入，可以再次嘗試。',
        'popup-blocked' => '瀏覽器阻擋了登入視窗，請允許彈出視窗後重試。',
        'network-request-failed' => '網路連線失敗，請檢查連線後重試。',
        'account-exists-with-different-credential' =>
          '此帳號已有其他登入方式，請聯絡管理員處理，系統不會自動合併資料。',
        'operation-not-allowed' ||
        'unauthorized-domain' => 'Google 登入尚未完成設定，請聯絡管理員。',
        _ => 'Google 登入失敗，請稍後重試。',
      };
    }
    return '無法完成登入或載入個人資料，請稍後重試。';
  }

  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
      _revision++;
      _currentUser = null;
      _errorMessage = null;
    } catch (_) {
      _errorMessage = '登出失敗，請稍後重試。';
    }
    _isLoading = false;
    _notify();
  }

  /// 更新暱稱，並同步到自己所有報名資料的 displayName 與自己發布場次的 organizerName。
  Future<void> updateUser(User updatedUser) async {
    if (updatedUser.id != _currentUser?.id) throw StateError('Not signed in');
    final name = updatedUser.name;
    // 需要更新的文件與要寫入的欄位：報名資料寫 displayName，場次寫 organizerName。
    final stale = <(DocumentReference<Map<String, dynamic>>, String)>[];
    // 與「我的場次」相同的查詢形狀，沿用既有的 collection-group 索引。
    for (final status in ['attending', 'waitlisted']) {
      final snapshot = await _firestore
          .collectionGroup('participants')
          .where('userId', isEqualTo: updatedUser.id)
          .where('status', isEqualTo: status)
          .orderBy('joinedAt')
          .get();
      for (final entry in snapshot.docs) {
        if (entry.data()['displayName'] != name) {
          stale.add((entry.reference, 'displayName'));
        }
      }
    }

    // 自己發布過的場次上也有公開的主揪暱稱，一併同步。
    final organized = await _firestore
        .collection('events')
        .where('organizerId', isEqualTo: updatedUser.id)
        .get();
    for (final event in organized.docs) {
      if (event.data()['organizerName'] != name) {
        stale.add((event.reference, 'organizerName'));
      }
    }

    // 規則用 getAfter 比對暱稱，所以使用者文件要放在第一批；每批最多 500 筆寫入。
    var batch = _firestore.batch()
      ..update(_firestore.collection('users').doc(updatedUser.id), {
        'name': name,
      });
    var writes = 1;
    for (final (reference, field) in stale) {
      if (writes == 500) {
        await batch.commit();
        batch = _firestore.batch();
        writes = 0;
      }
      batch.update(reference, {field: name});
      writes++;
    }
    await batch.commit();
    _currentUser = updatedUser;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _subscription.cancel();
    super.dispose();
  }
}
