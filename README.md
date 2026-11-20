# medicinal_materials_flutter

A Flutter project.

## Getting Started

rebuild method
```
#Flutter
flutter clean
flutter pub get
flutter build web --release

#docker
docker compose up -d --build

#chorme
ctrl + shift + r
```

## 药材字典（分类对照表）

字典数据在 `assets/herb_dictionary.json`，格式：

```json
{
  "version": 1,
  "herbs": { "乌梢蛇": "animal", "辽藁本": "plant" }
}
```

类别取值：`plant` 植物类 9%、`animal` 动物类 13%、`mineral` 矿物类 13%。

维护方式：

1. 网页端右上角书本图标 →「药材字典」：新增 / 改类别 / 删除，改完立刻生效。改动存在浏览器本地（localStorage），只影响这台机器，不动仓库。
2. 改完点「导出 JSON」，用导出的文件覆盖 `assets/herb_dictionary.json` 并提交，重新 `flutter build web --release` 部署，就是新的内置字典（也可当备份）。
3. 也支持导入 `.xlsx`（两列：药材名称 / 类别）或 `.json`，适合批量维护。
4. 未收录的药材按 0 税率计入，结果页会红字提示「税额偏低」，在「未识别药材」列表点「归类」可当场补上并重算。
5. 名称中的全角/半角括号、多余空格自动兼容，同一药材两种写法都能命中同一条。

注意：改了字典必须重新 build 并部署，否则线上仍是旧的 JSON。