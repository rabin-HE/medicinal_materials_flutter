import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/herb_category.dart';
import 'package:flutter_application_1/services/herb_dictionary.dart';
import 'package:flutter_application_1/services/sales_excel.dart';
import 'package:flutter_application_1/services/tax_calculator.dart';

/// 用仓库里的真实导出文件（2026-11-06_2026-11-08.xlsx）做回归
///
/// 期望值是用脚本独立统计同一份表格得到的：
///   全部 1159 条明细都是中药饮片，含 30 条退费（负金额）、275 条金额为 0 的行；
///   实收合计 11707.71；按字典分类后
///   植物类 11438.71、动物类 250.88、矿物类 18.12；
///   税额 = 11438.71/1.09*0.09 + 250.88/1.13*0.13 + 18.12/1.13*0.13 = 975.4275
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 真实导出文件带患者信息，被 .gitignore 排除；没有它时只跳过这一条
  final sampleFile = File('2026-11-06_2026-11-08.xlsx');
  final skipSample = sampleFile.existsSync()
      ? null
      : '缺少 2026-11-06_2026-11-08.xlsx（放在项目根目录才会跑真实文件回归）';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HerbDictionary.instance.load();
  });

  test('真实收费明细（50 列，多出「商品标签」列）解析出正确金额与税额', () {
    final result = SalesExcel.parseBytes(sampleFile.readAsBytesSync());

    // 表头在第 1 行，名称列被「商品标签」挤到第 18 列（索引 17），实收在索引 30
    expect(result.columns.herbNameIndex, 17);
    expect(result.columns.amountIndex, 30);
    expect(result.columns.headerRowIndex, 0);

    final summary = TaxCalculator.calculateSummary(result.records);
    expect(result.records.length, 884);
    expect(summary.totalAmount, closeTo(11707.71, 0.001));
    expect(summary.unidentifiedRecords, isEmpty, reason: '这批药材应全部在字典中');

    expect(summary.categoryTotals[HerbCategory.plant], closeTo(11438.71, 0.001));
    expect(summary.categoryTotals[HerbCategory.animal], closeTo(250.88, 0.001));
    expect(summary.categoryTotals[HerbCategory.mineral], closeTo(18.12, 0.001));
    expect(summary.totalTaxAmount, closeTo(975.4275, 0.001));

    // 退费（负金额）也要计入，不能因为负数被当成解析失败
    expect(
      result.records.where((r) => r.totalAmount < 0),
      isNotEmpty,
      reason: '退费行应保留为负金额',
    );
  }, skip: skipSample);

  test('列顺序变化（实收在名称左边、混入干扰列）也能按表头识别', () {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([
      TextCellValue('备注'),
      TextCellValue('实收(元)'),
      TextCellValue('商品标签'),
      TextCellValue('单价'),
      TextCellValue('药品/项目名称'),
      TextCellValue('原价'),
    ]);
    sheet.appendRow([
      TextCellValue('-'),
      DoubleCellValue(109),
      TextCellValue('-'),
      TextCellValue('0.40'),
      TextCellValue('辽藁本'),
      TextCellValue('209'),
    ]);
    sheet.appendRow([
      TextCellValue('-'),
      DoubleCellValue(113),
      TextCellValue('-'),
      TextCellValue('1.00'),
      TextCellValue('乌梢蛇'),
      TextCellValue('213'),
    ]);

    final bytes = Uint8List.fromList(excel.encode()!);
    final result = SalesExcel.parseBytes(bytes);

    expect(result.columns.amountIndex, 1);
    expect(result.columns.herbNameIndex, 4);
    final summary = TaxCalculator.calculateSummary(result.records);
    expect(summary.totalAmount, closeTo(222.0, 0.001));
    expect(summary.totalTaxAmount, closeTo(22.0, 0.001));
  });

  test('表头上面还有标题行时也能找到表头', () {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([TextCellValue('XX 医院收费明细表')]);
    sheet.appendRow([TextCellValue('导出时间：2026-11-09')]);
    sheet.appendRow([TextCellValue('药品/项目名称'), TextCellValue('实收金额')]);
    sheet.appendRow([TextCellValue('红花'), DoubleCellValue(109)]);
    sheet.appendRow([TextCellValue('地龙'), DoubleCellValue(113)]);

    final result = SalesExcel.parseBytes(Uint8List.fromList(excel.encode()!));

    expect(result.columns.headerRowIndex, 2);
    expect(result.records.length, 2);
    final summary = TaxCalculator.calculateSummary(result.records);
    expect(summary.totalAmount, closeTo(222.0, 0.001));
    expect(summary.totalTaxAmount, closeTo(22.0, 0.001));
  });

  test('表格中间重复出现的表头不会被算成药材', () {
    final data = <List<dynamic>>[
      ['药品/项目名称', '实收金额'],
      ['红花', 109.0],
      ['药品/项目名称', '实收金额'],
      ['地龙', 113.0],
    ];
    final result = TaxCalculator.parseMedicalSalesDataWithColumns(data);
    expect(result.records.length, 2);
    expect(result.records.map((r) => r.herbName), ['红花', '地龙']);
  });

  test('金额为文本（千分位、货币符号、中文负号、带「元」）也能解析', () {
    final data = <List<dynamic>>[
      ['药品/项目名称', '实收'],
      ['红花', '￥1,109.00'],
      ['地龙', '－113'],
      ['陈皮', '1.50元'],
      ['白术', ''],
      ['白芍', '-'],
    ];
    final result = TaxCalculator.parseMedicalSalesDataWithColumns(data);
    expect(result.records.length, 3);
    expect(result.records[0].totalAmount, closeTo(1109.0, 0.001));
    expect(result.records[1].totalAmount, closeTo(-113.0, 0.001));
    expect(result.records[2].totalAmount, closeTo(1.5, 0.001));
  });

  test('没有表头的老格式仍按 2 列简化格式解析', () {
    final data = <List<dynamic>>[
      ['红花', 109.0],
      ['地龙', 113.0],
    ];
    final result = TaxCalculator.parseMedicalSalesDataWithColumns(data);
    expect(result.records.length, 2);
    expect(result.columns.herbNameIndex, 0);
    expect(result.columns.amountIndex, 1);
  });
}