import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/models/herb_category.dart';
import 'package:flutter_application_1/screens/home_screen.dart';
import 'package:flutter_application_1/services/herb_dictionary.dart';

/// 用假的文件选择器把 Excel 直接“喂”给界面
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return FilePickerResult([
      PlatformFile(name: 'sample.xlsx', size: bytes.length, bytes: bytes),
    ]);
  }
}

Uint8List _sampleXlsx() {
  final excel = Excel.createExcel();
  final sheet = excel[excel.getDefaultSheet()!];
  sheet.appendRow([TextCellValue('药品/项目名称'), TextCellValue('实收金额')]);
  sheet.appendRow([TextCellValue('乌梢蛇'), DoubleCellValue(113)]);
  sheet.appendRow([TextCellValue('辽藁本'), DoubleCellValue(109)]);
  sheet.appendRow([TextCellValue('某种新药材'), DoubleCellValue(200)]);
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HerbDictionary.instance.load();
    FilePicker.platform = _FakeFilePicker(_sampleXlsx());
  });

  tearDown(() async {
    await HerbDictionary.instance.resetLocalChanges();
  });

  testWidgets('导入后未收录药材触发红色警告，归类后税额补上', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入 Excel'));
    await tester.pumpAndSettle();

    // 乌梢蛇 13 + 辽藁本 9 = 22，未收录的 200 元按 0 税
    expect(find.text('¥ 22.00'), findsOneWidget);
    expect(find.textContaining('有 1 项药材不在字典中'), findsOneWidget);

    // 在未识别列表里点「归类」→ 选植物类
    await tester.ensureVisible(find.text('归类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('归类'));
    await tester.pumpAndSettle();
    expect(find.text('「某种新药材」属于哪一类？'), findsOneWidget);

    await tester.tap(find.text('植物类（9%）'));
    await tester.pumpAndSettle();

    // 200 / 1.09 * 0.09 = 16.51，合计 38.51
    expect(find.text('¥ 38.51'), findsOneWidget);
    expect(find.textContaining('不在字典中'), findsNothing);
    expect(HerbDictionary.instance.lookup('某种新药材'), HerbCategory.plant);
  });

  testWidgets('真实 50 列收费明细在界面上给出正确合计', (tester) async {
    FilePicker.platform = _FakeFilePicker(
      File('2026-11-06_2026-11-08.xlsx').readAsBytesSync(),
    );

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入 Excel'));
    await tester.pumpAndSettle();

    // 实收合计 11707.71，总税额 975.43（此前这里全是 0）
    expect(find.text('¥ 11707.71'), findsOneWidget);
    expect(find.text('¥ 975.43'), findsOneWidget);
    expect(find.textContaining('不在字典中'), findsNothing);
  }, skip: !File('2026-11-06_2026-11-08.xlsx').existsSync());

  testWidgets('解析不出任何记录时给出错误提示，而不是显示 0', (tester) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];
    sheet.appendRow([TextCellValue('药品/项目名称'), TextCellValue('实收')]);
    sheet.appendRow([TextCellValue('红花'), DoubleCellValue(0)]);
    FilePicker.platform = _FakeFilePicker(Uint8List.fromList(excel.encode()!));

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导入 Excel'));
    await tester.pumpAndSettle();

    expect(find.textContaining('没有从'), findsOneWidget);
    expect(find.text('¥ 0.00'), findsNothing);
  });
}