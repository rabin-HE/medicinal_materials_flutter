import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/herb_category.dart';
import 'package:flutter_application_1/services/herb_dictionary.dart';
import 'package:flutter_application_1/services/tax_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HerbDictionary.instance.load();
  });

  test('字典里的药材按 9% / 13% 计税，未收录药材按 0 税并单列', () {
    final data = <List<dynamic>>[
      ['药品/项目名称', '实收金额'],
      ['乌梢蛇', 113.0], // 动物类 13%
      ['辽藁本', 109.0], // 植物类 9%
      ['某个还没收录的药材', 200.0],
    ];

    final records = TaxCalculator.parseMedicalSalesData(data);
    expect(records.length, 3);

    final summary = TaxCalculator.calculateSummary(records);
    final unidentified = summary.unidentifiedRecords;

    expect(unidentified.length, 1);
    expect(unidentified.first.herbName, '某个还没收录的药材');
    expect(unidentified.first.taxRate, 0);

    // 113 / 1.13 * 0.13 = 13.0，109 / 1.09 * 0.09 = 9.0
    expect(summary.categoryTaxTotals[HerbCategory.animal], closeTo(13.0, 0.001));
    expect(summary.categoryTaxTotals[HerbCategory.plant], closeTo(9.0, 0.001));
    expect(summary.totalTaxAmount, closeTo(22.0, 0.001));
  });

  test('把未收录药材归类后，税额随之补上', () async {
    final data = <List<dynamic>>[
      ['药品/项目名称', '实收金额'],
      ['某个还没收录的药材', 200.0],
    ];
    final before = TaxCalculator.calculateSummary(
      TaxCalculator.parseMedicalSalesData(data),
    );
    expect(before.totalTaxAmount, 0);

    await HerbDictionary.instance.upsert('某个还没收录的药材', HerbCategory.plant);

    final after = TaxCalculator.calculateSummary(
      TaxCalculator.parseMedicalSalesData(data),
    );
    expect(after.unidentifiedRecords, isEmpty);
    expect(after.totalTaxAmount, closeTo(200 / 1.09 * 0.09, 0.001));

    await HerbDictionary.instance.resetLocalChanges();
  });
}