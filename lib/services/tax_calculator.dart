// ignore_for_file: avoid_print

import '../models/herb_category.dart';
import '../models/sales_record.dart';

/// 从收费明细表里识别出的列位置
class SalesColumns {
  const SalesColumns({
    required this.herbNameIndex,
    required this.amountIndex,
    this.headerRowIndex,
  });

  /// 药品/项目名称所在列
  final int herbNameIndex;

  /// 实收金额所在列
  final int amountIndex;

  /// 表头所在行；没有识别到表头时为 null
  final int? headerRowIndex;

  int get minColumns =>
      (herbNameIndex > amountIndex ? herbNameIndex : amountIndex) + 1;

  @override
  String toString() =>
      '名称列=$herbNameIndex, 实收列=$amountIndex, 表头行=${headerRowIndex ?? "无"}';
}

/// 税费计算服务
class TaxCalculator {
  /// 药品/项目名称列的表头候选（已归一化）
  static const List<String> _herbHeaderAliases = [
    '药品/项目名称',
    '药品名称',
    '项目名称',
    '药材名称',
    '商品名称',
    '收费项目',
    '品名',
    '名称',
  ];

  /// 实收金额列的表头候选（已归一化）
  static const List<String> _amountHeaderAliases = [
    '实收',
    '实收金额',
    '实收合计',
    '金额',
    '销售额',
  ];

  /// 表头归一化：去空白、统一全角括号、去掉货币符号和结尾的「(元)」
  static String _normalizeHeader(dynamic value) {
    if (value == null) return '';
    var s = value.toString().trim().replaceAll(RegExp(r'\s+'), '');
    s = s
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('／', '/')
        .replaceAll('￥', '')
        .replaceAll('¥', '');
    s = s.replaceAll(RegExp(r'\(元\)$'), '');
    return s;
  }

  static bool _isHerbHeader(String header) {
    if (header.isEmpty) return false;
    // 编码/规格/厂家这类列名里也带「药品」，排除掉
    const excluded = ['编码', '规格', '厂家', '单位', '名称缩写'];
    if (excluded.any(header.contains)) return false;
    if (_herbHeaderAliases.contains(header)) return true;
    final looksLikeName = header.contains('名称') || header == '项目';
    final looksLikeHerb = header.contains('药品') ||
        header.contains('项目') ||
        header.contains('药材') ||
        header.contains('商品');
    return looksLikeName && looksLikeHerb;
  }

  static bool _isAmountHeader(String header) {
    if (header.isEmpty) return false;
    // 单价/原价/议价/优惠/抵扣/核销都不是「实收」
    const excluded = ['单价', '原价', '议价', '优惠', '抵扣', '核销', '数量'];
    if (excluded.any(header.contains)) return false;
    if (_amountHeaderAliases.contains(header)) return true;
    return header.contains('实收');
  }

  /// 按表头自动定位「药品/项目名称」和「实收」两列
  ///
  /// 医院导出的表列顺序会变（例如多一列「商品标签」），
  /// 所以不能写死列索引，否则整张表都会被静默跳过。
  /// 在前 30 行里找同时含两列表头的行；找不到返回 null。
  static SalesColumns? detectColumns(List<List<dynamic>> data) {
    final limit = data.length < 30 ? data.length : 30;
    for (var rowIndex = 0; rowIndex < limit; rowIndex++) {
      final row = data[rowIndex];
      int? herbIndex;
      int? amountIndex;
      for (var col = 0; col < row.length; col++) {
        final header = _normalizeHeader(row[col]);
        if (herbIndex == null && _isHerbHeader(header)) {
          herbIndex = col;
        } else if (amountIndex == null && _isAmountHeader(header)) {
          amountIndex = col;
        }
      }
      if (herbIndex != null && amountIndex != null) {
        return SalesColumns(
          herbNameIndex: herbIndex,
          amountIndex: amountIndex,
          headerRowIndex: rowIndex,
        );
      }
    }
    return null;
  }

  /// 没有表头时的兜底列位置（兼容历史格式与 2 列的简化格式）
  static SalesColumns _fallbackColumns(List<List<dynamic>> data) {
    var maxColumns = 0;
    for (final row in data) {
      if (row.length > maxColumns) maxColumns = row.length;
    }
    if (maxColumns >= 33) {
      // 早期格式：第17列药品/项目名称，第33列实收
      return const SalesColumns(herbNameIndex: 16, amountIndex: 32);
    }
    if (maxColumns >= 30) {
      // 上一版导出格式：第17列药品/项目名称，第30列实收
      return const SalesColumns(herbNameIndex: 16, amountIndex: 29);
    }
    // 简化格式：两列
    return const SalesColumns(herbNameIndex: 0, amountIndex: 1);
  }

  /// 从医疗收费明细表解析销售记录
  ///
  /// 支持：
  /// 1. 收费明细大表（列位置按表头自动识别，列顺序变化不影响）
  /// 2. 简化格式（2列）：药品名称、实收金额
  static List<SalesRecord> parseMedicalSalesData(List<List<dynamic>> data) {
    return parseMedicalSalesDataWithColumns(data).records;
  }

  /// 带列识别结果的解析，便于界面/测试显示识别到了哪几列
  static SalesParseResult parseMedicalSalesDataWithColumns(
    List<List<dynamic>> data,
  ) {
    final List<SalesRecord> records = [];
    final columns = detectColumns(data) ?? _fallbackColumns(data);
    final headerRowIndex = columns.headerRowIndex;
    final minColumns = columns.minColumns;

    int skippedShortRow = 0;
    int skippedNullName = 0;
    int skippedEmptyName = 0;
    int skippedNullAmount = 0;
    int skippedZeroAmount = 0;
    int parsed = 0;

    print('[DEBUG] 列识别: $columns');
    print('[DEBUG] parseMedicalSalesData: 输入 ${data.length} 行数据');

    for (int i = 0; i < data.length; i++) {
      if (i == headerRowIndex) continue;

      final row = data[i];
      if (row.length < minColumns) {
        skippedShortRow++;
        if (skippedShortRow <= 3) {
          print('[DEBUG] 第$i行跳过: 列数不足 (只有${row.length}列, 需要$minColumns列)');
        }
        continue;
      }

      try {
        // 获取药品名称
        final herbNameCell = row[columns.herbNameIndex];
        if (herbNameCell == null) {
          skippedNullName++;
          continue;
        }

        final herbName = herbNameCell.toString().trim();
        // 空名称、占位符、以及表格中间重复出现的表头都跳过
        if (herbName.isEmpty ||
            herbName == '-' ||
            herbName == '--' ||
            _isHerbHeader(_normalizeHeader(herbName))) {
          skippedEmptyName++;
          continue;
        }

        // 获取实收金额
        final amountCell = row[columns.amountIndex];
        final totalAmount = _parseDouble(amountCell);

        if (totalAmount == null) {
          skippedNullAmount++;
          if (skippedNullAmount <= 5) {
            print(
              '[DEBUG] 第$i行金额解析失败: 药材="$herbName", 原始值="$amountCell" (类型: ${amountCell.runtimeType})',
            );
          }
          continue;
        }

        if (totalAmount == 0) {
          skippedZeroAmount++;
          if (skippedZeroAmount <= 5) {
            print('[DEBUG] 第$i行金额为0: 药材="$herbName", 原始值="$amountCell"');
          }
          continue;
        }

        // 创建销售记录
        final record = SalesRecord.fromExcel(
          herbName: herbName,
          quantity: 0, // 医疗明细表不关注数量
          totalAmount: totalAmount,
        );

        records.add(record);
        parsed++;

        // 打印前5条成功解析的记录
        if (parsed <= 5) {
          print(
            '[DEBUG] 成功解析第$i行: 药材="$herbName", 金额=$totalAmount, 分类=${record.category?.name ?? "未识别"}',
          );
        }
      } catch (e) {
        // 跳过无法解析的行
        print('[DEBUG] 第$i行解析异常: $e');
        continue;
      }
    }

    print('\n[DEBUG] 解析统计:');
    print('  成功解析: $parsed 条');
    print('  跳过(列数不足): $skippedShortRow');
    print('  跳过(名称为空): $skippedNullName');
    print('  跳过(名称无效): $skippedEmptyName');
    print('  跳过(金额解析失败): $skippedNullAmount');
    print('  跳过(金额为0): $skippedZeroAmount');

    return SalesParseResult(
      records: records,
      columns: columns,
      totalRows: data.length,
      skippedShortRow: skippedShortRow,
      skippedInvalidName: skippedNullName + skippedEmptyName,
      skippedInvalidAmount: skippedNullAmount,
      skippedZeroAmount: skippedZeroAmount,
    );
  }

  /// 计算税费汇总
  static TaxSummary calculateSummary(List<SalesRecord> records) {
    return TaxSummary(records);
  }

  /// 计算分类税费
  /// 植物类：汇总金额 / 1.09 * 0.09
  /// 动物类、矿物类：汇总金额 / 1.13 * 0.13
  static Map<String, double> calculateCategoryTax(
    Map<HerbCategory, double> categoryTotals,
  ) {
    final result = <String, double>{};

    for (final entry in categoryTotals.entries) {
      final category = entry.key;
      final totalAmount = entry.value;

      double tax = 0.0;
      if (category == HerbCategory.plant) {
        // 植物类：9%税率
        tax = totalAmount / 1.09 * 0.09;
      } else if (category == HerbCategory.animal ||
          category == HerbCategory.mineral) {
        // 动物类、矿物类：13%税率
        tax = totalAmount / 1.13 * 0.13;
      }

      result[category.name] = tax;
    }

    return result;
  }

  /// 解析数字（支持多种格式）
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;

    if (value is double) return value.isFinite ? value : null;
    if (value is int) return value.toDouble();

    var str = value.toString().trim();
    if (str.isEmpty || str == '-' || str == '--' || str == 'null') return null;

    // 移除千分位逗号、货币符号、空格，中文负号转半角
    str = str
        .replaceAll(',', '')
        .replaceAll('，', '')
        .replaceAll('¥', '')
        .replaceAll('￥', '')
        .replaceAll(' ', '')
        .replaceAll('　', '')
        .replaceAll('－', '-');
    // 容忍「1.50元」这类带单位的文本
    if (str.endsWith('元')) str = str.substring(0, str.length - 1);

    return double.tryParse(str);
  }
}

/// 一次解析的结果（含列识别与跳过统计，便于界面提示）
class SalesParseResult {
  const SalesParseResult({
    required this.records,
    required this.columns,
    required this.totalRows,
    this.skippedShortRow = 0,
    this.skippedInvalidName = 0,
    this.skippedInvalidAmount = 0,
    this.skippedZeroAmount = 0,
  });

  final List<SalesRecord> records;
  final SalesColumns columns;
  final int totalRows;
  final int skippedShortRow;
  final int skippedInvalidName;
  final int skippedInvalidAmount;
  final int skippedZeroAmount;
}