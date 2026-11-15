import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/firebase_config.dart';
import 'features/auth/repositories/auth_repository.dart';
import 'features/groups/repositories/group_repository.dart';
import 'features/events/repositories/event_repository.dart';
import 'features/notifications/notification_repository.dart';
import 'features/notifications/push_service.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  // 使用 /event/xxx 形式的網址（預設是 /#/event/xxx），分享連結與重新整理才會進到正確頁面。
  // Firebase Hosting 已設定把所有路徑導回 index.html。
  usePathUrlStrategy();
  // 用 push 開啟的頁面（球隊、場次等）也要更新網址列，才能複製、分享與重新整理。
  GoRouter.optionURLReflectsImperativeAPIs = true;
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      debugPrint('Mobile ads initialization failed: $error');
    }
  }
  await Firebase.initializeApp(options: kIsWeb ? webFirebaseOptions() : null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthRepository()),
        ChangeNotifierProvider(create: (_) => GroupRepository()),
        ChangeNotifierProvider(create: (_) => EventRepository()),
        Provider(create: (_) => NotificationRepository()),
        Provider(create: (_) => PushService()),
      ],
      child: const JiukaApp(),
    ),
  );
}

class JiukaApp extends StatefulWidget {
  const JiukaApp({super.key});

  @override
  State<JiukaApp> createState() => _JiukaAppState();
}

class _JiukaAppState extends State<JiukaApp> {
  late final GoRouter _router = createAppRouter(context.read<AuthRepository>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Jiuka 揪咖',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
