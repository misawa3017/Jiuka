import 'package:flutter/material.dart';

import '../core/data/taiwan_districts.dart';

/// 縣市＋鄉鎮市區兩層下拉選單。
///
/// - [allowAny] 為 true 時（首頁篩選），兩層都多一個「全部」選項，可只選縣市。
/// - 為 false 時（發布場次），兩層都必填。
class DistrictPicker extends StatelessWidget {
  final String? city;
  final String? area;
  final bool allowAny;
  final void Function(String? city, String? area) onChanged;

  const DistrictPicker({
    super.key,
    required this.city,
    required this.area,
    required this.onChanged,
    this.allowAny = false,
  });

  @override
  Widget build(BuildContext context) {
    final areas = city == null ? const <String>[] : taiwanDistricts[city]!;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            // 縣市改變時重建，讓表單驗證狀態跟著重設。
            key: ValueKey('city-$city'),
            initialValue: city,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '縣市'),
            items: [
              if (allowAny)
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('全部縣市'),
                ),
              for (final name in taiwanDistricts.keys)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            validator: allowAny
                ? null
                : (value) => value == null ? '請選擇縣市' : null,
            onChanged: (value) => onChanged(value, null),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey('area-$city-$area'),
            initialValue: area,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '鄉鎮市區'),
            hint: Text(city == null ? '請先選縣市' : '請選擇'),
            items: [
              if (allowAny && city != null)
                const DropdownMenuItem<String?>(value: null, child: Text('全部')),
              for (final name in areas)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            validator: allowAny
                ? null
                : (value) => value == null ? '請選擇鄉鎮市區' : null,
            onChanged: city == null ? null : (value) => onChanged(city, value),
          ),
        ),
      ],
    );
  }
}
