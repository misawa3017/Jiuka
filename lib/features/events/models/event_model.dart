import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/taiwan_districts.dart';

enum EventStatus { open, closed, cancelled }

enum SportType { basketball, badminton }

enum CostMode { perPerson, totalVenue }

enum EventParticipationStatus { attending, waitlisted }

String _stringValue(Object? value) => value is String ? value : '';

int _intValue(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

bool _boolValue(Object? value, bool fallback) =>
    value is bool ? value : fallback;

DateTime? _optionalDateValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

DateTime _dateValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int _legacyRosterCount(Object? value) => value is List ? value.length : 0;

class EventParticipant {
  final String userId;
  final EventParticipationStatus status;
  final DateTime joinedAt;

  /// 報名時的暱稱；改暱稱時會同步。舊資料沒有這個欄位時為空字串。
  final String displayName;

  /// 主揪記錄的出席與收款狀態；未記錄時為 false。
  final bool attended;
  final bool paid;

  const EventParticipant({
    required this.userId,
    required this.status,
    required this.joinedAt,
    this.displayName = '',
    this.attended = false,
    this.paid = false,
  });

  factory EventParticipant.fromMap(Map<String, dynamic> map, String userId) =>
      EventParticipant(
        userId: userId,
        status: map['status'] == 'waitlisted'
            ? EventParticipationStatus.waitlisted
            : EventParticipationStatus.attending,
        joinedAt: map['joinedAt'] is Timestamp
            ? (map['joinedAt'] as Timestamp).toDate()
            : DateTime.fromMillisecondsSinceEpoch(0),
        displayName: _stringValue(map['displayName']).trim(),
        attended: _boolValue(map['attended'], false),
        paid: _boolValue(map['paid'], false),
      );
}

class Event {
  final String id;
  final String groupId;
  final String organizerId;

  /// 主揪暱稱，公開顯示在場次上；舊場次沒有時為空字串。
  final String organizerName;
  final SportType? sport;

  /// 主揪自訂的活動名稱（選填，最多 [maxTitleLength] 字）；空字串時畫面以球館名稱當標題。
  final String title;
  static const maxTitleLength = 40;

  /// 縣市，例如「臺北市」；用於首頁只選縣市時的篩選。
  final String city;

  /// 縣市＋鄉鎮市區全名，例如「臺北市大安區」。
  final String district;
  final String description;
  final int existingPlayers;
  final DateTime startTime;
  final DateTime endTime;
  final String venue;

  /// 每人固定費用，或整場場租；由 costMode 決定。
  final int cost;
  final CostMode costMode;
  final bool organizerPlaying;
  final int maxPlayers;
  final int attendeeCount;
  final int waitlistCount;
  final EventStatus status;
  final bool isRecurring;

  /// 球友自行取消的期限：開始前幾小時；0 表示開始前都可取消。只限制正取。
  final int cancelDeadlineHours;
  static const cancelDeadlineOptions = [0, 2, 6, 24];

  /// 主揪最後一次編輯場次的時間；從未編輯為 null。只由後端寫入。
  final DateTime? updatedAt;

  /// 主揪取消場次的時間；未取消為 null。
  final DateTime? cancelledAt;

  /// 主揪在場次開始後確定的每人最終費用；未確定為 null，畫面顯示預估。
  final int? finalCostPerPerson;
  final DateTime? costConfirmedAt;

  Event({
    required this.id,
    required this.groupId,
    this.organizerId = '',
    this.organizerName = '',
    this.sport,
    this.title = '',
    this.city = '',
    this.district = '',
    this.description = '',
    this.existingPlayers = 0,
    required this.startTime,
    required this.endTime,
    required this.venue,
    required this.cost,
    this.costMode = CostMode.perPerson,
    this.organizerPlaying = false,
    required this.maxPlayers,
    this.attendeeCount = 0,
    this.waitlistCount = 0,
    this.status = EventStatus.open,
    this.isRecurring = false,
    this.cancelDeadlineHours = 0,
    this.updatedAt,
    this.cancelledAt,
    this.finalCostPerPerson,
    this.costConfirmedAt,
  });

  bool get isCostConfirmed => finalCostPerPerson != null;

  /// 正取球友是否已超過自行取消的期限（與 Cloud Function 判斷一致）。
  bool isPastCancelDeadline(DateTime now) =>
      cancelDeadlineHours > 0 &&
      now.isAfter(startTime.subtract(Duration(hours: cancelDeadlineHours)));

  /// 確定費用時的建議金額：固定費用沿用原價；場租以已確定人數平分並無條件進位。
  int get suggestedFinalCost {
    if (costMode == CostMode.perPerson) return cost;
    return occupiedCount == 0 ? cost : (cost / occupiedCount).ceil();
  }

  /// 畫面上的標題：有活動名稱用活動名稱，否則用球館名稱。
  String get displayTitle => title.isNotEmpty ? title : venue;

  int get occupiedCount => existingPlayers + attendeeCount;
  int get spotsLeft => (maxPlayers - occupiedCount).clamp(0, maxPlayers);
  bool get isFull => spotsLeft == 0;
  bool canAcceptParticipants(DateTime now) =>
      status == EventStatus.open &&
      startTime.isAfter(now) &&
      endTime.isAfter(startTime);

  int? estimatedCostPerPerson({bool joining = false}) {
    if (costMode == CostMode.perPerson) return cost;
    final players = occupiedCount + (joining ? 1 : 0);
    return players == 0 ? null : (cost / players).ceil();
  }

  Map<String, dynamic> toMap() {
    return {
      'groupId': groupId,
      'organizerId': organizerId,
      'organizerName': organizerName,
      'title': title,
      'sport': sport?.name,
      'city': city,
      'district': district,
      'description': description,
      'existingPlayers': existingPlayers,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'venue': venue,
      'cost': cost,
      'costMode': costMode.name,
      'organizerPlaying': organizerPlaying,
      'maxPlayers': maxPlayers,
      'attendeeCount': attendeeCount,
      'waitlistCount': waitlistCount,
      'status': status.index,
      'isRecurring': isRecurring,
      'cancelDeadlineHours': cancelDeadlineHours,
    };
  }

  factory Event.fromMap(Map<String, dynamic> map, String id) {
    final rawStatus = map['status'];
    final statusIndex = rawStatus == null
        ? EventStatus.open.index
        : rawStatus is int
        ? rawStatus
        : -1;
    return Event(
      id: id,
      groupId: _stringValue(map['groupId']),
      organizerId: _stringValue(map['organizerId']),
      organizerName: _stringValue(map['organizerName']).trim(),
      sport: SportType.values
          .where((sport) => sport.name == map['sport'])
          .firstOrNull,
      title: _stringValue(map['title']).trim(),
      // 舊場次沒有 city 欄位，從地區全名推算。
      city: _stringValue(map['city']).isNotEmpty
          ? _stringValue(map['city'])
          : cityOfDistrict(_stringValue(map['district'])) ?? '',
      district: _stringValue(map['district']),
      description: _stringValue(map['description']),
      existingPlayers: _intValue(map['existingPlayers'], 0),
      startTime: _dateValue(map['startTime']),
      endTime: _dateValue(map['endTime']),
      venue: _stringValue(map['venue']),
      cost: _intValue(map['cost'], 0),
      costMode:
          CostMode.values
              .where((mode) => mode.name == map['costMode'])
              .firstOrNull ??
          CostMode.perPerson,
      organizerPlaying: _boolValue(map['organizerPlaying'], false),
      maxPlayers: _intValue(map['maxPlayers'], 20),
      attendeeCount: _intValue(
        map['attendeeCount'],
        _legacyRosterCount(map['attendeeIds']),
      ),
      waitlistCount: _intValue(
        map['waitlistCount'],
        _legacyRosterCount(map['waitlistIds']),
      ),
      // Unknown or malformed persisted statuses must never make an event open.
      status: statusIndex >= 0 && statusIndex < EventStatus.values.length
          ? EventStatus.values[statusIndex]
          : EventStatus.cancelled,
      isRecurring: _boolValue(map['isRecurring'], false),
      cancelDeadlineHours: _intValue(map['cancelDeadlineHours'], 0),
      updatedAt: _optionalDateValue(map['updatedAt']),
      cancelledAt: _optionalDateValue(map['cancelledAt']),
      finalCostPerPerson: map['finalCostPerPerson'] is num
          ? (map['finalCostPerPerson'] as num).toInt()
          : null,
      costConfirmedAt: _optionalDateValue(map['costConfirmedAt']),
    );
  }

  // Create copyWith for immutability updates
  Event copyWith({
    String? id,
    String? groupId,
    String? organizerId,
    String? organizerName,
    SportType? sport,
    String? title,
    String? city,
    String? district,
    String? description,
    int? existingPlayers,
    DateTime? startTime,
    DateTime? endTime,
    String? venue,
    int? cost,
    CostMode? costMode,
    bool? organizerPlaying,
    int? maxPlayers,
    int? attendeeCount,
    int? waitlistCount,
    EventStatus? status,
    bool? isRecurring,
    int? cancelDeadlineHours,
  }) {
    return Event(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      organizerId: organizerId ?? this.organizerId,
      organizerName: organizerName ?? this.organizerName,
      sport: sport ?? this.sport,
      title: title ?? this.title,
      city: city ?? this.city,
      district: district ?? this.district,
      description: description ?? this.description,
      existingPlayers: existingPlayers ?? this.existingPlayers,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      venue: venue ?? this.venue,
      cost: cost ?? this.cost,
      costMode: costMode ?? this.costMode,
      organizerPlaying: organizerPlaying ?? this.organizerPlaying,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      attendeeCount: attendeeCount ?? this.attendeeCount,
      waitlistCount: waitlistCount ?? this.waitlistCount,
      status: status ?? this.status,
      isRecurring: isRecurring ?? this.isRecurring,
      cancelDeadlineHours: cancelDeadlineHours ?? this.cancelDeadlineHours,
      updatedAt: updatedAt,
      cancelledAt: cancelledAt,
      finalCostPerPerson: finalCostPerPerson,
      costConfirmedAt: costConfirmedAt,
    );
  }
}
