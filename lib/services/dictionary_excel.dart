import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/herb_category.dart';

/// 解析 Excel 对照表的结果
class DictionaryExcelResult {
  final Map<String, HerbCategory> herbs;
  final List<String> skippedRows;

  const DictionaryExcelResult(this.herbs, this.skippedRows);
}

/// 药材对照表的 Excel 读写
///
/// 表格格式（第一行为表头，两列）：
/// | 药材名称 | 类别 |
/// | 乌梢蛇   | 动物类 |
class DictionaryExcel {
  static const String headerName = '药材名称';
  static const String headerCategory = '类别';
  static const String sheetName = '药材对照表';

  /// 导出为 xlsx 字节
  static Uint8List exportBytes(Map<String, HerbCategory> herbs) {
    final excel = Excel.createExcel();
    excel.rename(excel.getDefaultSheet() ?? 'Sheet1', sheetName);
    final sheet = excel[sheetName];
    sheet.appendRow([
      TextCellValue(headerName),
      TextCellValue(headerCategory),
    ]);
    herbs.forEach((name, category) {
      sheet.appendRow([
        TextCellValue(name),
        TextCellValue(category.name),
      ]);
    });
    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('生成 Excel 失败');
    }
    return Uint8List.fromList(bytes);
  }

  /// 解析导入的 xlsx/xls 字节
  static DictionaryExcelResult parse(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw const FormatException('Excel 中没有工作表');
    }
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.isEmpty) {
      throw const FormatException('工作表为空');
    }

    final herbs = <String, HerbCategory>{};
    final skipped = <String>[];

    // 自动识别表头列：找到「药材名称/药品名称/名称」和「类别/分类/税率」两列
    var nameIndex = 0;
    var categoryIndex = 1;
    var startRow = 0;
    if (sheet.rows.isNotEmpty) {
      final header = sheet.rows.first
          .map((cell) => cell?.value?.toString().trim() ?? '')
          .toList();
      final detectedName = header.indexWhere(
        (h) => h.contains('名称') || h.contains('药材') || h == '品名',
      );
      final detectedCategory = header.indexWhere(
        (h) => h.contains('类别') || h.contains('分类') || h.contains('税率'),
      );
      if (detectedName >= 0 && detectedCategory >= 0) {
        nameIndex = detectedName;
        categoryIndex = detectedCategory;
        startRow = 1;
      }
    }

    for (var i = startRow; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;
      final name = row.length > nameIndex
          ? (row[nameIndex]?.value?.toString().trim() ?? '')
          : '';
      final categoryText = row.length > categoryIndex
          ? (row[categoryIndex]?.value?.toString().trim() ?? '')
          : '';
      if (name.isEmpty) continue;
      final category = HerbCategory.fromName(categoryText);
      if (category == null) {
        skipped.add('第 ${i + 1} 行：$name（类别「$categoryText」无法识别）');
        continue;
      }
      herbs[name] = category;
    }

    return DictionaryExcelResult(herbs, skipped);
  }
}