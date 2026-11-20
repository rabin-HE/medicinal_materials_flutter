/// 药材分类枚举
///
/// 「药材名 → 分类」的对照表不写死在代码里，而是放在
/// `assets/herb_dictionary.json`，运行时由 `HerbDictionary` 加载，
/// 并可在应用内维护（见「药材字典」页面）。
enum HerbCategory {
  plant('植物类', 0.09, 'plant'),
  animal('动物类', 0.13, 'animal'),
  mineral('矿物类', 0.13, 'mineral');

  /// 中文类别名，用于界面显示
  final String name;

  /// 税率
  final double taxRate;

  /// 字典文件中的分类标识（plant / animal / mineral）
  final String id;

  const HerbCategory(this.name, this.taxRate, this.id);

  /// 根据字典中的标识解析分类，如 `plant`
  static HerbCategory? fromId(String id) {
    final key = id.trim().toLowerCase();
    for (final category in values) {
      if (category.id == key) return category;
    }
    return null;
  }

  /// 宽松解析类别名，支持「植物类」「植物」「plant」「植物类(9%)」
  static HerbCategory? fromName(String name) {
    final key = name.trim();
    if (key.isEmpty) return null;
    for (final category in values) {
      if (category.name == key || category.id == key.toLowerCase()) {
        return category;
      }
    }
    if (key.contains('植')) return HerbCategory.plant;
    if (key.contains('动')) return HerbCategory.animal;
    if (key.contains('矿')) return HerbCategory.mineral;
    return null;
  }
}