import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:jiuka/features/events/models/event_model.dart';
import 'package:jiuka/features/events/repositories/event_repository.dart';
import 'support/auth_fixture.dart';

class MockBatch extends Mock implements WriteBatch {}

void main() {
  late MockStore store;
  late MockCollection events;
  late MockCollection participants;
  late MockDocument eventRef;
  late MockDocument participantRef;
  late MockSnapshot eventSnapshot;
  late MockSnapshot participantSnapshot;
  late MockTransaction transaction;
  late EventRepository repository;
  late Map<String, dynamic> eventData;
  var participantExists = false;
  Map<String, dynamic>? participantData;

  setUp(() {
    store = MockStore();
    events = MockCollection();
    participants = MockCollection();
    eventRef = MockDocument();
    participantRef = MockDocument();
    eventSnapshot = MockSnapshot();
    participantSnapshot = MockSnapshot();
    transaction = MockTransaction();
    participantExists = false;
    repository = EventRepository(firestore: store);
    eventData = Event(
      id: 'game',
      groupId: '',
      organizerId: 'owner',
      sport: SportType.badminton,
      city: '臺北市',
      district: '臺北市大安區',
      existingPlayers: 1,
      organizerPlaying: true,
      startTime: DateTime.now().add(const Duration(days: 2)),
      endTime: DateTime.now().add(const Duration(days: 2, hours: 2)),
      venue: 'Court',
      cost: 1000,
      costMode: CostMode.totalVenue,
      maxPlayers: 2,
    ).toMap();

    when(() => store.collection('events')).thenReturn(events);
    when(() => events.doc('game')).thenReturn(eventRef);
    when(() => eventRef.collection('participants')).thenReturn(participants);
    when(() => participants.doc('first')).thenReturn(participantRef);
    when(
      () => transaction.get(eventRef),
    ).thenAnswer((_) async => eventSnapshot);
    when(
      () => transaction.get(participantRef),
    ).thenAnswer((_) async => participantSnapshot);
    when(() => eventSnapshot.exists).thenReturn(true);
    when(() => eventSnapshot.data()).thenAnswer((_) => eventData);
    when(() => participantSnapshot.exists).thenAnswer((_) => participantExists);
    when(() => transaction.update(eventRef, any())).thenAnswer((invocation) {
      eventData.addAll(
        Map<String, dynamic>.from(invocation.positionalArguments[1] as Map),
      );
      return transaction;
    });
    when(
      () => transaction.set<Map<String, dynamic>>(participantRef, any()),
    ).thenAnswer((invocation) {
      participantExists = true;
      participantData = Map<String, dynamic>.from(
        invocation.positionalArguments[1] as Map,
      );
      return transaction;
    });
    when(() => store.runTransaction<void>(any())).thenAnswer((invocation) {
      final operation =
          invocation.positionalArguments.first
              as Future<void> Function(Transaction);
      return operation(transaction);
    });
  });

  tearDown(() => repository.dispose());

  test(
    'join records a private participant and updates only the count',
    () async {
      await repository.joinEvent('game', 'first', '小明');
      expect(eventData['attendeeCount'], 1);
      expect(eventData.containsKey('attendeeIds'), isFalse);
      expect(participantData!['displayName'], '小明');
      expect(participantData!['status'], 'attending');
      verify(
        () => transaction.set<Map<String, dynamic>>(participantRef, any()),
      ).called(1);
    },
  );

  test('帶朋友報名：整組放得下進正取，計數加整組人數', () async {
    // 名額 4、已有主揪 1 人。
    eventData['maxPlayers'] = 4;
    await repository.joinEvent('game', 'first', '小明', guests: 2);
    expect(eventData['attendeeCount'], 3);
    expect(participantData!['guests'], 2);
    expect(participantData!['status'], 'attending');
  });

  test('帶朋友報名：名額不夠或已有人候補時整組進候補', () async {
    eventData['maxPlayers'] = 3;
    await repository.joinEvent('game', 'first', '小明', guests: 2);
    expect(eventData['waitlistCount'], 3);
    expect(eventData['attendeeCount'], 0);
    expect(participantData!['status'], 'waitlisted');
  });

  test('已有人候補時，即使有空位也排候補', () async {
    eventData['maxPlayers'] = 10;
    eventData['waitlistCount'] = 2;
    await repository.joinEvent('game', 'first', '小明');
    expect(eventData['waitlistCount'], 3);
    expect(participantData!['status'], 'waitlisted');
  });

  test('同行朋友超過 3 人不送出', () async {
    expect(
      () => repository.joinEvent('game', 'first', '小明', guests: 4),
      throwsArgumentError,
    );
  });

  test('join is idempotent for an existing participant', () async {
    participantExists = true;
    await repository.joinEvent('game', 'first', '小明');
    expect(eventData['attendeeCount'], 0);
    verifyNever(() => transaction.update(eventRef, any()));
  });

  test('leave delegates to the trusted callable adapter', () async {
    String? leftEventId;
    repository = EventRepository(
      firestore: store,
      cancelParticipation: (eventId) async => leftEventId = eventId,
    );
    await repository.leaveEvent('game', 'first');
    expect(leftEventId, 'game');
  });

  test('確定費用寫入金額與伺服器時間，負數不送出', () async {
    Map<Object, Object?>? written;
    when(() => eventRef.update(any())).thenAnswer((invocation) async {
      written = invocation.positionalArguments.first as Map<Object, Object?>;
    });
    await repository.confirmCost('game', 250);
    expect(written!['finalCostPerPerson'], 250);
    expect(written!['costConfirmedAt'], isA<FieldValue>());
    expect(() => repository.confirmCost('game', -1), throwsArgumentError);
  });

  group('限熟人場次', () {
    test('邀請碼是 6 位數字', () {
      for (var i = 0; i < 20; i++) {
        expect(
          EventRepository.generateInviteCode(),
          matches(RegExp(r'^\d{6}$')),
        );
      }
    });

    test('發布限熟人場次時，場次與邀請碼同一批寫入；邀請碼格式不對不送出', () async {
      registerFallbackValue(MockDocument());
      final batch = MockBatch();
      final privateCollection = MockCollection();
      final inviteRef = MockDocument();
      final writes = <DocumentReference, Map<String, dynamic>>{};
      when(() => store.batch()).thenReturn(batch);
      when(() => eventRef.collection('private')).thenReturn(privateCollection);
      when(() => privateCollection.doc('invite')).thenReturn(inviteRef);
      when(() => batch.set<Map<String, dynamic>>(any(), any())).thenAnswer((
        invocation,
      ) {
        writes[invocation.positionalArguments[0] as DocumentReference] =
            Map<String, dynamic>.from(invocation.positionalArguments[1] as Map);
      });
      when(() => batch.commit()).thenAnswer((_) async {});

      final game = Event.fromMap(
        eventData,
        'game',
      ).copyWith(status: EventStatus.inviteOnly);
      expect(
        () => repository.createEvent(game, inviteCode: '1234'),
        throwsArgumentError,
      );
      await repository.createEvent(game, inviteCode: '482913');
      expect(writes[eventRef]!['status'], 3);
      expect(writes[inviteRef], {'code': '482913'});
      verify(() => batch.commit()).called(1);
    });

    test('報名限熟人場次會帶上邀請碼，公開場次不帶', () async {
      eventData['status'] = EventStatus.inviteOnly.index;
      await repository.joinEvent('game', 'first', '小明', inviteCode: '482913');
      expect(participantData!['inviteCode'], '482913');

      eventData
        ..['status'] = EventStatus.open.index
        ..['attendeeCount'] = 0;
      participantExists = false;
      await repository.joinEvent('game', 'first', '小明');
      expect(participantData!.containsKey('inviteCode'), isFalse);
    });

    test('開放公開報名：狀態改回公開並記錄時間', () async {
      Map<Object, Object?>? written;
      when(() => eventRef.update(any())).thenAnswer((invocation) async {
        written = invocation.positionalArguments.first as Map<Object, Object?>;
      });
      await repository.publishEvent('game');
      expect(written!['status'], EventStatus.open.index);
      expect(written!['publishedAt'], isA<FieldValue>());
    });
  });

  test('記錄出席與收款只寫入有指定的欄位', () async {
    final writes = <Map<Object, Object?>>[];
    when(() => participantRef.update(any())).thenAnswer((invocation) async {
      writes.add(invocation.positionalArguments.first as Map<Object, Object?>);
    });
    await repository.markParticipant('game', 'first', attended: true);
    await repository.markParticipant('game', 'first', paid: false);
    expect(writes, [
      {'attended': true},
      {'paid': false},
    ]);
  });

  test('主揪或管理者移除報名者交給 Cloud Function', () async {
    (String, String)? removed;
    repository = EventRepository(
      firestore: store,
      submitRemoval: (eventId, userId) async => removed = (eventId, userId),
    );
    await repository.removeParticipant('game', 'bob');
    expect(removed, ('game', 'bob'));
  });

  group('主揪編輯與取消場次', () {
    late Event game;
    String? submittedId;
    Map<String, dynamic>? submitted;

    setUp(() {
      submittedId = null;
      submitted = null;
      repository = EventRepository(
        firestore: store,
        submitEventUpdate: (eventId, event) async {
          submittedId = eventId;
          submitted = event;
        },
      );
      game = Event.fromMap(eventData, 'game').copyWith(attendeeCount: 1);
    });

    test('只送出可編輯欄位，時間以毫秒傳給 Cloud Function', () async {
      final start = DateTime.now().add(const Duration(days: 3));
      await repository.updateEvent(
        game.copyWith(
          venue: '  新球館  ',
          maxPlayers: 6,
          startTime: start,
          endTime: start.add(const Duration(hours: 2)),
        ),
      );
      expect(submittedId, 'game');
      expect(submitted!['venue'], '新球館');
      expect(submitted!['maxPlayers'], 6);
      expect(submitted!['startTime'], start.millisecondsSinceEpoch);
      for (final key in ['organizerId', 'status', 'attendeeCount', 'groupId']) {
        expect(submitted!.containsKey(key), isFalse, reason: key);
      }
    });

    test('地區必須來自清單，且鄉鎮市區屬於該縣市', () async {
      for (final (city, district) in [
        ('臺北市', '新北市板橋區'),
        ('臺北市', '臺北市'),
        ('臺北市', '臺北市不存在區'),
        ('台北市', '台北市大安區'),
        ('', '臺北市大安區'),
      ]) {
        expect(
          () => repository.updateEvent(
            game.copyWith(city: city, district: district),
          ),
          throwsArgumentError,
          reason: '$city / $district',
        );
      }
      expect(submitted, isNull);
      await repository.updateEvent(
        game.copyWith(city: '新北市', district: '新北市板橋區'),
      );
      expect(submitted!['city'], '新北市');
      expect(submitted!['district'], '新北市板橋區');
    });

    test('活動名稱一併送出；超過 40 字或前後空白不送出', () async {
      await repository.updateEvent(game.copyWith(title: '週三晚間籃球'));
      expect(submitted!['title'], '週三晚間籃球');
      submitted = null;
      for (final title in ['名' * 41, ' 前後空白 ']) {
        expect(
          () => repository.updateEvent(game.copyWith(title: title)),
          throwsArgumentError,
          reason: title,
        );
      }
      expect(submitted, isNull);
    });

    test('取消期限一併送出，不在選項內的值不送出', () async {
      await repository.updateEvent(game.copyWith(cancelDeadlineHours: 24));
      expect(submitted!['cancelDeadlineHours'], 24);
      submitted = null;
      expect(
        () => repository.updateEvent(game.copyWith(cancelDeadlineHours: 5)),
        throwsArgumentError,
      );
      expect(submitted, isNull);
    });

    test('名額低於已約人數加正取人數時，不送出', () async {
      // 已約 1 人 + 正取 1 人 = 2，名額改成 1 不合法。
      expect(
        () => repository.updateEvent(game.copyWith(maxPlayers: 1)),
        throwsArgumentError,
      );
      expect(submitted, isNull);
    });

    test('取消場次只寫入狀態與伺服器時間', () async {
      Map<Object, Object?>? written;
      when(() => eventRef.update(any())).thenAnswer((invocation) async {
        written = invocation.positionalArguments.first as Map<Object, Object?>;
      });
      await repository.cancelEvent('game');
      expect(written!.keys, unorderedEquals(['status', 'cancelledAt']));
      expect(written!['status'], EventStatus.cancelled.index);
      expect(written!['cancelledAt'], isA<FieldValue>());
    });
  });
}
