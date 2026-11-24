// ignore_for_file: avoid_print
import 'dart:io';

import 'package:excel/excel.dart';

/// 把 xlsx 第一个工作表导出为 TSV，便于用其他工具核对数据
/// 用法: dart run tool/dump_xlsx.dart file.xlsx out.tsv
void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : '2026-11-06_2026-11-08.xlsx';
  final out = args.length > 1 ? args[1] : 'dump.tsv';
  final excel = Excel.decodeBytes(File(path).readAsBytesSync());
  final sheet = excel.tables[excel.tables.keys.first]!;
  final buffer = StringBuffer();
  for (final row in sheet.rows) {
    buffer.writeln(
      row.map((cell) => cell?.value?.toString() ?? '').join('\t'),
    );
  }
  File(out).writeAsStringSync(buffer.toString());
  print('wrote ${sheet.rows.length} rows -> $out');
}