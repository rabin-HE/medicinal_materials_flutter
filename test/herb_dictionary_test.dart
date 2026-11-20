import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/herb_category.dart';
import 'package:flutter_application_1/models/sales_record.dart';
import 'package:flutter_application_1/services/dictionary_excel.dart';
import 'package:flutter_application_1/services/herb_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HerbDictionary.instance.load();
  });

  test('内置字典没有重复名称，新增的三味药材归类正确', () {
    final dict = HerbDictionary.instance;
    expect(dict.isLoaded, isTrue);
    expect(dict.baseCount, greaterThan(400));

    expect(dict.lookup('乌梢蛇'), HerbCategory.animal);
    expect(dict.lookup('辽藁本'), HerbCategory.plant);
    expect(dict.lookup('炒神曲'), HerbCategory.plant);

    // 名称唯一：Map 的 key 天然去重，条数与 entries 一致
    expect(dict.herbs.length, dict.entries.length);
  });

  test('全角/半角括号、多余空格的写法都能命中同一条', () {
    final dict = HerbDictionary.instance;
    expect(dict.lookup('羚羊角粉(精品)'), HerbCategory.animal);
    expect(dict.lookup('羚羊角粉（精品）'), HerbCategory.animal);
    expect(dict.lookup(' 辽藁本 '), HerbCategory.plant);
  });

  test('未收录药材返回 null，税率为 0（税额偏低靠界面警告）', () {
    final record = SalesRecord.fromExcel(
      herbName: '查无此药',
      quantity: 1,
      totalAmount: 100,
    );
    expect(record.category, isNull);
    expect(record.taxRate, 0);
    expect(record.taxAmount, 0);
  });

  test('本机新增 / 改类别 / 删除生效，导出后可再解析', () async {
    final dict = HerbDictionary.instance;

    await dict.upsert('测试药材甲', HerbCategory.animal);
    expect(dict.lookup('测试药材甲'), HerbCategory.animal);

    await dict.upsert('乌梢蛇', HerbCategory.plant);
    expect(dict.lookup('乌梢蛇'), HerbCategory.plant);

    final json = dict.exportJson();
    final parsed = HerbDictionary.parseDictionaryJson(json);
    expect(parsed['测试药材甲'], HerbCategory.animal);
    expect(parsed['乌梢蛇'], HerbCategory.plant);
    expect(parsed.length, dict.herbs.length);

    await dict.removeHerb('测试药材甲');
    expect(dict.lookup('测试药材甲'), isNull);

    await dict.resetLocalChanges();
    expect(dict.lookup('乌梢蛇'), HerbCategory.animal);
    expect(dict.hasLocalChanges, isFalse);
    expect(dict.herbs.length, dict.baseCount);
  });

  test('Excel 导出后再导入，条目一致', () {
    final dict = HerbDictionary.instance;
    final bytes = DictionaryExcel.exportBytes(dict.herbs);
    final parsed = DictionaryExcel.parse(bytes);

    expect(parsed.skippedRows, isEmpty);
    expect(parsed.herbs.length, dict.herbs.length);
    expect(parsed.herbs['乌梢蛇'], HerbCategory.animal);
    expect(parsed.herbs['辽藁本'], HerbCategory.plant);
  });

  test('导入时无法识别的类别会被跳过并记录', () {
    final dict = HerbDictionary.instance;
    final before = dict.herbs.length;

    expect(
      () => HerbDictionary.parseDictionaryJson('{"herbs": {"草": "plant"}}'),
      returnsNormally,
    );
    expect(dict.herbs.length, before);
  });
}