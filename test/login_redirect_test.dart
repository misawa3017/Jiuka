import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'package:jiuka/features/auth/repositories/auth_repository.dart';
import 'package:jiuka/features/auth/screens/login_screen.dart';
import 'support/auth_fixture.dart';

void main() {
  testWidgets('從首頁用 push 開登入頁，登入後應該離開登入頁', (tester) async {
    final fixture = AuthFixture();
    await tester.runAsync(fixture.ready);
    final router = GoRouter(
      refreshListenable: fixture.repository,
      redirect: (_, state) => authRedirect(fixture.repository, state.uri),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/login?from=/'),
              child: const Text('首頁'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
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
    await tester.tap(find.text('首頁'));
    await tester.pumpAndSettle();
    expect(find.text('使用 Google 帳號登入'), findsOneWidget);
    await tester.tap(find.text('使用 Google 帳號登入'));
    await tester.pumpAndSettle();
    expect(find.text('使用 Google 帳號登入'), findsNothing);
    expect(find.text('首頁'), findsOneWidget);
  });

  testWidgets('從場次頁用 push 開登入頁，登入後回到該場次', (tester) async {
    final fixture = AuthFixture();
    await tester.runAsync(fixture.ready);
    final router = GoRouter(
      initialLocation: '/event/game',
      refreshListenable: fixture.repository,
      redirect: (_, state) => authRedirect(fixture.repository, state.uri),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('首頁')),
        GoRoute(
          path: '/event/:id',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(
                '/login?from=${Uri.encodeComponent('/event/game')}',
              ),
              child: Text('場次 ${state.pathParameters['id']}'),
            ),
          ),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
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
    await tester.tap(find.text('場次 game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用 Google 帳號登入'));
    await tester.pumpAndSettle();
    expect(find.text('使用 Google 帳號登入'), findsNothing);
    expect(find.text('場次 game'), findsOneWidget);
  });
}
