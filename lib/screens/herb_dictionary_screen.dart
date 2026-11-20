import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/herb_category.dart';
import '../services/dictionary_excel.dart';
import '../services/herb_dictionary.dart';
import '../utils/file_saver.dart';

/// 药材字典维护页面
///
/// 字典分两层：仓库内置（assets/herb_dictionary.json）+ 本机修改。
/// 本机修改保存在浏览器本地，导出 JSON 覆盖仓库文件并提交后即可固化给所有人用。
class HerbDictionaryScreen extends StatefulWidget {
  const HerbDictionaryScreen({super.key, this.initialQuery = ''});

  /// 从「未识别药材」跳转过来时预填的搜索词
  final String initialQuery;

  @override
  State<HerbDictionaryScreen> createState() => _HerbDictionaryScreenState();
}

class _HerbDictionaryScreenState extends State<HerbDictionaryScreen> {
  late final TextEditingController _searchController;
  HerbCategory? _filter;
  bool _busy = false;

  HerbDictionary get _dict => HerbDictionary.instance;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HerbEntry> get _visibleEntries {
    final keyword = HerbDictionary.normalize(_searchController.text);
    return _dict.entries.where((entry) {
      if (_filter != null && entry.category != _filter) return false;
      if (keyword.isEmpty) return true;
      return HerbDictionary.normalize(entry.name).contains(keyword);
    }).toList();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _showEditDialog({HerbEntry? entry}) async {
    final nameController = TextEditingController(text: entry?.name ?? '');
    var selected = entry?.category ?? HerbCategory.plant;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(entry == null ? '新增药材' : '修改药材'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: entry == null,
                decoration: const InputDecoration(
                  labelText: '药材名称',
                  hintText: '例如：乌梢蛇',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: HerbCategory.values.map((category) {
                  return ChoiceChip(
                    label: Text(
                      '${category.name} ${(category.taxRate * 100).toStringAsFixed(0)}%',
                    ),
                    selected: selected == category,
                    onSelected: (_) => setDialogState(() => selected = category),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      _toast('药材名称不能为空');
      return;
    }

    final existing = _dict.lookup(name);
    if (entry == null && existing != null) {
      _toast('「$name」已存在（${existing.name}），已更新为 ${selected.name}');
    }
    await _dict.upsert(name, selected);
    if (!mounted) return;
    setState(() {});
    _toast('已保存「$name」→ ${selected.name}（本机生效，导出后才会固化到仓库）');
  }

  Future<void> _confirmDelete(HerbEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除药材'),
        content: Text('确定要从字典中删除「${entry.name}」吗？删除后该药材将按未识别处理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _dict.removeHerb(entry.name);
    if (!mounted) return;
    setState(() {});
    _toast('已删除「${entry.name}」');
  }

  Future<void> _importFile() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'json'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _toast('无法读取文件内容');
        return;
      }

      final extension = (file.extension ?? '').toLowerCase();
      Map<String, HerbCategory> incoming;
      var skipped = <String>[];
      if (extension == 'json') {
        incoming = HerbDictionary.parseDictionaryJson(utf8.decode(bytes));
      } else {
        final parsed = DictionaryExcel.parse(bytes);
        incoming = parsed.herbs;
        skipped = parsed.skippedRows;
      }
      if (incoming.isEmpty) {
        _toast('文件里没有可用的药材条目');
        return;
      }

      final merged = await _dict.merge(incoming);
      if (!mounted) return;
      setState(() {});
      _toast(
        '导入完成：${merged.toString()}'
        '${skipped.isEmpty ? '' : '；${skipped.length} 行无法识别，例如 ${skipped.first}'}',
      );
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportJson() async {
    try {
      final bytes = Uint8List.fromList(utf8.encode(_dict.exportJson()));
      final message = await saveBytesToFile(
        fileName: 'herb_dictionary.json',
        bytes: bytes,
        mimeType: 'application/json;charset=utf-8',
      );
      _toast(
        '${message ?? '已导出'}；用它覆盖仓库里的 assets/herb_dictionary.json 并提交，即可固化为内置字典',
      );
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _exportExcel() async {
    try {
      final bytes = DictionaryExcel.exportBytes(_dict.herbs);
      final message = await saveBytesToFile(
        fileName: 'herb_dictionary.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      _toast(message ?? '已导出');
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _resetLocalChanges() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤销本机修改'),
        content: Text(
          '将清除本机对字典的 ${_dict.overrideCount} 项修改（新增、改类别、删除），'
          '恢复到仓库内置的 ${_dict.baseCount} 味药材。已导出的文件不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _dict.resetLocalChanges();
    if (!mounted) return;
    setState(() {});
    _toast('已恢复为内置字典');
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('字典怎么维护'),
        content: const SingleChildScrollView(
          child: Text(
            '1. 内置字典在仓库的 assets/herb_dictionary.json，随网页一起部署，是所有人的基础数据。\n\n'
            '2. 在这里新增/改类别/删除，只是改「本机」的副本，立刻生效，不动仓库。\n\n'
            '3. 改完点「导出 JSON」，用导出的文件覆盖 assets/herb_dictionary.json 并提交，'
            '重新部署后就是新的内置字典（也可以把这当成字典的备份）。\n\n'
            '4. 导入支持 .json 和 .xlsx：Excel 需要两列「药材名称」「类别」，类别写植物类/动物类/矿物类。\n\n'
            '5. 名字里的全角/半角括号、多余空格会自动兼容，不会因为写法不同就查不到。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('药材字典'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: '说明',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
          ),
          PopupMenuButton<String>(
            tooltip: '导入 / 导出',
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _importFile();
                  break;
                case 'exportJson':
                  _exportJson();
                  break;
                case 'exportExcel':
                  _exportExcel();
                  break;
                case 'reset':
                  _resetLocalChanges();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('导入（Excel / JSON）'),
                ),
              ),
              const PopupMenuItem(
                value: 'exportJson',
                child: ListTile(
                  leading: Icon(Icons.data_object),
                  title: Text('导出 JSON（可提交到仓库）'),
                ),
              ),
              const PopupMenuItem(
                value: 'exportExcel',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('导出 Excel'),
                ),
              ),
              PopupMenuItem(
                value: 'reset',
                enabled: _dict.hasLocalChanges,
                child: const ListTile(
                  leading: Icon(Icons.settings_backup_restore),
                  title: Text('撤销本机修改'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(entries.length),
                _buildSearchField(),
                _buildFilterChips(),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(
                          child: Text(
                            '没有匹配的药材',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) =>
                              _buildEntryTile(entries[index]),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('新增药材'),
      ),
    );
  }

  Widget _buildHeader(int visibleCount) {
    final dict = _dict;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '内置 ${dict.baseCount} 味 · 本机修改 ${dict.overrideCount} 项',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Text(
            '当前显示 $visibleCount 项',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: '搜索药材名称',
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('全部 ${_dict.herbs.length}'),
            selected: _filter == null,
            onSelected: (_) => setState(() => _filter = null),
          ),
          ...HerbCategory.values.map(
            (category) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(
                  '${category.name} ${_dict.countOf(category)}',
                ),
                selected: _filter == category,
                onSelected: (_) => setState(() => _filter = category),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(HerbEntry entry) {
    return ListTile(
      dense: true,
      title: Row(
        children: [
          Flexible(child: Text(entry.name)),
          if (entry.isOverridden) ...[
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 14, color: Colors.orange),
          ],
        ],
      ),
      subtitle: Text(
        '${entry.category.name} · ${(entry.category.taxRate * 100).toStringAsFixed(0)}%',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '修改类别',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _showEditDialog(entry: entry),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(entry),
          ),
        ],
      ),
    );
  }
}