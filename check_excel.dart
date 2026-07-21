// ignore_for_file: avoid_print

import 'package:excel/excel.dart';
import 'dart:io';

void main() {
  final file = File('test_list.xlsx');
  final bytes = file.readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);

  final sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null) {
    print('No sheet found');
    return;
  }

  print('总行数: ${sheet.rows.length}');
  print('总列数: ${sheet.maxColumns}');
  print('');

  // 打印前2行的所有列
  print('=== 第1行（标题行）===');
  final row0 = sheet.rows[0];
  for (int i = 0; i < row0.length; i++) {
    final cell = row0[i];
    final value = cell?.value;
    if (value != null && value.toString().trim().isNotEmpty) {
      print('  列$i: $value');
    }
  }

  print('\n=== 第2行（第一条数据）===');
  final row1 = sheet.rows[1];
  for (int i = 0; i < row1.length; i++) {
    final cell = row1[i];
    final value = cell?.value;
    if (value != null && value.toString().trim().isNotEmpty) {
      // 判断是否是数字
      final isNum = value is double || value is int;
      print('  列$i: $value ${isNum ? "[数字]" : ""}');
    }
  }

  print('\n=== 第3行（第二条数据）===');
  if (sheet.rows.length > 2) {
    final row2 = sheet.rows[2];
    for (int i = 0; i < row2.length; i++) {
      final cell = row2[i];
      final value = cell?.value;
      if (value != null && value.toString().trim().isNotEmpty) {
        final isNum = value is double || value is int;
        print('  列$i: $value ${isNum ? "[数字]" : ""}');
      }
    }
  }
}
