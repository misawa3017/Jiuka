import 'package:firebase_core/firebase_core.dart';

/// Web 配置由啟動參數提供，不在程式中假設 Firebase 專案。
FirebaseOptions webFirebaseOptions() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  if ([
    apiKey,
    appId,
    projectId,
    senderId,
    authDomain,
  ].any((value) => value.isEmpty)) {
    throw StateError('缺少 Firebase Web 設定，請參考 docs/google-sign-in.md。');
  }
  return const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    projectId: projectId,
    messagingSenderId: senderId,
    authDomain: authDomain,
  );
}
