import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/event_model.dart';

enum UserEventList { organized, attending, waitlisted }

class EventRepository extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _functions;
  final Future<void> Function(String eventId)? _cancelParticipation;

  EventRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    Future<void> Function(String eventId)? cancelParticipation,
  })
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _functions = functions,
      _cancelParticipation = cancelParticipation;

  Future<void> createEvent(Event event) async {
    if (event.organizerId.isEmpty ||
        event.sport == null ||
        event.district.trim().isEmpty ||
        event.venue.trim().isEmpty ||
        !event.startTime.isAfter(DateTime.now()) ||
        !event.endTime.isAfter(event.startTime) ||
        event.maxPlayers < 2 ||
        event.existingPlayers < 0 ||
        event.existingPlayers > event.maxPlayers ||
        (event.organizerPlaying && event.existingPlayers == 0) ||
        event.cost < 0) {
      throw ArgumentError('場次資料不完整或無效');
    }
    await _firestore.collection('events').doc(event.id).set(event.toMap());
  }

  Stream<List<Event>> searchUpcomingEvents({
    SportType? sport,
    String? district,
    DateTime? day,
  }) {
    final now = DateTime.now();
    final startOfDay = day == null
        ? now
        : DateTime(day.year, day.month, day.day);
    final start = startOfDay.isAfter(now) ? startOfDay : now;
    Query<Map<String, dynamic>> query = _firestore
        .collection('events')
        .where('status', isEqualTo: EventStatus.open.index)
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start));
    if (day != null) {
      query = query.where(
        'startTime',
        isLessThan: Timestamp.fromDate(
          DateTime(day.year, day.month, day.day + 1),
        ),
      );
    }
    if (sport != null) query = query.where('sport', isEqualTo: sport.name);
    final normalizedDistrict = district?.trim();
    if (normalizedDistrict != null && normalizedDistrict.isNotEmpty) {
      query = query.where('district', isEqualTo: normalizedDistrict);
    }
    return query
        .orderBy('startTime')
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Event.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<Event>> getEventsStream(String groupId) {
    return _firestore
        .collection('events')
        .where('groupId', isEqualTo: groupId)
        .orderBy('startTime', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Event.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<Event?> getEventStream(String id) {
    return _firestore.collection('events').doc(id).snapshots().map((doc) {
      if (doc.exists) return Event.fromMap(doc.data()!, doc.id);
      return null;
    });
  }

  Stream<EventParticipant?> getParticipationStream(
    String eventId,
    String userId,
  ) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .collection('participants')
        .doc(userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? EventParticipant.fromMap(snapshot.data()!, userId)
              : null,
        );
  }

  Stream<List<EventParticipant>> getParticipantsStream(String eventId) {
    return _firestore
        .collection('events')
        .doc(eventId)
        .collection('participants')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => EventParticipant.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<Event>> getUserEventsStream(String userId, UserEventList list) {
    if (list == UserEventList.organized) {
      return _firestore
          .collection('events')
          .where('organizerId', isEqualTo: userId)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => _sortEvents(
              snapshot.docs
                  .map((doc) => Event.fromMap(doc.data(), doc.id))
                  .toList(),
            ),
          );
    }

    final status = list == UserEventList.attending ? 'attending' : 'waitlisted';
    return _firestore
        .collectionGroup('participants')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: status)
        .orderBy('joinedAt')
        .limit(100)
        .snapshots()
        .asyncMap((snapshot) async {
          final eventSnapshots = await Future.wait(
            snapshot.docs.map((participant) {
              return participant.reference.parent.parent!.get();
            }),
          );
          return _sortEvents([
            for (final eventSnapshot in eventSnapshots)
              if (eventSnapshot.exists)
                Event.fromMap(eventSnapshot.data()!, eventSnapshot.id),
          ]);
        });
  }

  List<Event> _sortEvents(List<Event> events) {
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    return events;
  }

  Future<void> joinEvent(String eventId, String userId) async {
    final eventRef = _firestore.collection('events').doc(eventId);
    final participantRef = eventRef.collection('participants').doc(userId);
    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(eventRef);
      final participant = await transaction.get(participantRef);
      if (!snapshot.exists) throw StateError('找不到場次');
      final event = Event.fromMap(snapshot.data()!, eventId);
      if (!event.canAcceptParticipants(DateTime.now())) {
        throw StateError('場次已結束或不開放報名');
      }
      if (event.organizerPlaying && event.organizerId == userId) {
        return;
      }
      if (participant.exists) return;
      final isWaitlisted = event.isFull;
      transaction.update(eventRef, {
        isWaitlisted ? 'waitlistCount' : 'attendeeCount':
            isWaitlisted ? event.waitlistCount + 1 : event.attendeeCount + 1,
      });
      transaction.set(participantRef, {
        'eventId': eventId,
        'userId': userId,
        'status': isWaitlisted ? 'waitlisted' : 'attending',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> leaveEvent(String eventId, String userId) async {
    if (_cancelParticipation case final cancel?) {
      await cancel(eventId);
      return;
    }
    final functions =
        _functions ?? FirebaseFunctions.instanceFor(region: 'asia-east1');
    await functions.httpsCallable('leaveEvent').call({'eventId': eventId});
  }
}
