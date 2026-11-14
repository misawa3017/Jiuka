import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum PushStatus { unavailable, off, on, blocked }

/// 瀏覽器推播：取得 FCM token 並存到 users/{uid}/fcmTokens/{token}，
/// Cloud Functions 發通知時會一併推播。
///
/// 需要 build 時帶入 `--dart-define=FIREBASE_VAPID_KEY=...`（Firebase Console →
/// 專案設定 → Cloud Messaging → 網路推播憑證）；沒有設定時推播停用，站內通知照常運作。
class PushService {
  static const vapidKey = String.fromEnvironment('FIREBASE_VAPID_KEY');

  final FirebaseFirestore _firestore;
  final FirebaseMessaging Function() _messaging;

  PushService({
    FirebaseFirestore? firestore,
    FirebaseMessaging Function()? messaging,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? (() => FirebaseMessaging.instance);

  bool get isSupported => kIsWeb && vapidKey.isNotEmpty;

  DocumentReference<Map<String, dynamic>> _tokenRef(
    String userId,
    String token,
  ) => _firestore
      .collection('users')
      .doc(userId)
      .collection('fcmTokens')
      .doc(token);

  Future<PushStatus> status(String userId) async {
    if (!isSupported) return PushStatus.unavailable;
    try {
      final settings = await _messaging().getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return PushStatus.blocked;
      }
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return PushStatus.off;
      }
      final token = await _messaging().getToken(vapidKey: vapidKey);
      if (token == null) return PushStatus.off;
      return (await _tokenRef(userId, token).get()).exists
          ? PushStatus.on
          : PushStatus.off;
    } catch (error) {
      debugPrint('查詢推播狀態失敗：$error');
      return PushStatus.off;
    }
  }

  /// 請瀏覽器授權並登記這台裝置；回傳最新狀態。
  Future<PushStatus> enable(String userId) async {
    if (!isSupported) return PushStatus.unavailable;
    final settings = await _messaging().requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return PushStatus.blocked;
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return PushStatus.off;
    }
    final token = await _messaging().getToken(vapidKey: vapidKey);
    if (token == null) return PushStatus.off;
    await _tokenRef(
      userId,
      token,
    ).set({'createdAt': FieldValue.serverTimestamp()});
    return PushStatus.on;
  }

  /// 取消這台裝置的推播（例如登出前）；失敗不影響其他操作。
  Future<void> disable(String userId) async {
    if (!isSupported) return;
    try {
      final token = await _messaging().getToken(vapidKey: vapidKey);
      if (token != null) await _tokenRef(userId, token).delete();
      await _messaging().deleteToken();
    } catch (error) {
      debugPrint('取消推播失敗：$error');
    }
  }
}
