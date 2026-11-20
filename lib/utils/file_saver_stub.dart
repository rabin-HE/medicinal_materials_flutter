import 'dart:typed_data';

/// 非 web、非 io 平台（理论上不会用到）的占位实现
Future<String?> saveBytesToFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('当前平台不支持导出文件');
}