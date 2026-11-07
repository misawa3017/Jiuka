import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:go_router/go_router.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'package:jiuka/features/auth/repositories/auth_repository.dart';
import 'package:jiuka/features/auth/screens/login_screen.dart';
import 'support/auth_fixture.dart';

void main() {
  testWidgets('只有 Google 入口，取消登入顯示重試訊息', (tester) async {
    final fixture = AuthFixture();
    addTearDown(fixture.dispose);
    await tester.runAsync(fixture.ready);
    fixture.loginError = fb.FirebaseAuthException(code: 'popup-closed-by-user');
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthRepository>.value(
        value: fixture.repository,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('使用 Google 帳號登入'), findsOneWidget);
    await tester.tap(find.text('使用 Google 帳號登入'));
    await tester.pumpAndSettle();
    expect(find.text('已取消登入，可以再次嘗試。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('從場次連結登入返回場次，登出後回登入頁', (tester) async {
    final fixture = AuthFixture();
    await tester.runAsync(fixture.ready);
    final router = GoRouter(
      initialLocation: '/event/test-event',
      refreshListenable: fixture.repository,
      redirect: (_, state) => authRedirect(fixture.repository, state.uri),
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
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
    expect(find.text('場次：test-event'), findsOneWidget);
    await tester.tap(find.text('報名'));
    await tester.pumpAndSettle();
    expect(find.text('使用 Google 帳號登入'), findsOneWidget);
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
