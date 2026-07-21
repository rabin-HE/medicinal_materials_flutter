// ignore_for_file: avoid_print

import '../models/herb_category.dart';
import '../models/sales_record.dart';

/// 税费计算服务
class TaxCalculator {
  /// 从医疗收费明细表解析销售记录
  /// 
  /// 支持两种格式：
  /// 1. 原始格式（49列）：第17列（索引16）药品名称，第30列（索引29）实收金额
  /// 2. 简化格式（2列）：第1列（索引0）药品名称，第2列（索引1）实收金额
  static List<SalesRecord> parseMedicalSalesData(List<List<dynamic>> data) {
    final List<SalesRecord> records = [];
    int skippedShortRow = 0;
    int skippedNullName = 0;
    int skippedEmptyName = 0;
    int skippedNullAmount = 0;
    int skippedZeroAmount = 0;
    int parsed = 0;

    // 自动检测格式
    int herbNameIndex;
    int amountIndex;
    int minColumns;
    
    if (data.isNotEmpty && data[0].length >= 30) {
      // 原始格式（49列）
      herbNameIndex = 16;
      amountIndex = 29;
      minColumns = 30;
      print('\n[DEBUG] 检测到原始格式（49列）');
    } else {
      // 简化格式（2列）
      herbNameIndex = 0;
      amountIndex = 1;
      minColumns = 2;
      print('\n[DEBUG] 检测到简化格式（2列）');
    }

    print('[DEBUG] parseMedicalSalesData: 输入 ${data.length} 行数据');
    print('[DEBUG] 药品名称列索引: $herbNameIndex, 实收金额列索引: $amountIndex');

    for (int i = 0; i < data.length; i++) {
      final row = data[i];
      if (row.length < minColumns) {
        skippedShortRow++;
        if (skippedShortRow <= 3) {
          print('[DEBUG] 第${i}行跳过: 列数不足 (只有${row.length}列, 需要$minColumns列)');
        }
        continue;
      }

      try {
        // 获取药品名称
        final herbNameCell = row[herbNameIndex];
        if (herbNameCell == null) {
          skippedNullName++;
          continue;
        }
        
        final herbName = herbNameCell.toString().trim();
        if (herbName.isEmpty || herbName == '-' || herbName == '药品/项目名称') {
          skippedEmptyName++;
          continue;
        }

        // 获取实收金额
        final amountCell = row[amountIndex];
        final totalAmount = _parseDouble(amountCell);

        if (totalAmount == null) {
          skippedNullAmount++;
          if (skippedNullAmount <= 5) {
            print(
              '[DEBUG] 第$i行金额解析失败: 药材="$herbName", 原始值="$amountCell" (类型: $amountCell.runtimeType)',
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

    return records;
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

    if (value is double) return value;
    if (value is int) return value.toDouble();

    final str = value.toString().trim();
    if (str.isEmpty || str == '-' || str == 'null') return null;

    // 移除千分位逗号和空格
    final cleaned = str.replaceAll(',', '').replaceAll(' ', '');

    return double.tryParse(cleaned);
  }
}
