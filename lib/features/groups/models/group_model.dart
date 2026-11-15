String _stringValue(Object? value) => value is String ? value : '';

int _playerCountValue(Object? value) => value is int && value >= 2 ? value : 20;

List<String> _memberIdsValue(Object? value, String adminId) {
  final memberIds = value is List
      ? value.whereType<String>().where((id) => id.isNotEmpty).toSet().toList()
      : <String>[];
  if (adminId.isNotEmpty && !memberIds.contains(adminId)) {
    memberIds.insert(0, adminId);
  }
  return memberIds;
}

Map<String, String> _memberNamesValue(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: (entry.value as String).trim(),
      }
    : {};

RecurringEventSettings? _recurringSettingsValue(Object? value) {
  if (value is! Map) return null;
  final dayOfWeek = value['dayOfWeek'];
  final hour = value['hour'];
  final minute = value['minute'];
  if (dayOfWeek is! int || dayOfWeek < 1 || dayOfWeek > 7) return null;
  if (hour is! int || hour < 0 || hour > 23) return null;
  if (minute is! int || minute < 0 || minute > 59) return null;
  return RecurringEventSettings(
    dayOfWeek: dayOfWeek,
    hour: hour,
    minute: minute,
  );
}

class Group {
  final String id;
  final String name;
  final String description;
  final String adminId;
  final int maxPlayersDefault;
  final RecurringEventSettings? recurringEventSettings;
  final List<String> memberIds;

  /// 成員暱稱（UID → 暱稱）。加入或改暱稱時由本人寫入；舊球隊可能缺少部分成員。
  final Map<String, String> memberNames;

  /// 幹部（隊長指派，協助管理場地與開場次）；舊球隊沒有這個欄位時為空。
  /// 隊長存在 [adminId]，不在這份名單裡。
  final List<String> officerIds;

  bool isCaptain(String? userId) => userId != null && userId == adminId;
  bool isOfficer(String? userId) =>
      userId != null && officerIds.contains(userId);
  bool isMember(String? userId) => userId != null && memberIds.contains(userId);

  /// 隊長或幹部：可以管理場地、用球隊名義開場次。
  bool canManage(String? userId) => isCaptain(userId) || isOfficer(userId);

  Group({
    required this.id,
    required this.name,
    required this.description,
    required this.adminId,
    this.maxPlayersDefault = 20,
    this.recurringEventSettings,
    this.memberIds = const [],
    this.memberNames = const {},
    this.officerIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'adminId': adminId,
      'maxPlayersDefault': maxPlayersDefault,
      'recurringEventSettings': recurringEventSettings?.toMap(),
      'memberIds': memberIds,
      'memberNames': memberNames,
      'officerIds': officerIds,
    };
  }

  factory Group.fromMap(Map<String, dynamic> map, String id) {
    final adminId = _stringValue(map['adminId']);
    final name = _stringValue(map['name']).trim();
    return Group(
      id: id,
      name: name.isEmpty ? '未命名球隊' : name,
      description: _stringValue(map['description']),
      adminId: adminId,
      maxPlayersDefault: _playerCountValue(map['maxPlayersDefault']),
      recurringEventSettings: _recurringSettingsValue(
        map['recurringEventSettings'],
      ),
      memberIds: _memberIdsValue(map['memberIds'], adminId),
      memberNames: _memberNamesValue(map['memberNames']),
      officerIds: map['officerIds'] is List
          ? (map['officerIds'] as List).whereType<String>().toList()
          : const [],
    );
  }

  factory Group.create({
    required String name,
    required String description,
    required String adminId,
    required String adminName,
    int maxPlayersDefault = 20,
    RecurringEventSettings? recurringEventSettings,
  }) {
    return Group(
      id: '', // Will be assigned by Firestore
      name: name,
      description: description,
      adminId: adminId,
      maxPlayersDefault: maxPlayersDefault,
      recurringEventSettings: recurringEventSettings,
      memberIds: [adminId], // Admin is automatically a member
      memberNames: {adminId: adminName},
    );
  }
}

class RecurringEventSettings {
  final int dayOfWeek; // 1 = Monday, 7 = Sunday
  final int hour;
  final int minute;

  RecurringEventSettings({
    required this.dayOfWeek,
    required this.hour,
    required this.minute,
  });

  Map<String, dynamic> toMap() {
    return {'dayOfWeek': dayOfWeek, 'hour': hour, 'minute': minute};
  }

  factory RecurringEventSettings.fromMap(Map<String, dynamic> map) {
    return _recurringSettingsValue(map) ??
        RecurringEventSettings(dayOfWeek: 1, hour: 0, minute: 0);
  }
}
