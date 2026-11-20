import 'herb_category.dart';
import '../services/herb_dictionary.dart';

/// 销售记录模型
class SalesRecord {
  final String herbName;
  final double quantity;
  final double totalAmount;
  final HerbCategory? category;
  final double taxRate;

  SalesRecord({
    required this.herbName,
    required this.quantity,
    required this.totalAmount,
    this.category,
    required this.taxRate,
  });

  /// 从 Excel 数据创建销售记录
  factory SalesRecord.fromExcel({
    required String herbName,
    required double quantity,
    required double totalAmount,
  }) {
    final category = HerbDictionary.instance.lookup(herbName);
    final taxRate = category?.taxRate ?? 0.0;

    return SalesRecord(
      herbName: herbName,
      quantity: quantity,
      totalAmount: totalAmount,
      category: category,
      taxRate: taxRate,
    );
  }

  /// 计算不含税金额
  double get preTaxAmount {
    if (taxRate == 0) return totalAmount;
    return totalAmount / (1 + taxRate);
  }

  /// 计算税额
  double get taxAmount {
    return totalAmount - preTaxAmount;
  }

  /// 格式化显示
  @override
  String toString() {
    return '药材: $herbName, 数量: $quantity, 总价: $totalAmount, '
        '分类: ${category?.name ?? "未知"}, 税率: ${(taxRate * 100).toStringAsFixed(0)}%, '
        '不含税金额: ${preTaxAmount.toStringAsFixed(2)}, 税额: ${taxAmount.toStringAsFixed(2)}';
  }
}

/// 汇总结果模型
class TaxSummary {
  final List<SalesRecord> records;

  TaxSummary(this.records);

  /// 总金额（含税）
  double get totalAmount {
    return records.fold(0.0, (sum, record) => sum + record.totalAmount);
  }

  /// 总税额
  double get totalTaxAmount {
    return records.fold(0.0, (sum, record) => sum + record.taxAmount);
  }

  /// 总不含税金额
  double get totalPreTaxAmount {
    return records.fold(0.0, (sum, record) => sum + record.preTaxAmount);
  }

  /// 按分类汇总
  Map<HerbCategory, List<SalesRecord>> get byCategory {
    final Map<HerbCategory, List<SalesRecord>> result = {};
    for (final record in records) {
      if (record.category != null) {
        result.putIfAbsent(record.category!, () => []);
        result[record.category!]!.add(record);
      }
    }
    return result;
  }

  /// 按分类统计金额
  Map<HerbCategory, double> get categoryTotals {
    final Map<HerbCategory, double> result = {};
    for (final record in records) {
      if (record.category != null) {
        result[record.category!] =
            (result[record.category!] ?? 0.0) + record.totalAmount;
      }
    }
    return result;
  }

  /// 按分类统计税额
  Map<HerbCategory, double> get categoryTaxTotals {
    final Map<HerbCategory, double> result = {};
    for (final record in records) {
      if (record.category != null) {
        result[record.category!] =
            (result[record.category!] ?? 0.0) + record.taxAmount;
      }
    }
    return result;
  }

  /// 未识别药材列表
  List<SalesRecord> get unidentifiedRecords {
    return records.where((record) => record.category == null).toList();
  }

  /// 格式化显示汇总
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== 税费汇总 ===');
    buffer.writeln('总金额（含税）: ${totalAmount.toStringAsFixed(2)}');
    buffer.writeln('总税额: ${totalTaxAmount.toStringAsFixed(2)}');
    buffer.writeln('总不含税金额: ${totalPreTaxAmount.toStringAsFixed(2)}');
    buffer.writeln();

    buffer.writeln('--- 按分类统计 ---');
    for (final category in HerbCategory.values) {
      final total = categoryTotals[category] ?? 0.0;
      final tax = categoryTaxTotals[category] ?? 0.0;
      final count = byCategory[category]?.length ?? 0;
      buffer.writeln('${category.name}: $count 项, '
          '金额: ${total.toStringAsFixed(2)}, '
          '税额: ${tax.toStringAsFixed(2)}');
    }

    if (unidentifiedRecords.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('--- 未识别药材 (${unidentifiedRecords.length} 项) ---');
      for (final record in unidentifiedRecords) {
        buffer.writeln('  ${record.herbName}: ${record.totalAmount}');
      }
    }

    return buffer.toString();
  }
}
