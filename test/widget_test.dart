import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:go_router/go_router.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'package:jiuka/features/admin/screens/admin_screen.dart';
import 'package:jiuka/features/auth/repositories/auth_repository.dart';
import 'package:jiuka/features/auth/screens/login_screen.dart';
import 'package:jiuka/features/events/screens/create_event_screen.dart';
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

  test('未登入可看場次詳情，但編輯頁要先登入', () async {
    final fixture = AuthFixture();
    addTearDown(fixture.dispose);
    await fixture.ready();
    expect(authRedirect(fixture.repository, Uri.parse('/event/game')), isNull);
    expect(
      authRedirect(fixture.repository, Uri.parse('/event/game/edit')),
      '/login?from=%2Fevent%2Fgame%2Fedit',
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

  testWidgets('發布表單在手機寬度分區顯示且不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CreateEventScreen()));
    await tester.pumpAndSettle();
    for (final section in ['基本資訊', '時間', '人數']) {
      expect(find.text(section), findsOneWidget);
    }
    expect(find.text('活動名稱（選填）'), findsOneWidget);
    expect(find.text('縣市'), findsOneWidget);
    expect(find.text('發布場次'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('補充說明'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('費用'), findsOneWidget);
    expect(find.text('先開放給熟人'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非管理者打開管理後台只看到提示', (tester) async {
    final fixture = AuthFixture();
    addTearDown(fixture.dispose);
    await tester.runAsync(fixture.ready);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthRepository>.value(
        value: fixture.repository,
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    expect(find.text('只有系統管理者可以進入這個頁面。'), findsOneWidget);
  });
}
