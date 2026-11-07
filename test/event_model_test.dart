import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/features/events/models/event_model.dart';

void main() {
  Event event({
    int existing = 6,
    int attending = 0,
    int total = 10,
    CostMode mode = CostMode.perPerson,
    int cost = 150,
  }) => Event(
    id: 'event-1',
    groupId: '',
    organizerId: 'owner',
    sport: SportType.basketball,
    district: '台北市大安區',
    existingPlayers: existing,
    organizerPlaying: true,
    startTime: DateTime(2027, 1, 1, 19),
    endTime: DateTime(2027, 1, 1, 21),
    venue: '大安運動中心',
    cost: cost,
    costMode: mode,
    maxPlayers: total,
    attendeeCount: attending,
  );

  test('主揪與已約球友只占一次名額', () {
    final game = event();
    expect(game.occupiedCount, 6);
    expect(game.spotsLeft, 4);
    expect(game.isFull, isFalse);
    final full = game.copyWith(attendeeCount: 4);
    expect(full.spotsLeft, 0);
    expect(full.isFull, isTrue);
  });

  test('固定費用與整場場租清楚區分，加入後才計入估算', () {
    expect(event().estimatedCostPerPerson(joining: true), 150);
    final rent = event(mode: CostMode.totalVenue, cost: 1200);
    expect(rent.estimatedCostPerPerson(), 200);
    expect(rent.estimatedCostPerPerson(joining: true), 172);
    expect(
      event(existing: 0, mode: CostMode.totalVenue).estimatedCostPerPerson(),
      isNull,
    );
  });

  test('新場次資料可往返，舊場次預設固定費用及零既有人數', () {
    final game = event(mode: CostMode.totalVenue, cost: 1200);
    final restored = Event.fromMap(game.toMap(), game.id);
    expect(restored.sport, SportType.basketball);
    expect(restored.costMode, CostMode.totalVenue);
    expect(restored.existingPlayers, 6);
    expect(restored.organizerPlaying, isTrue);

    final legacy = Event.fromMap({
      'startTime': game.toMap()['startTime'],
      'endTime': game.toMap()['endTime'],
      'venue': '舊場次',
      'cost': 150,
      'maxPlayers': 10,
    }, 'old');
    expect(legacy.costMode, CostMode.perPerson);
    expect(legacy.existingPlayers, 0);
    expect(legacy.sport, isNull);
  });
}
