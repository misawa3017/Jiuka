import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:jiuka/features/events/models/event_model.dart';
import 'package:jiuka/features/events/repositories/event_repository.dart';
import 'support/auth_fixture.dart';

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
      district: 'Taipei',
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
      await repository.joinEvent('game', 'first');
      expect(eventData['attendeeCount'], 1);
      expect(eventData.containsKey('attendeeIds'), isFalse);
      verify(
        () => transaction.set<Map<String, dynamic>>(participantRef, any()),
      ).called(1);
    },
  );

  test('join is idempotent for an existing participant', () async {
    participantExists = true;
    await repository.joinEvent('game', 'first');
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
