import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiuka/components/district_picker.dart';
import 'package:jiuka/core/data/taiwan_districts.dart';

void main() {
  test('清單包含 22 縣市、368 鄉鎮市區，同縣市內不重複', () {
    expect(taiwanDistricts.length, 22);
    expect(
      taiwanDistricts.values.fold<int>(0, (sum, a) => sum + a.length),
      368,
    );
    for (final areas in taiwanDistricts.values) {
      expect(areas.toSet().length, areas.length);
    }
  });

  test('拆解地區全名，並把「台」視為「臺」', () {
    expect(cityOfDistrict('臺北市大安區'), '臺北市');
    expect(areaOfDistrict('臺北市大安區'), '大安區');
    expect(cityOfDistrict('台南市東區'), '臺南市');
    expect(areaOfDistrict('台南市東區'), '東區');
    // 臺中市也有大安區；必須依縣市判斷。
    expect(areaOfDistrict('臺中市大安區'), '大安區');
    expect(areaOfDistrict('新北市大安區'), isNull);
    expect(cityOfDistrict('火星市'), isNull);
    expect(areaOfDistrict('臺北市'), isNull);
  });

  testWidgets('先選縣市才能選鄉鎮市區；換縣市會清空鄉鎮市區', (tester) async {
    String? city;
    String? area;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DistrictPicker(
              city: city,
              area: area,
              onChanged: (c, a) => setState(() {
                city = c;
                area = a;
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.text('請先選縣市'), findsOneWidget);

    await tester.tap(find.text('縣市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('臺北市').last);
    await tester.pumpAndSettle();
    expect(city, '臺北市');

    await tester.tap(find.text('請選擇'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大安區').last);
    await tester.pumpAndSettle();
    expect(area, '大安區');

    await tester.tap(find.text('臺北市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新北市').last);
    await tester.pumpAndSettle();
    expect(city, '新北市');
    expect(area, isNull);
  });
}
