import 'dart:io';
import 'package:excel/excel.dart';

void main() {
  final file = File('收费明细2026-07-17_2026-07-19_simplified.xlsx');
  final bytes = file.readAsBytesSync();
  
  try {
    final excel = Excel.decodeBytes(bytes);
    print('✓ 成功解析简化后的文件');
    print('工作表数量: ${excel.tables.length}');
    for (final name in excel.tables.keys) {
      print('  - "$name"');
    }
    
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet != null) {
      print('总行数: ${sheet.rows.length}');
      if (sheet.rows.isNotEmpty) {
        print('第1行: ${sheet.rows[0].map((c) => c?.value).toList()}');
        if (sheet.rows.length > 1) {
          print('第2行: ${sheet.rows[1].map((c) => c?.value).toList()}');
        }
      }
    }
  } catch (e) {
    print('✗ 解析失败: $e');
  }
}
