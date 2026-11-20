import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 桌面端：弹出保存对话框后写入文件
Future<String?> saveBytesToFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: fileName,
  );
  if (path == null) return '已取消';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return '已保存到 $path';
}