/// 球隊季租（groups/{gid}/seasons/{sid}）：固定時段的場地，季租成員自動占位，
/// 每週空位開放給臨打。日期用 `yyyy-MM-dd`、時間用 `HH:mm`，以台灣時間解讀。
class Season {
  final String id;
  final String name;
  final String venueId;
  final String venueName;
  final String city;
  final String district;
  final String startDate;
  final String endDate;

  /// 1 = 週一 … 7 = 週日（與 DateTime.weekday 相同）。
  final int dayOfWeek;
  final String startTime;
  final String endTime;

  /// 場地容納人數（季租成員＋臨打的上限）。
  final int capacity;
  final int totalRent;
  final int feePerMember;
  final int dropInFee;

  /// `public` 公開臨打；`inviteOnly` 先開放給隊員與熟人。
  final String dropInMode;
  final int openDaysBefore;
  final int cancelDeadlineHours;
  final String organizerId;
  final List<String> skipDates;
  final List<String> memberIds;
  final List<String> paidMemberIds;
  final bool active;

  /// 排程最後開到哪一天（只由 Cloud Function 寫入）。
  final String lastCreatedFor;

  const Season({
    required this.id,
    required this.name,
    required this.venueId,
    required this.venueName,
    required this.city,
    required this.district,
    required this.startDate,
    required this.endDate,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.capacity,
    required this.totalRent,
    required this.feePerMember,
    required this.dropInFee,
    this.dropInMode = 'public',
    this.openDaysBefore = 7,
    this.cancelDeadlineHours = 24,
    required this.organizerId,
    this.skipDates = const [],
    this.memberIds = const [],
    this.paidMemberIds = const [],
    this.active = true,
    this.lastCreatedFor = '',
  });

  static const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
  String get weekdayLabel => '週${weekdayLabels[dayOfWeek - 1]}';

  /// 「場租 ÷ 季租人數」無條件進位，作為季費參考。
  int? get suggestedFee =>
      memberIds.isEmpty ? null : (totalRent / memberIds.length).ceil();

  int get collectedFees => paidMemberIds.length * feePerMember;

  /// 季租期間（扣掉停打日）實際會打的日期，用來顯示「共 N 場」。
  List<DateTime> get playDates {
    final start = DateTime.tryParse(startDate);
    final end = DateTime.tryParse(endDate);
    if (start == null || end == null) return const [];
    final skip = skipDates.toSet();
    final dates = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      if (day.weekday == dayOfWeek && !skip.contains(formatDate(day))) {
        dates.add(day);
      }
    }
    return dates;
  }

  static String formatDate(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
    'name': name,
    'venueId': venueId,
    'venueName': venueName,
    'city': city,
    'district': district,
    'startDate': startDate,
    'endDate': endDate,
    'dayOfWeek': dayOfWeek,
    'startTime': startTime,
    'endTime': endTime,
    'capacity': capacity,
    'totalRent': totalRent,
    'feePerMember': feePerMember,
    'dropInFee': dropInFee,
    'dropInMode': dropInMode,
    'openDaysBefore': openDaysBefore,
    'cancelDeadlineHours': cancelDeadlineHours,
    'organizerId': organizerId,
    'skipDates': skipDates,
    'memberIds': memberIds,
    'paidMemberIds': paidMemberIds,
    'active': active,
    'lastCreatedFor': lastCreatedFor,
  };

  factory Season.fromMap(Map<String, dynamic> map, String id) {
    String text(String key) =>
        map[key] is String ? (map[key] as String).trim() : '';
    int number(String key, int fallback) =>
        map[key] is num ? (map[key] as num).toInt() : fallback;
    List<String> strings(String key) => map[key] is List
        ? (map[key] as List).whereType<String>().toList()
        : const [];
    return Season(
      id: id,
      name: text('name'),
      venueId: text('venueId'),
      venueName: text('venueName'),
      city: text('city'),
      district: text('district'),
      startDate: text('startDate'),
      endDate: text('endDate'),
      dayOfWeek: number('dayOfWeek', 1).clamp(1, 7),
      startTime: text('startTime'),
      endTime: text('endTime'),
      capacity: number('capacity', 10),
      totalRent: number('totalRent', 0),
      feePerMember: number('feePerMember', 0),
      dropInFee: number('dropInFee', 0),
      dropInMode: text('dropInMode') == 'inviteOnly' ? 'inviteOnly' : 'public',
      openDaysBefore: number('openDaysBefore', 7),
      cancelDeadlineHours: number('cancelDeadlineHours', 24),
      organizerId: text('organizerId'),
      skipDates: strings('skipDates'),
      memberIds: strings('memberIds'),
      paidMemberIds: strings('paidMemberIds'),
      active: map['active'] != false,
      lastCreatedFor: text('lastCreatedFor'),
    );
  }

  Season copyWith({
    List<String>? memberIds,
    List<String>? paidMemberIds,
    List<String>? skipDates,
    bool? active,
  }) => Season.fromMap({
    ...toMap(),
    'memberIds': ?memberIds,
    'paidMemberIds': ?paidMemberIds,
    'skipDates': ?skipDates,
    'active': ?active,
  }, id);
}
