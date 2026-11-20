import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import '../models/herb_category.dart';
import '../models/sales_record.dart';
import '../services/tax_calculator.dart';
import '../services/excel_preprocessor.dart';
import '../services/herb_dictionary.dart';
import 'herb_dictionary_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SalesRecord> _records = [];
  TaxSummary? _summary;
  Map<String, double>? _categoryTax;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _pickExcelFile() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null) {
        setState(() {
          _errorMessage = '无法读取文件';
          _isLoading = false;
        });
        return;
      }

      Excel excel;
      try {
        excel = Excel.decodeBytes(bytes);
      } catch (e) {
        // Excel解析失败，尝试预处理
        print('[DEBUG] Excel解析失败: $e');
        print('[DEBUG] 尝试预处理文件...');

        try {
          // 使用纯Dart预处理器修复xlsx文件
          final fixedBytes = ExcelPreprocessor.fixExcelBytes(bytes);
          excel = Excel.decodeBytes(fixedBytes);
          print('[DEBUG] 成功读取预处理后的文件');
        } catch (e2) {
          print('[DEBUG] 预处理后的文件仍然无法解析: $e2');
          setState(() {
            _errorMessage = '预处理后的Excel文件仍然无法解析: $e2';
            _isLoading = false;
          });
          return;
        }
      }

      // 读取第一个工作表
      if (excel.tables.isEmpty) {
        setState(() {
          _errorMessage = 'Excel 文件中没有工作表';
          _isLoading = false;
        });
        return;
      }

      // 调试输出：显示所有工作表名称
      print('\n=== 工作表信息 ===');
      print('工作表数量: ${excel.tables.length}');
      for (final name in excel.tables.keys) {
        print('  - "$name" (长度: ${name.length})');
      }

      // 尝试获取第一个工作表
      final firstSheetName = excel.tables.keys.first;
      print('选择的工作表: "$firstSheetName"');

      final sheet = excel.tables[firstSheetName];
      if (sheet == null || sheet.rows.isEmpty) {
        setState(() {
          _errorMessage = '工作表为空';
          _isLoading = false;
        });
        return;
      }

      // 解析数据（跳过标题行）
      final data = <List<dynamic>>[];
      print('=== 开始读取Excel数据 ===');
      print('总行数: ${sheet.rows.length}');

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        final rowData = <dynamic>[];
        for (final cell in row) {
          rowData.add(cell?.value);
        }
        data.add(rowData);

        // 打印前5行原始数据用于调试
        if (i <= 5) {
          print('第${i}行数据:');
          if (rowData.length > 16) {
            print('  药品名称(列17): ${rowData[16]}');
          }
          if (rowData.length > 29) {
            print('  实收金额(列30): ${rowData[29]}');
          }
          if (rowData.length == 2) {
            print('  药品名称(列1): ${rowData[0]}');
            print('  实收金额(列2): ${rowData[1]}');
          }
        }
      }
      print('成功读取 ${data.length} 行数据');

      // 计算税费
      debugPrint('\n=== 开始解析销售数据 ===');
      final records = TaxCalculator.parseMedicalSalesData(data);
      debugPrint('成功解析 ${records.length} 条销售记录');

      // 打印前10条记录的详细信息
      if (records.isNotEmpty) {
        debugPrint('\n--- 前10条记录详情 ---');
        for (int i = 0; i < records.length && i < 10; i++) {
          final record = records[i];
          debugPrint('${i + 1}. ${record.herbName}');
          debugPrint('   金额: ${record.totalAmount}');
          debugPrint('   分类: ${record.category?.name ?? "未识别"}');
          debugPrint('   税率: ${(record.taxRate * 100).toStringAsFixed(0)}%');
        }
      }

      final summary = TaxCalculator.calculateSummary(records);
      debugPrint('\n=== 计算汇总结果 ===');
      debugPrint('总金额: ${summary.totalAmount.toStringAsFixed(2)}');
      debugPrint('总税额: ${summary.totalTaxAmount.toStringAsFixed(2)}');

      // 打印各分类统计
      debugPrint('\n--- 分类统计 ---');
      for (final category in HerbCategory.values) {
        final total = summary.categoryTotals[category] ?? 0.0;
        final tax = summary.categoryTaxTotals[category] ?? 0.0;
        final count = summary.byCategory[category]?.length ?? 0;
        debugPrint(
          '${category.name}: $count 项, 金额: ${total.toStringAsFixed(2)}, 税额: ${tax.toStringAsFixed(2)}',
        );
      }

      // 打印未识别药材
      if (summary.unidentifiedRecords.isNotEmpty) {
        debugPrint('\n--- 未识别药材 (${summary.unidentifiedRecords.length} 项) ---');
        for (final record in summary.unidentifiedRecords.take(10)) {
          debugPrint('  ${record.herbName}: ${record.totalAmount}');
        }
      }

      final categoryTax = TaxCalculator.calculateCategoryTax(
        summary.categoryTotals,
      );
      debugPrint('\n=== 分类税费计算 ===');
      for (final entry in categoryTax.entries) {
        debugPrint('${entry.key}: ${entry.value.toStringAsFixed(2)}');
      }

      setState(() {
        _records = records;
        _summary = summary;
        _categoryTax = categoryTax;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '处理文件时出错: $e';
        _isLoading = false;
      });
    }
  }

  /// 字典变化后重新归类并重算（SalesRecord 不可变，整体重建一遍）
  void _recompute() {
    if (_records.isEmpty) return;
    final rebuilt = _records
        .map(
          (record) => SalesRecord.fromExcel(
            herbName: record.herbName,
            quantity: record.quantity,
            totalAmount: record.totalAmount,
          ),
        )
        .toList();
    final summary = TaxCalculator.calculateSummary(rebuilt);
    setState(() {
      _records = rebuilt;
      _summary = summary;
      _categoryTax = TaxCalculator.calculateCategoryTax(summary.categoryTotals);
    });
  }

  /// 打开药材字典；回来后重算，字典改动能立刻反映到税额上
  Future<void> _openDictionary({String initialQuery = ''}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HerbDictionaryScreen(initialQuery: initialQuery),
      ),
    );
    if (!mounted) return;
    _recompute();
  }

  /// 给某个未识别药材直接指定类别
  Future<void> _assignCategory(String herbName) async {
    final category = await showDialog<HerbCategory>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('「$herbName」属于哪一类？'),
        children: [
          ...HerbCategory.values.map(
            (value) => SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${value.name}（${(value.taxRate * 100).toStringAsFixed(0)}%）',
                ),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('取消'),
            ),
          ),
        ],
      ),
    );
    if (category == null) return;

    await HerbDictionary.instance.upsert(herbName, category);
    if (!mounted) return;
    _recompute();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('「$herbName」已归类为${category.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('税费计算器'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: '药材字典（${HerbDictionary.instance.herbs.length} 味）',
            icon: const Icon(Icons.menu_book),
            onPressed: _openDictionary,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summary == null
          ? _buildEmptyState()
          : _buildSummaryView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickExcelFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('导入 Excel'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.file_upload,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const SelectableText(
            '请导入收费明细 Excel 文件',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const SelectableText(
            '系统将自动分类并计算税费',
            style: TextStyle(color: Colors.grey),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            SelectableText(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_summary!.unidentifiedRecords.isNotEmpty) ...[
            _buildUnidentifiedBanner(),
            const SizedBox(height: 16),
          ],
          _buildTotalCard(),
          const SizedBox(height: 16),
          _buildCategoryBreakdown(),
          if (_summary!.unidentifiedRecords.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildUnidentifiedList(),
          ],
          const SizedBox(height: 16),
          _buildDetailList(),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SelectableText(
              '总计',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildSummaryRow('总金额（实收）', _summary!.totalAmount),
            _buildSummaryRow(
              '总税额',
              _summary!.totalTaxAmount,
              color: Colors.red,
            ),
            _buildSummaryRow('总不含税金额', _summary!.totalPreTaxAmount),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SelectableText(label),
          SelectableText(
            '¥ ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SelectableText(
              '分类统计及税费计算',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...HerbCategory.values.map((category) {
              final total = _summary!.categoryTotals[category] ?? 0.0;
              final tax = _categoryTax?[category.name] ?? 0.0;
              final count = _summary!.byCategory[category]?.length ?? 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SelectableText(
                          '${category.name} (${(category.taxRate * 100).toStringAsFixed(0)}%)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SelectableText('$count 项'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SelectableText('汇总金额: ¥ ${total.toStringAsFixed(2)}'),
                        SelectableText(
                          '税费: ¥ ${tax.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      category == HerbCategory.plant
                          ? '计算公式: ¥${total.toStringAsFixed(2)} / 1.09 × 0.09 = ¥${tax.toStringAsFixed(2)}'
                          : '计算公式: ¥${total.toStringAsFixed(2)} / 1.13 × 0.13 = ¥${tax.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 未识别药材的红色警告：这部分金额现在按 0 税率，总税额会偏低
  Widget _buildUnidentifiedBanner() {
    final records = _summary!.unidentifiedRecords;
    final amount = records.fold<double>(0, (sum, r) => sum + r.totalAmount);
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '有 ${records.length} 项药材不在字典中，涉及 ¥ ${amount.toStringAsFixed(2)} '
                '未计税，总税额偏低。请在下方「未识别药材」里点「归类」补齐。',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _openDictionary(initialQuery: records.first.herbName),
              child: const Text('打开字典'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnidentifiedList() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                SelectableText(
                  '未识别药材 (${_summary!.unidentifiedRecords.length} 项)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._summary!.unidentifiedRecords.map((record) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        '${record.herbName}: ¥ ${record.totalAmount.toStringAsFixed(2)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _assignCategory(record.herbName),
                      child: const Text('归类'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '详细清单',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._records.map((record) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            record.herbName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          record.category?.name ?? '未知',
                          style: TextStyle(
                            color: record.category == null
                                ? Colors.orange
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('实收: ¥ ${record.totalAmount.toStringAsFixed(2)}'),
                        Text(
                          '税率: ${(record.taxRate * 100).toStringAsFixed(0)}%',
                        ),
                      ],
                    ),
                    const Divider(),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
