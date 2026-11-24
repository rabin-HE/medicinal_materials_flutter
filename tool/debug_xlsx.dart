// ignore_for_file: avoid_print
import 'dart:io';

import 'package:excel/excel.dart';

/// 调试脚本：打印 xlsx 的表结构，确认解析列/金额是否符合预期
/// 用法: dart run tool/debug_xlsx.dart file.xlsx [maxRows]
Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : '2026-11-06_2026-11-08.xlsx';
  final maxRows = args.length > 1 ? int.parse(args[1]) : 10;
  final bytes = File(path).readAsBytesSync();

  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (e) {
    print('decodeBytes 失败: $e');
    return;
  }

  print('sheets: ${excel.tables.keys.toList()}');
  for (final entry in excel.tables.entries) {
    final sheet = entry.value;
    print('--- sheet "${entry.key}" rows=${sheet.rows.length} maxCols=${sheet.maxColumns}');
    for (var i = 0; i < sheet.rows.length && i < maxRows; i++) {
      final row = sheet.rows[i];
      final cells = <String>[];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        String text;
        if (cell == null) {
          text = '<null>';
        } else {
          text = '${cell.value}(${cell.value.runtimeType})';
        }
        cells.add('$c:$text');
      }
      print('row[$i] len=${row.length}: ${cells.join(' | ')}');
    }
  }
}