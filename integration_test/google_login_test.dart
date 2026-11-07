import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'package:jiuka/features/auth/repositories/auth_repository.dart';
import 'package:jiuka/features/auth/screens/login_screen.dart';
import '../test/support/auth_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 使用替身隔離外部 OAuth；真實 Google 視窗與 Firebase 規則另需測試專案驗證。
  testWidgets('場次深層連結登入後返回、登出後回登入頁', (tester) async {
    final fixture = AuthFixture();
    await tester.runAsync(fixture.ready);
    final router = GoRouter(
      initialLocation: '/event/test-event',
      refreshListenable: fixture.repository,
      redirect: (_, state) => authRedirect(fixture.repository, state.uri),
      routes: [
        GoRoute(path: '/login', builder: (_, state) => const LoginScreen()),
        GoRoute(
          path: '/event/:id',
          builder: (eventContext, state) => Scaffold(
            body: Column(
              children: [
                Text('場次：${state.pathParameters['id']}'),
                TextButton(
                  onPressed: () => eventContext.go(
                    '/login?from=/event/${state.pathParameters['id']}',
                  ),
                  child: const Text('報名'),
                ),
                TextButton(
                  onPressed: fixture.repository.logout,
                  child: const Text('登出'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(() async {
      router.dispose();
      await fixture.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthRepository>.value(
        value: fixture.repository,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('報名'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 Google 帳號登入'));
    await tester.pumpAndSettle();
    expect(find.text('場次：test-event'), findsOneWidget);
    await tester.tap(find.text('登出'));
    await tester.pumpAndSettle();
    expect(find.text('場次：test-event'), findsOneWidget);
    await tester.tap(find.text('報名'));
    await tester.pumpAndSettle();
    expect(find.text('使用 Google 帳號登入'), findsOneWidget);
  });
}
