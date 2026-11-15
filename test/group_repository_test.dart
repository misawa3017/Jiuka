import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/features/events/models/event_model.dart';
import 'package:jiuka/features/groups/models/group_model.dart';
import 'package:jiuka/features/groups/models/season_model.dart';
import 'package:jiuka/features/groups/models/venue_model.dart';
import 'package:jiuka/features/groups/repositories/group_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'support/auth_fixture.dart';

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockEntry extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  test('球隊角色：隊長、幹部、隊員；舊球隊沒有幹部欄位', () {
    final group = Group.fromMap({
      'adminId': 'captain',
      'memberIds': ['captain', 'officer', 'member'],
      'officerIds': ['officer'],
    }, 'g');
    expect(group.isCaptain('captain'), isTrue);
    expect(group.isOfficer('officer'), isTrue);
    expect(group.canManage('officer'), isTrue);
    expect(group.canManage('member'), isFalse);
    expect(group.isMember('member'), isTrue);
    expect(group.isMember('stranger'), isFalse);
    expect(Group.fromMap({'adminId': 'a'}, 'old').officerIds, isEmpty);
    expect(
      Group.create(
        name: 'x',
        description: '',
        adminId: 'a',
        adminName: '小明',
      ).toMap()['officerIds'],
      isEmpty,
    );
  });

  test('常用場地資料往返，缺欄位時有預設值', () {
    const venue = Venue(
      id: 'v',
      name: '三重運動中心 3F',
      city: '新北市',
      district: '新北市三重區',
      costMode: CostMode.totalVenue,
      cost: 2400,
      maxPlayers: 12,
      notes: '停車：地下室',
    );
    final restored = Venue.fromMap(venue.toMap(), 'v');
    expect(restored.name, venue.name);
    expect(restored.costMode, CostMode.totalVenue);
    expect(restored.costLabel, '場租 2400 元');
    final legacy = Venue.fromMap({'name': 'x'}, 'old');
    expect(legacy.costMode, CostMode.perPerson);
    expect(legacy.maxPlayers, 10);
  });

  Season season({List<String> members = const ['a', 'b']}) => Season(
    id: 'q1',
    name: '2027 Q1 週三夜',
    venueId: 'v',
    venueName: '三重運動中心 3F',
    city: '新北市',
    district: '新北市三重區',
    startDate: '2027-01-06',
    endDate: '2027-03-31',
    dayOfWeek: 3,
    startTime: '20:00',
    endTime: '22:00',
    capacity: 12,
    totalRent: 28800,
    feePerMember: 3300,
    dropInFee: 150,
    organizerId: 'a',
    skipDates: const ['2027-02-10'],
    memberIds: members,
    paidMemberIds: const ['a'],
  );

  test('季租：算出每週打球日（扣掉停打日）、季費參考與已收季費', () {
    final q1 = season();
    final dates = q1.playDates;
    // 2027/1/6 到 3/31 共 13 個週三，扣掉 2/10 停打。
    expect(dates.length, 12);
    expect(dates.first, DateTime(2027, 1, 6));
    expect(dates.last, DateTime(2027, 3, 31));
    expect(dates.every((d) => d.weekday == DateTime.wednesday), isTrue);
    expect(dates.contains(DateTime(2027, 2, 10)), isFalse);
    expect(q1.suggestedFee, 14400);
    expect(q1.collectedFees, 3300);
    expect(season(members: const []).suggestedFee, isNull);
    expect(q1.weekdayLabel, '週三');
  });

  test('季租資料往返；舊資料或格式錯誤時有安全預設值', () {
    final restored = Season.fromMap(season().toMap(), 'q1');
    expect(restored.toMap(), season().toMap());
    final broken = Season.fromMap({'dayOfWeek': 9, 'dropInMode': 'x'}, 'x');
    expect(broken.dayOfWeek, 7);
    expect(broken.dropInMode, 'public');
    expect(broken.playDates, isEmpty);
    expect(season().copyWith(active: false).active, isFalse);
  });

  group('球隊管理操作寫入的內容', () {
    late MockStore store;
    late MockCollection groups;
    late MockDocument groupRef;
    late MockCollection requests;
    late MockDocument requestRef;
    late GroupRepository repository;
    late StreamController<Never> authChanges;
    final updates = <Map<Object, Object?>>[];
    (String, String, bool)? reviewed;

    setUp(() {
      store = MockStore();
      groups = MockCollection();
      groupRef = MockDocument();
      requests = MockCollection();
      requestRef = MockDocument();
      updates.clear();
      reviewed = null;
      authChanges = StreamController<Never>();
      final auth = MockAuth();
      when(() => auth.authStateChanges()).thenAnswer((_) => authChanges.stream);
      when(() => store.collection('groups')).thenReturn(groups);
      when(() => groups.doc('g')).thenReturn(groupRef);
      when(() => groupRef.collection('joinRequests')).thenReturn(requests);
      when(() => requests.doc('u')).thenReturn(requestRef);
      when(() => groupRef.update(any())).thenAnswer((invocation) async {
        updates.add(
          invocation.positionalArguments.first as Map<Object, Object?>,
        );
      });
      repository = GroupRepository(
        firestore: store,
        auth: auth,
        submitReview: (groupId, userId, approve) async =>
            reviewed = (groupId, userId, approve),
      );
    });

    tearDown(() async {
      repository.dispose();
      await authChanges.close();
    });

    test('申請入隊寫入本人暱稱與伺服器時間', () async {
      Map<String, dynamic>? written;
      when(() => requestRef.set(any())).thenAnswer((invocation) async {
        written = Map<String, dynamic>.from(
          invocation.positionalArguments.first as Map,
        );
      });
      await repository.requestToJoin('g', 'u', '阿德');
      expect(written!['userId'], 'u');
      expect(written!['displayName'], '阿德');
      expect(written!['createdAt'], isA<FieldValue>());
    });

    test('核准與拒絕交給 Cloud Function', () async {
      await repository.reviewJoinRequest('g', 'u', approve: true);
      expect(reviewed, ('g', 'u', true));
      await repository.reviewJoinRequest('g', 'u', approve: false);
      expect(reviewed, ('g', 'u', false));
    });

    test('移除成員一併清掉暱稱與幹部身分', () async {
      await repository.removeMember('g', 'u');
      expect(
        updates.single.keys,
        unorderedEquals(['memberIds', 'memberNames.u', 'officerIds']),
      );
    });

    test('常用場地：沒有 id 時新增，有 id 時覆寫同一筆', () async {
      final venues = MockCollection();
      final newRef = MockDocument();
      final existingRef = MockDocument();
      final writes = <MockDocument, Map<String, dynamic>>{};
      when(() => groupRef.collection('venues')).thenReturn(venues);
      when(() => venues.doc()).thenReturn(newRef);
      when(() => venues.doc('v1')).thenReturn(existingRef);
      for (final ref in [newRef, existingRef]) {
        when(() => ref.set(any())).thenAnswer((invocation) async {
          writes[ref] = Map<String, dynamic>.from(
            invocation.positionalArguments.first as Map,
          );
        });
      }
      const venue = Venue(
        id: '',
        name: '新莊體育館',
        city: '新北市',
        district: '新北市新莊區',
        costMode: CostMode.perPerson,
        cost: 180,
        maxPlayers: 10,
      );
      await repository.saveVenue('g', venue);
      await repository.saveVenue('g', Venue.fromMap(venue.toMap(), 'v1'));
      expect(writes[newRef]!['name'], '新莊體育館');
      expect(writes[existingRef]!['cost'], 180);
      expect(writes[newRef]!.containsKey('id'), isFalse);
    });

    test('季租：只更新指定的欄位，其他設定不動', () async {
      final seasons = MockCollection();
      final seasonRef = MockDocument();
      Map<Object, Object?>? written;
      when(() => groupRef.collection('seasons')).thenReturn(seasons);
      when(() => seasons.doc('q1')).thenReturn(seasonRef);
      when(() => seasonRef.update(any())).thenAnswer((invocation) async {
        written = invocation.positionalArguments.first as Map<Object, Object?>;
      });
      await repository.updateSeason('g', 'q1', paidMemberIds: ['a', 'b']);
      expect(written, {
        'paidMemberIds': ['a', 'b'],
      });
    });

    test('臨打收入：已付的非季租成員 × 人數 × 臨打費，取消的場次不算', () async {
      final events = MockCollection();
      final eventRef = MockDocument();
      final participants = MockCollection();
      final snapshot = MockQuerySnapshot();
      MockEntry entry(Map<String, dynamic> data, String id) {
        final doc = MockEntry();
        when(() => doc.data()).thenReturn(data);
        when(() => doc.id).thenReturn(id);
        return doc;
      }

      when(() => store.collection('events')).thenReturn(events);
      when(() => events.doc('e1')).thenReturn(eventRef);
      when(() => eventRef.collection('participants')).thenReturn(participants);
      when(() => participants.get()).thenAnswer((_) async => snapshot);
      final docs = [
        entry({'status': 'attending', 'seasonMember': true, 'paid': true}, 'a'),
        entry({'status': 'attending', 'paid': true, 'guests': 1}, 'b'),
        entry({'status': 'attending', 'paid': false}, 'c'),
      ];
      when(() => snapshot.docs).thenReturn(docs);
      Event game(String id, EventStatus status) => Event(
        id: id,
        groupId: 'g',
        seasonId: 'q1',
        startTime: DateTime(2027, 1, 6, 20),
        endTime: DateTime(2027, 1, 6, 22),
        venue: '三重運動中心',
        cost: 150,
        maxPlayers: 12,
        status: status,
      );
      final income = await repository.seasonDropInIncome([
        game('e1', EventStatus.open),
        game('e2', EventStatus.cancelled),
      ]);
      // 只有 b（帶 1 位朋友，共 2 人）已付：2 × 150。
      expect(income, 300);
      verifyNever(() => events.doc('e2'));
    });

    test('立即開出季租場次交給 Cloud Function', () async {
      final calls = <(String, String)>[];
      final auth = MockAuth();
      final changes = StreamController<Never>();
      when(() => auth.authStateChanges()).thenAnswer((_) => changes.stream);
      final repo = GroupRepository(
        firestore: store,
        auth: auth,
        submitOpenSeason: (groupId, seasonId) async {
          calls.add((groupId, seasonId));
          return ['2027-01-06'];
        },
      );
      expect(await repo.openSeasonEventsNow('g', 'q1'), ['2027-01-06']);
      expect(calls, [('g', 'q1')]);
      repo.dispose();
      await changes.close();
    });

    test('任免幹部與轉移隊長只改對應欄位', () async {
      await repository.setOfficer('g', 'u', true);
      await repository.transferCaptain('g', 'u');
      expect(updates[0].keys, ['officerIds']);
      expect(updates[1]['adminId'], 'u');
      expect(updates[1].keys, unorderedEquals(['adminId', 'officerIds']));
    });
  });
}
