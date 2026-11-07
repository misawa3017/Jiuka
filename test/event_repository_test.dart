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
    when(() => transaction.get(eventRef)).thenAnswer((_) async => eventSnapshot);
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
    when(() => transaction.set<Map<String, dynamic>>(participantRef, any()))
        .thenAnswer((invocation) {
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

  test('join records a private participant and updates only the count', () async {
    await repository.joinEvent('game', 'first');
    expect(eventData['attendeeCount'], 1);
    expect(eventData.containsKey('attendeeIds'), isFalse);
    verify(() => transaction.set<Map<String, dynamic>>(participantRef, any()))
        .called(1);
  });

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
}
