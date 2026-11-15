import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/features/events/models/event_model.dart';
import 'package:jiuka/features/groups/models/group_model.dart';
import 'package:jiuka/features/groups/models/venue_model.dart';
import 'package:jiuka/features/groups/repositories/group_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'support/auth_fixture.dart';

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

    test('任免幹部與轉移隊長只改對應欄位', () async {
      await repository.setOfficer('g', 'u', true);
      await repository.transferCaptain('g', 'u');
      expect(updates[0].keys, ['officerIds']);
      expect(updates[1]['adminId'], 'u');
      expect(updates[1].keys, unorderedEquals(['adminId', 'officerIds']));
    });
  });
}
