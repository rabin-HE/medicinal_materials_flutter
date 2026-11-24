import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../models/sales_record.dart';
import 'excel_preprocessor.dart';
import 'tax_calculator.dart';

/// 收费明细 Excel 的读取入口
///
/// 解析逻辑集中在这里，界面和测试走同一条路径，避免两边各自猜列位置。
class SalesExcel {
  /// 解码 xlsx；excel 包对某些导出文件（会计格式 numFmtId）会报错，此时先用预处理器修一遍
  static Excel decode(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (first) {
      try {
        final fixed = ExcelPreprocessor.fixExcelBytes(bytes);
        return Excel.decodeBytes(fixed);
      } catch (second) {
        throw SalesExcelException('Excel 文件无法解析：$second');
      }
    }
  }

  /// 把一个工作表转成二维值列表
  static List<List<dynamic>> sheetRows(Sheet sheet) {
    return <List<dynamic>>[
      for (final row in sheet.rows)
        <dynamic>[for (final cell in row) cell?.value],
    ];
  }

  /// 解析收费明细：优先选能识别出表头的工作表，否则用第一个非空工作表
  static SalesExcelResult parseBytes(Uint8List bytes) {
    final excel = decode(bytes);
    if (excel.tables.isEmpty) {
      throw const SalesExcelException('Excel 文件中没有工作表');
    }

    Sheet? chosen;
    String? chosenName;
    List<List<dynamic>> chosenRows = const [];
    SalesColumns? chosenColumns;

    for (final entry in excel.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;
      final rows = sheetRows(sheet);
      if (chosen == null) {
        chosen = sheet;
        chosenName = entry.key;
        chosenRows = rows;
        chosenColumns = TaxCalculator.detectColumns(rows);
      }
      final columns = TaxCalculator.detectColumns(rows);
      if (columns != null) {
        chosen = sheet;
        chosenName = entry.key;
        chosenRows = rows;
        chosenColumns = columns;
        break;
      }
    }

    if (chosen == null || chosenName == null) {
      throw const SalesExcelException('工作表为空');
    }

    final result = TaxCalculator.parseMedicalSalesDataWithColumns(chosenRows);
    return SalesExcelResult(
      sheetName: chosenName,
      parseResult: result,
      columns: chosenColumns ?? result.columns,
    );
  }
}

/// 解析收费明细的结果
class SalesExcelResult {
  const SalesExcelResult({
    required this.sheetName,
    required this.parseResult,
    required this.columns,
  });

  final String sheetName;
  final SalesParseResult parseResult;
  final SalesColumns columns;

  List<SalesRecord> get records => parseResult.records;

  int get totalRows => parseResult.totalRows;
}

class SalesExcelException implements Exception {
  const SalesExcelException(this.message);

  final String message;

  @override
  String toString() => message;
}