import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/herb_category.dart';
import 'package:flutter_application_1/screens/herb_dictionary_screen.dart';
import 'package:flutter_application_1/services/herb_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HerbDictionary.instance.load();
  });

  testWidgets('字典页可以搜索到具体药材并显示税率', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HerbDictionaryScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('内置'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '乌梢蛇');
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('乌梢蛇'),
      ),
      findsOneWidget,
    );
    expect(find.text('动物类 · 13%'), findsOneWidget);
  });

  testWidgets('新增药材后字典和本地存储都更新', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HerbDictionaryScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新增药材'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '测试药材乙');
    await tester.tap(find.text('植物类 9%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(HerbDictionary.instance.lookup('测试药材乙'), HerbCategory.plant);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(HerbDictionary.prefsKey);
    expect(stored, isNotNull);
    expect(stored, contains('测试药材乙'));
  });
}