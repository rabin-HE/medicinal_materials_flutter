import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/herb_category.dart';

/// 字典中的一个药材条目
class HerbEntry {
  final String name;
  final HerbCategory category;

  /// 是否被本地修改过（与仓库内置字典不一致）
  final bool isOverridden;

  const HerbEntry(this.name, this.category, {this.isOverridden = false});
}

/// 一次导入（合并）的结果
class DictionaryImportResult {
  final int added;
  final int updated;
  final int unchanged;
  final int skipped;

  /// 被跳过的原始行，便于界面提示
  final List<String> skippedRows;

  const DictionaryImportResult({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.skipped = 0,
    this.skippedRows = const [],
  });

  int get changed => added + updated;

  @override
  String toString() =>
      '新增 $added 项，修改 $updated 项，未变 $unchanged 项，跳过 $skipped 项';
}

/// 药材字典
///
/// 数据来源分三层：
/// 1. `assets/herb_dictionary.json` —— 仓库内置字典（随 web 部署发布，主要维护放在这里）；
/// 2. 浏览器本地修改（SharedPreferences，web 端即 localStorage）—— 应用内增加/改类别/删除；
/// 3. 导入的文件（Excel / JSON）—— 合并进本地修改层。
///
/// 内置字典更新（重新部署）后，本地修改仍然叠加在上面，所以不会因为换版本丢数据；
/// 「导出字典」得到的是合并后的完整字典，用它可以覆盖仓库里的 assets 文件并提交。
class HerbDictionary {
  HerbDictionary._();

  static final HerbDictionary instance = HerbDictionary._();

  static const String assetPath = 'assets/herb_dictionary.json';
  static const String prefsKey = 'herb_dictionary_overrides_v1';

  final Map<String, HerbCategory> _base = {};
  final Map<String, HerbCategory> _overrides = {};
  final Set<String> _removed = {};

  /// 归一化名称 → 分类，用于兼容全角/半角括号、多余空格等写法差异
  final Map<String, HerbCategory> _normalizedIndex = {};

  /// 归一化名称 → 字典中的标准写法（避免同一药材两种括号写法各存一条）
  final Map<String, String> _canonicalNames = {};

  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 仓库内置字典条目数
  int get baseCount => _base.length;

  /// 本地修改条目数（新增/改类别 + 删除）
  int get overrideCount => _overrides.length + _removed.length;

  bool get hasLocalChanges => _overrides.isNotEmpty || _removed.isNotEmpty;

  /// 合并后的完整字典（key 顺序即字典文件中的顺序）
  Map<String, HerbCategory> get herbs {
    final merged = Map<String, HerbCategory>.from(_base);
    for (final entry in _overrides.entries) {
      merged[entry.key] = entry.value;
    }
    _removed.forEach(merged.remove);
    return Map.unmodifiable(merged);
  }

  /// 全部条目，按字典顺序
  List<HerbEntry> get entries => herbs.entries
      .map((e) => HerbEntry(
            e.key,
            e.value,
            isOverridden: _overrides.containsKey(e.key),
          ))
      .toList();

  int countOf(HerbCategory category) =>
      herbs.values.where((c) => c == category).length;

  /// 归一化：去掉空白，统一全角括号，英文转小写
  static String normalize(String name) {
    var s = name.trim().replaceAll(RegExp(r'\s+'), '');
    const mapping = {
      '（': '(',
      '）': ')',
      '［': '[',
      '］': ']',
      '【': '[',
      '】': ']',
      '，': ',',
      '－': '-',
      '　': '',
    };
    mapping.forEach((from, to) => s = s.replaceAll(from, to));
    return s.toLowerCase();
  }

  /// 查找药材分类；未收录返回 null
  HerbCategory? lookup(String herbName) {
    final name = herbName.trim();
    if (name.isEmpty) return null;
    final exact = herbs[name];
    if (exact != null) return exact;
    return _normalizedIndex[normalize(name)];
  }

  /// 加载内置字典 + 本地修改
  ///
  /// [assetJson] 仅用于测试注入，正常运行时读取 assets。
  Future<void> load({String? assetJson}) async {
    final raw = assetJson ?? await rootBundle.loadString(assetPath);
    final base = parseDictionaryJson(raw);
    _base
      ..clear()
      ..addAll(base);

    await _loadOverrides();
    _loaded = true;
    _rebuildIndex();
  }

  Future<void> _loadOverrides() async {
    _overrides.clear();
    _removed.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final overrides = decoded['overrides'];
      if (overrides is Map) {
        overrides.forEach((key, value) {
          final category = HerbCategory.fromId(value.toString());
          if (category != null) _overrides[key.toString()] = category;
        });
      }
      final removed = decoded['removed'];
      if (removed is List) {
        _removed.addAll(
          removed.map((e) => e.toString()).where((e) => e.isNotEmpty),
        );
      }
    } catch (e) {
      // 本地数据损坏不应该阻断应用，忽略并继续用内置字典
      debugPrint('[HerbDictionary] 读取本地修改失败: $e');
    }
  }

  void _rebuildIndex() {
    _normalizedIndex.clear();
    _canonicalNames.clear();
    for (final entry in herbs.entries) {
      final key = normalize(entry.key);
      _normalizedIndex.putIfAbsent(key, () => entry.value);
      _canonicalNames.putIfAbsent(key, () => entry.key);
    }
  }

  /// 找到字典里已有的标准写法，没有就返回原名（去空白）
  String _resolveKey(String name) {
    final trimmed = name.trim();
    return _canonicalNames[normalize(trimmed)] ?? trimmed;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_overrides.isEmpty && _removed.isEmpty) {
        await prefs.remove(prefsKey);
        return;
      }
      await prefs.setString(
        prefsKey,
        jsonEncode({
          'version': 1,
          'overrides': {
            for (final e in _overrides.entries) e.key: e.value.id,
          },
          'removed': _removed.toList(),
        }),
      );
    } catch (e) {
      debugPrint('[HerbDictionary] 保存本地修改失败: $e');
    }
  }

  /// 新增或修改一个药材的分类
  Future<void> upsert(String name, HerbCategory category) async {
    final key = _resolveKey(name);
    if (key.isEmpty) throw ArgumentError('药材名称不能为空');
    if (_base[key] == category && !_overrides.containsKey(key)) {
      // 与内置字典一致，无需记录覆盖
      _removed.remove(key);
      _rebuildIndex();
      await _persist();
      return;
    }
    _overrides[key] = category;
    _removed.remove(key);
    _rebuildIndex();
    await _persist();
  }

  /// 删除一个药材
  Future<void> removeHerb(String name) async {
    final key = _resolveKey(name);
    _overrides.remove(key);
    if (_base.containsKey(key)) {
      _removed.add(key);
    }
    _rebuildIndex();
    await _persist();
  }

  /// 撤销所有本地修改，回到仓库内置字典
  Future<void> resetLocalChanges() async {
    _overrides.clear();
    _removed.clear();
    _rebuildIndex();
    await _persist();
  }

  /// 解析字典 JSON 文本（格式：{"herbs": {"药材名": "plant"}}）
  static Map<String, HerbCategory> parseDictionaryJson(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('字典文件格式错误：顶层应为 JSON 对象');
    }
    final herbs = decoded['herbs'];
    if (herbs is! Map) {
      throw const FormatException('字典文件格式错误：缺少 herbs 字段');
    }
    final result = <String, HerbCategory>{};
    herbs.forEach((key, value) {
      final name = key.toString().trim();
      final category =
          HerbCategory.fromId(value.toString()) ??
              HerbCategory.fromName(value.toString());
      if (name.isEmpty || category == null) return;
      result[name] = category;
    });
    return result;
  }

  /// 把一批条目合并进字典（用于 Excel / JSON 导入），一次写入本地存储
  Future<DictionaryImportResult> merge(
    Map<String, HerbCategory> incoming,
  ) async {
    var added = 0;
    var updated = 0;
    var unchanged = 0;

    HerbCategory? currentOf(String key) =>
        _overrides[key] ?? (_removed.contains(key) ? null : _base[key]);

    for (final entry in incoming.entries) {
      if (entry.key.trim().isEmpty) continue;
      final key = _resolveKey(entry.key);
      final current = currentOf(key);
      if (current == null) {
        added++;
      } else if (current != entry.value) {
        updated++;
      } else {
        unchanged++;
      }
      if (_base[key] != entry.value || _overrides.containsKey(key)) {
        _overrides[key] = entry.value;
      }
      _removed.remove(key);
    }

    _rebuildIndex();
    await _persist();
    return DictionaryImportResult(
      added: added,
      updated: updated,
      unchanged: unchanged,
    );
  }

  /// 导出完整字典 JSON（可覆盖 assets/herb_dictionary.json 后提交）
  String exportJson() {
    final merged = herbs;
    final buffer = StringBuffer()
      ..writeln('{')
      ..writeln('  "version": 1,')
      ..writeln(
        '  "categories": {"plant": "植物类", "animal": "动物类", "mineral": "矿物类"},',
      )
      ..writeln('  "herbs": {');
    final names = merged.keys.toList();
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final comma = i == names.length - 1 ? '' : ',';
      buffer.writeln(
        '    ${jsonEncode(name)}: "${merged[name]!.id}"$comma',
      );
    }
    buffer
      ..writeln('  }')
      ..writeln('}');
    return buffer.toString();
  }
}