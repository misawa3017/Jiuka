import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:mocktail/mocktail.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'support/auth_fixture.dart';

void main() {
  late AuthFixture fixture;
  setUp(() async {
    fixture = AuthFixture();
    await fixture.ready();
  });
  tearDown(() => fixture.dispose());

  test('首次登入建立完整資料，再次登入保留暱稱', () async {
    await fixture.repository.signInWithGoogle();
    expect(fixture.repository.isAuthenticated, isTrue);
    expect(fixture.saved!['name'], 'Google Name');
    expect(fixture.writes, 1);
    fixture.saved!['name'] = '自訂暱稱';
    await fixture.repository.logout();
    await Future<void>.delayed(Duration.zero);
    await fixture.repository.signInWithGoogle();
    expect(fixture.repository.currentUser!.name, '自訂暱稱');
    expect(fixture.writes, 1);
  });

  test('取消、網路失敗及重試不建立不完整資料', () async {
    for (final code in ['popup-closed-by-user', 'network-request-failed']) {
      fixture.loginError = fb.FirebaseAuthException(code: code);
      await fixture.repository.signInWithGoogle();
      expect(fixture.repository.isAuthenticated, isFalse);
      expect(fixture.repository.isLoading, isFalse);
      expect(fixture.repository.errorMessage, isNotNull);
      expect(fixture.writes, 0);
    }
    fixture.loginError = null;
    await fixture.repository.signInWithGoogle();
    expect(fixture.repository.isAuthenticated, isTrue);
    expect(fixture.repository.errorMessage, isNull);
  });

  test('資料寫入失敗不算登入成功，重試可恢復', () async {
    fixture.storeError = StateError('offline');
    await fixture.repository.signInWithGoogle();
    expect(fixture.repository.isAuthenticated, isFalse);
    expect(fixture.writes, 0);
    verify(() => fixture.auth.signOut()).called(1);
    fixture.storeError = null;
    await fixture.repository.signInWithGoogle();
    expect(fixture.repository.isAuthenticated, isTrue);
  });

  test('缺少 Google 基本資料不建立文件', () async {
    when(() => fixture.user.displayName).thenReturn(null);
    await fixture.repository.signInWithGoogle();
    expect(fixture.writes, 0);
    expect(fixture.repository.isAuthenticated, isFalse);
  });

  test('恢復既有 Google 工作階段並在登出後清除', () async {
    fixture.saved = {'name': '原暱稱', 'email': 'player@example.com'};
    fixture.changes.add(fixture.user);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.repository.currentUser!.name, '原暱稱');
    expect(fixture.writes, 0);
    await fixture.repository.logout();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.repository.currentUser, isNull);
    expect(fixture.repository.isLoading, isFalse);
  });

  test('恢復工作階段時若資料讀取失敗會登出', () async {
    fixture.storeError = StateError('unavailable');
    fixture.changes.add(fixture.user);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.repository.isAuthenticated, isFalse);
    expect(fixture.repository.errorMessage, isNotNull);
    verify(() => fixture.auth.signOut()).called(1);
  });

  test('舊密碼工作階段不獲得 App 登入狀態', () async {
    when(() => fixture.userInfo.providerId).thenReturn('password');
    fixture.changes.add(fixture.user);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.repository.isAuthenticated, isFalse);
    expect(fixture.writes, 0);
    verify(() => fixture.auth.signOut()).called(1);
  });

  test('返回原場次並拒絕外部與循環返回位置', () async {
    expect(authRedirect(fixture.repository, Uri.parse('/event/abc')), isNull);
    final redirect = authRedirect(
      fixture.repository,
      Uri.parse('/create-event?group=abc'),
    )!;
    expect(
      Uri.parse(redirect).queryParameters['from'],
      '/create-event?group=abc',
    );
    await fixture.repository.signInWithGoogle();
    expect(
      authRedirect(fixture.repository, Uri.parse(redirect)),
      '/create-event?group=abc',
    );
    for (final value in [
      'https://example.com',
      '//example.com',
      '/login?from=/login',
      'relative',
    ]) {
      expect(safeReturnLocation(value), '/');
    }
  });
}
