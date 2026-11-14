import 'package:cloud_firestore/cloud_firestore.dart';
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
    city: '臺北市',
    district: '臺北市大安區',
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
    expect(legacy.updatedAt, isNull);
    expect(legacy.cancelledAt, isNull);
  });

  test('主揪暱稱可往返，舊場次沒有時為空字串', () {
    final game = event().copyWith(organizerName: '小明');
    expect(game.toMap()['organizerName'], '小明');
    expect(Event.fromMap(game.toMap(), 'e').organizerName, '小明');
    final legacy = event().toMap()..remove('organizerName');
    expect(Event.fromMap(legacy, 'old').organizerName, '');
  });

  test('活動名稱可往返；沒填或舊場次以球館名稱當標題', () {
    final named = event().copyWith(title: '週三晚間籃球');
    expect(named.toMap()['title'], '週三晚間籃球');
    expect(Event.fromMap(named.toMap(), 'e').displayTitle, '週三晚間籃球');
    expect(event().displayTitle, '大安運動中心');
    final legacy = event().toMap()..remove('title');
    expect(Event.fromMap(legacy, 'old').title, '');
    expect(Event.fromMap(legacy, 'old').displayTitle, '大安運動中心');
  });

  test('存入縣市；舊場次沒有縣市時從地區全名推算', () {
    expect(event().toMap()['city'], '臺北市');
    expect(Event.fromMap(event().toMap(), 'e').city, '臺北市');
    final legacy = event().toMap()
      ..remove('city')
      ..['district'] = '台中市西屯區';
    expect(Event.fromMap(legacy, 'old').city, '臺中市');
    final unknown = event().toMap()
      ..remove('city')
      ..['district'] = '大安';
    expect(Event.fromMap(unknown, 'old').city, '');
  });

  test('讀取編輯與取消時間，但發布時不寫入這兩個欄位', () {
    final edited = DateTime(2026, 12, 1, 10, 30);
    final map = event().toMap()
      ..['updatedAt'] = Timestamp.fromDate(edited)
      ..['cancelledAt'] = Timestamp.fromDate(edited);
    final restored = Event.fromMap(map, 'event-1');
    expect(restored.updatedAt, edited);
    expect(restored.cancelledAt, edited);
    expect(restored.copyWith(venue: '新球館').updatedAt, edited);
    expect(event().toMap().containsKey('updatedAt'), isFalse);
    expect(event().toMap().containsKey('cancelledAt'), isFalse);
  });
}
