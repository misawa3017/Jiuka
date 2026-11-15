import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/features/events/models/event_model.dart';
import 'package:jiuka/features/groups/models/group_model.dart';

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

  test('球隊成員暱稱：建立時寫入管理員暱稱，舊球隊沒有時為空', () {
    final group = Group.create(
      name: '球友團',
      description: '',
      adminId: 'a',
      adminName: '小明',
    );
    expect(group.toMap()['memberNames'], {'a': '小明'});
    final restored = Group.fromMap({
      ...group.toMap(),
      'memberIds': ['a', 'b'],
      'memberNames': {'a': '小明', 'b': ' 小華 ', 'c': 123},
    }, 'g');
    expect(restored.memberNames, {'a': '小明', 'b': '小華'});
    expect(Group.fromMap({'adminId': 'a'}, 'old').memberNames, isEmpty);
  });

  test('限熟人場次仍接受報名，狀態數字往返不變', () {
    final private = event().copyWith(status: EventStatus.inviteOnly);
    expect(private.isInviteOnly, isTrue);
    expect(private.isAcceptingSignups, isTrue);
    expect(private.canAcceptParticipants(DateTime(2026, 12, 1)), isTrue);
    expect(private.toMap()['status'], 3);
    expect(Event.fromMap(private.toMap(), 'e').status, EventStatus.inviteOnly);
    final cancelled = event().copyWith(status: EventStatus.cancelled);
    expect(cancelled.isAcceptingSignups, isFalse);
  });

  test('同行朋友：一組人數含本人，舊資料視為 0 位朋友', () {
    expect(
      EventParticipant.fromMap({
        'status': 'attending',
        'guests': 2,
      }, 'u').partySize,
      3,
    );
    expect(EventParticipant.fromMap({'status': 'attending'}, 'u').partySize, 1);
    final game = event(existing: 6, total: 10);
    expect(game.fitsParty(4), isTrue);
    expect(game.fitsParty(5), isFalse);
    expect(game.copyWith(waitlistCount: 1).fitsParty(1), isFalse);
  });

  test('取消期限：預設不限；有期限時開始前 N 小時內算超過', () {
    final start = event().startTime;
    expect(event().cancelDeadlineHours, 0);
    expect(
      event().isPastCancelDeadline(start.subtract(const Duration(minutes: 1))),
      isFalse,
    );
    final strict = event().copyWith(cancelDeadlineHours: 6);
    expect(
      strict.isPastCancelDeadline(start.subtract(const Duration(hours: 7))),
      isFalse,
    );
    expect(
      strict.isPastCancelDeadline(start.subtract(const Duration(hours: 5))),
      isTrue,
    );
    expect(Event.fromMap(strict.toMap(), 'e').cancelDeadlineHours, 6);
    final legacy = event().toMap()..remove('cancelDeadlineHours');
    expect(Event.fromMap(legacy, 'old').cancelDeadlineHours, 0);
  });

  test('最終費用：建議金額依費用方式計算，確定後卡片顯示已確定', () {
    expect(event().suggestedFinalCost, 150);
    final rent = event(mode: CostMode.totalVenue, cost: 1000, existing: 3);
    expect(rent.suggestedFinalCost, 334);
    expect(rent.isCostConfirmed, isFalse);
    final confirmed = Event.fromMap(
      rent.toMap()
        ..['finalCostPerPerson'] = 300
        ..['costConfirmedAt'] = Timestamp.fromDate(DateTime(2026, 11, 20)),
      'e',
    );
    expect(confirmed.isCostConfirmed, isTrue);
    expect(confirmed.finalCostPerPerson, 300);
    expect(rent.toMap().containsKey('finalCostPerPerson'), isFalse);
  });

  test('報名者的出席與收款狀態，舊資料預設為未記錄', () {
    final marked = EventParticipant.fromMap({
      'status': 'attending',
      'attended': true,
      'paid': true,
    }, 'u1');
    expect(marked.attended, isTrue);
    expect(marked.paid, isTrue);
    final legacy = EventParticipant.fromMap({'status': 'attending'}, 'u2');
    expect(legacy.attended, isFalse);
    expect(legacy.paid, isFalse);
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
