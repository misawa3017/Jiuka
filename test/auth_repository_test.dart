import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:mocktail/mocktail.dart';
import 'package:jiuka/core/router/app_router.dart';
import 'package:jiuka/features/auth/models/user_model.dart';
import 'support/auth_fixture.dart';

// ignore: subtype_of_sealed_class
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockEntry extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class MockBatch extends Mock implements WriteBatch {}

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

  test('改暱稱時同一批寫入同步報名資料，已同步的不重寫', () async {
    registerFallbackValue(MockDocument());
    await fixture.repository.signInWithGoogle();
    final query = MockQuery();
    final batch = MockBatch();
    MockEntry entry(String name) {
      final doc = MockEntry();
      when(() => doc.data()).thenReturn({'displayName': name});
      when(() => doc.reference).thenReturn(MockDocument());
      return doc;
    }

    final stale = entry('Google Name');
    final synced = entry('新暱稱');
    final legacy = MockEntry();
    when(() => legacy.data()).thenReturn({});
    when(() => legacy.reference).thenReturn(MockDocument());
    QuerySnapshot<Map<String, dynamic>> result(List<MockEntry> docs) {
      final snapshot = MockQuerySnapshot();
      when(() => snapshot.docs).thenReturn(docs);
      return snapshot;
    }

    when(() => fixture.store.collectionGroup('participants')).thenReturn(query);
    when(
      () => query.where(any(), isEqualTo: any(named: 'isEqualTo')),
    ).thenReturn(query);
    final statuses = <Object?>[];
    when(
      () => query.where('status', isEqualTo: any(named: 'isEqualTo')),
    ).thenAnswer((invocation) {
      statuses.add(invocation.namedArguments[#isEqualTo]);
      return query;
    });
    when(() => query.orderBy('joinedAt')).thenReturn(query);
    var call = 0;
    when(() => query.get()).thenAnswer(
      (_) async => call++ == 0 ? result([stale, synced]) : result([legacy]),
    );
    // 自己發布的場次：一場暱稱過期要更新，一場已是新暱稱不重寫。
    final events = MockCollection();
    final organizedQuery = MockQuery();
    final staleEvent = MockEntry();
    when(() => staleEvent.data()).thenReturn({'organizerName': 'Google Name'});
    when(() => staleEvent.reference).thenReturn(MockDocument());
    final syncedEvent = MockEntry();
    when(() => syncedEvent.data()).thenReturn({'organizerName': '新暱稱'});
    when(() => syncedEvent.reference).thenReturn(MockDocument());
    when(() => fixture.store.collection('events')).thenReturn(events);
    when(
      () => events.where('organizerId', isEqualTo: 'google-user'),
    ).thenReturn(organizedQuery);
    when(
      () => organizedQuery.get(),
    ).thenAnswer((_) async => result([staleEvent, syncedEvent]));
    when(() => fixture.store.batch()).thenReturn(batch);
    final updates = <DocumentReference, Map<String, dynamic>>{};
    when(() => batch.update<Map<String, dynamic>>(any(), any())).thenAnswer((
      invocation,
    ) {
      updates[invocation.positionalArguments[0] as DocumentReference] =
          Map<String, dynamic>.from(invocation.positionalArguments[1] as Map);
    });
    when(() => batch.commit()).thenAnswer((_) async {});

    final user = fixture.repository.currentUser!;
    await fixture.repository.updateUser(
      User(
        id: user.id,
        name: '新暱稱',
        email: user.email,
        avatarUrl: user.avatarUrl,
        joinedGroups: user.joinedGroups,
      ),
    );

    expect(statuses, ['attending', 'waitlisted']);
    expect(updates[fixture.document], {'name': '新暱稱'});
    expect(updates[stale.reference], {'displayName': '新暱稱'});
    expect(updates[legacy.reference], {'displayName': '新暱稱'});
    expect(updates.containsKey(synced.reference), isFalse);
    expect(updates[staleEvent.reference], {'organizerName': '新暱稱'});
    expect(updates.containsKey(syncedEvent.reference), isFalse);
    verify(() => batch.commit()).called(1);
    expect(fixture.repository.currentUser!.name, '新暱稱');
  });

  group('登入時補上舊場次的主揪暱稱', () {
    late MockCollection events;
    late MockQuery organizedQuery;
    late MockBatch batch;
    late Map<DocumentReference, Map<String, dynamic>> updates;

    MockEntry eventDoc(Map<String, dynamic> data) {
      final doc = MockEntry();
      when(() => doc.data()).thenReturn(data);
      when(() => doc.reference).thenReturn(MockDocument());
      return doc;
    }

    setUp(() {
      registerFallbackValue(MockDocument());
      events = MockCollection();
      organizedQuery = MockQuery();
      batch = MockBatch();
      updates = {};
      when(() => fixture.store.collection('events')).thenReturn(events);
      when(
        () => events.where('organizerId', isEqualTo: 'google-user'),
      ).thenReturn(organizedQuery);
      when(() => fixture.store.batch()).thenReturn(batch);
      when(() => batch.update<Map<String, dynamic>>(any(), any())).thenAnswer((
        invocation,
      ) {
        updates[invocation.positionalArguments[0] as DocumentReference] =
            Map<String, dynamic>.from(invocation.positionalArguments[1] as Map);
      });
      when(() => batch.commit()).thenAnswer((_) async {});
    });

    test('只補缺少或過期的暱稱，已正確的不重寫', () async {
      final missing = eventDoc({});
      final outdated = eventDoc({'organizerName': '舊暱稱'});
      final current = eventDoc({'organizerName': 'Google Name'});
      final snapshot = MockQuerySnapshot();
      when(() => snapshot.docs).thenReturn([missing, outdated, current]);
      when(() => organizedQuery.get()).thenAnswer((_) async => snapshot);

      await fixture.repository.signInWithGoogle();
      await pumpEventQueue();

      expect(updates[missing.reference], {'organizerName': 'Google Name'});
      expect(updates[outdated.reference], {'organizerName': 'Google Name'});
      expect(updates.containsKey(current.reference), isFalse);
      verify(() => batch.commit()).called(1);
    });

    test('補資料失敗不影響登入', () async {
      when(() => organizedQuery.get()).thenThrow(StateError('offline'));
      await fixture.repository.signInWithGoogle();
      await pumpEventQueue();
      expect(fixture.repository.isAuthenticated, isTrue);
      verifyNever(() => batch.commit());
    });
  });
}
