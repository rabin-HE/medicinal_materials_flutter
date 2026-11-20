import 'dart:typed_data';

import 'file_saver_stub.dart'
    if (dart.library.io) 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// 把字节保存成本地文件。
///
/// web 端触发浏览器下载；桌面端弹出保存对话框。
/// 返回给用户看的结果提示（下载已开始 / 已保存到某路径 / 已取消）。
Future<String?> saveBytesToFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) {
  return impl.saveBytesToFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
  );
}