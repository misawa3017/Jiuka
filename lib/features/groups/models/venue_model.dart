import '../../events/models/event_model.dart';

/// 球隊的常用場地（groups/{gid}/venues/{vid}），開球隊場次時可一鍵帶入。
class Venue {
  final String id;
  final String name;
  final String city;

  /// 縣市＋鄉鎮市區全名，例如「新北市三重區」。
  final String district;
  final CostMode costMode;
  final int cost;
  final int maxPlayers;
  final String notes;

  const Venue({
    required this.id,
    required this.name,
    required this.city,
    required this.district,
    required this.costMode,
    required this.cost,
    required this.maxPlayers,
    this.notes = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'city': city,
    'district': district,
    'costMode': costMode.name,
    'cost': cost,
    'maxPlayers': maxPlayers,
    'notes': notes,
  };

  factory Venue.fromMap(Map<String, dynamic> map, String id) {
    String text(Object? value) => value is String ? value.trim() : '';
    int number(Object? value, int fallback) =>
        value is num ? value.toInt() : fallback;
    return Venue(
      id: id,
      name: text(map['name']),
      city: text(map['city']),
      district: text(map['district']),
      costMode:
          CostMode.values
              .where((mode) => mode.name == map['costMode'])
              .firstOrNull ??
          CostMode.perPerson,
      cost: number(map['cost'], 0),
      maxPlayers: number(map['maxPlayers'], 10),
      notes: text(map['notes']),
    );
  }

  /// 費用的簡短說明，例如「場租 2,400 元」或「每人 180 元」。
  String get costLabel =>
      costMode == CostMode.perPerson ? '每人 $cost 元' : '場租 $cost 元';
}
