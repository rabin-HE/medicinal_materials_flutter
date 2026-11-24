#!/usr/bin/env bash
# 部署前自检：确认 Flutter Web 产物不依赖外网 CDN。
#
# 背景：flutter build web 默认从 https://www.gstatic.com/flutter-canvaskit/<rev>/canvaskit.js
# 拉 CanvasKit。墙内/无代理的浏览器取不到这个文件时，引擎根本没初始化，
# 页面就是纯白一片，控制台只有一条 unhandled promise rejection，普通人看不出原因。
# 构建时必须加 --no-web-resources-cdn，让 CanvasKit 走产物自带的 build/web/canvaskit/。
#
# 用法：tool/check_web_build.sh [build/web]
set -euo pipefail

dist="${1:-build/web}"

if [ ! -f "$dist/flutter_bootstrap.js" ]; then
  echo "FAIL: 找不到 $dist/flutter_bootstrap.js，先跑 flutter build web" >&2
  exit 1
fi

if [ ! -f "$dist/canvaskit/canvaskit.js" ] || [ ! -f "$dist/canvaskit/canvaskit.wasm" ]; then
  echo "FAIL: $dist/canvaskit/ 里没有 canvaskit.js / canvaskit.wasm，浏览器会白屏" >&2
  exit 1
fi

if ! grep -q '"useLocalCanvasKit":true' "$dist/flutter_bootstrap.js"; then
  echo "FAIL: 构建产物会从 www.gstatic.com 拉 CanvasKit，墙内/无代理浏览器打开就是白屏。" >&2
  echo "      重新构建：flutter build web --release --no-web-resources-cdn" >&2
  exit 1
fi

echo "OK: CanvasKit 走本地 $dist/canvaskit，不依赖外网 CDN"