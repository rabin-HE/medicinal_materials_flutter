# medicinal_materials_flutter

A Flutter project.

## 手工构建与部署（每次改完代码走这套）

前置：本机已在 `/home/he22/develop/flutter` 装好 Flutter，Docker 可用。**跑 flutter 前先
`unset` 代理**——本机 Clash 常开，Dart/Node 走 `HTTP_PROXY` 会卡在 `pub get` 或构建阶段。

### 第 1 步：构建 Web 产物（每次都要）

```
cd /home/he22/work/flutterApp/medicinal_materials_flutter
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy

flutter pub get
# --release 去掉 debug 角标；--no-web-resources-cdn 让 CanvasKit 走本地（必须，原因见下）
flutter build web --release --no-web-resources-cdn

tool/check_web_build.sh          # 必须输出 OK，不通过就别往下部署
```

- 只在换 Flutter 版本、换依赖、或怀疑缓存脏时才需要 `flutter clean`（会明显变慢，日常不必）。
- 产物在 `build/web`（约 47MB：`canvaskit/` 7MB + 两支字体 4MB + `main.dart.js` 2.9MB）。
- 本机实测构建约 28~36 秒。

### 第 2 步：打包镜像并重启容器

```
docker compose up -d --build
docker compose ps                # 状态应是 healthy；unhealthy 请看下面「健康检查」一节
```

Dockerfile 只做 `COPY build/web` + `COPY nginx.conf`，**它不编译 Dart**。所以第 1 步漏掉的话，
镜像里装的还是上一次的前端——改了 dart 代码、字体、`assets/herb_dictionary.json` 都必须重跑第 1 步。
不用 `down`，不用 `--no-cache`（实测镜像构建 0.5 秒内完成）。

### 第 3 步：验收

```
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18082/                    # 期望 200
curl -s http://127.0.0.1:18082/flutter_bootstrap.js | grep -o '"useLocalCanvasKit":true'
curl -sI http://127.0.0.1:18082/ | grep -i cache-control                            # 期望 no-store
```

浏览器打开 `http://192.168.1.103:18082/`，应看到绿色标题栏「税费计算器」+ 导入提示。

看到旧界面或白屏时，先清一次站点数据：F12 → Application → Storage → Clear site data
（或换一个没访问过的 URL、开无痕窗口）。旧版本留下的响应带 `immutable`，普通刷新和
Ctrl+Shift+R 都可能绕不过去。

### 日常最短路径

改动只是 Dart 代码 / 字体 / 字典时，一条命令搞定：

```
cd /home/he22/work/flutterApp/medicinal_materials_flutter && \
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy && \
flutter build web --release --no-web-resources-cdn && tool/check_web_build.sh && docker compose up -d --build
```

### 健康检查

`docker-compose.yml` 里健康检查固定访问 `http://127.0.0.1/`，不用 `localhost`：容器里的
busybox wget 会把 `localhost` 解析成 `[::1]`，而 nginx 只监听 IPv4，会一直
`Connection refused` 被判定 `unhealthy`。

### 主界面全白（连标题栏都没有）怎么办

先分清两种白：

1. **整个页面纯白、devtools 里只有一个 `<script>`、控制台只有一条
   `Failed to fetch dynamically imported module: https://www.gstatic.com/flutter-canvaskit/<rev>/canvaskit.js`**
   —— 构建产物在等 gstatic 上的 CanvasKit，网络到不了就永远不出图。这就是
   `flutter build web` 的默认行为（`--web-resources-cdn` 默认开）。构建时加
   `--no-web-resources-cdn`，CanvasKit 就会从产物自带的 `canvaskit/` 取。
   验证：`tool/check_web_build.sh` 会检查 `flutter_bootstrap.js` 里
   `"useLocalCanvasKit":true`。
2. **有绿色标题栏、内容区白** —— 那是业务状态问题（没导入文件），不是白屏 bug。

另外：`main.dart.js` / `flutter_bootstrap.js` 这些文件名不带内容指纹，nginx 以前给它们
打了 `immutable, max-age=1年`，重新部署后浏览器会一直用旧脚本（刷新无效）。现在
nginx.conf 里入口 HTML 是 `no-store`，入口脚本与 `assets/` 是 `no-cache`，
只有 `canvaskit/`、`icons/` 才长缓存。

因为旧响应带的是 `immutable`，这次升级后每台机器需要**清一次站点数据**（F12 →
Application → Storage → Clear site data，或换一个没访问过的 URL/无痕窗口）才能真正拿到新产物；
之后就不会再有这个问题。

### 内置字体（离线/墙内必须）

CanvasKit 画字用的是自己的字体栈：默认从 `fonts.gstatic.com` 拉 Roboto 和 Noto Sans SC
兜底字体。取不到时表现是「界面出来了，但字全是空白/方块」。

所以 `assets/fonts/` 里内置了两支字体，`ThemeData` 里指定
`fontFamily: AppLatin` + `fontFamilyFallback: ['AppCJK']`：

| 文件 | 负责 | 来源/许可 |
|------|------|-----------|
| `LiberationSans-Regular.ttf` (136KB) | 拉丁字母、数字、¥ % × 等符号 | Liberation Fonts，SIL OFL 1.1 |
| `DroidSansFallbackFull.ttf` (3.9MB) | 中文（含 ￥ 与 GB 常用汉字） | Droid Sans Fallback，Apache-2.0 |

注意 Droid Sans Fallback **不含拉丁字母和数字**，两支字体必须同时保留，缺一个就会出现方块字。

### Docker 构建很慢怎么办

`docker compose up -d --build` 慢的根因不是构建本身，而是基础镜像 `nginx:alpine` 拉不下来：
本机直连 Docker Hub 只有 ~15KB/s，20MB 那一层会一直超时重试（日志里是
`short read ... unexpected EOF` / `fetch oauth token: EOF`）。

Dockerfile 里已把基础镜像改成华为云 SWR 的镜像源，拉取约 4 秒：

```
ARG NGINX_IMAGE=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/nginx:alpine
```

需要回到官方源时：

```
docker compose build --build-arg NGINX_IMAGE=nginx:alpine
```

实测：镜像就绪后全量构建 `--no-cache` 约 0.6 秒（41MB 的 build/web 走本地 overlay2 去重）。
注意上海外镜像源（docker.1ms.run / hub.rat.dev / docker.m.daocloud.io 等）在本机同样只有
10~80KB/s，不能解决这个问题。

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

## 收费明细列的识别

导入收费明细时不再写死列号：程序在前 30 行里找「药品/项目名称」（或 药品名称 / 项目名称 / 药材名称 …）和
「实收」（或 实收金额 / 金额 …）两列表头，按表头定位列。医院导出多一列（例如 2026-11 起多出的「商品标签」）
或调换列顺序都不影响；只有找不到表头时才退回旧格式的固定列位置。
识别结果和跳过行数打印在解析日志里；一条记录都没解析出来时，界面直接红字报错，不会再显示一张全是 0 的结果页。

核对/调试用的脚本（不参与构建）：

```
dart run tool/debug_xlsx.dart 2026-11-06_2026-11-08.xlsx 6   # 打印表头和前几行
dart run tool/dump_xlsx.dart 2026-11-06_2026-11-08.xlsx /tmp/sales.tsv  # 导出成 TSV 方便用别的工具核对
```

`test/sales_xlsx_regression_test.dart` 用仓库里的真实导出文件做回归：表格不变时
实收合计应为 11707.71、税额 975.43（植物类 11438.71、动物类 250.88、矿物类 18.12）。