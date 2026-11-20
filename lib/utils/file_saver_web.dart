import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// web 端：用 Blob + 隐藏链接触发浏览器下载
Future<String?> saveBytesToFile({
  required String fileName,
  required Uint8List bytes,
  String mimeType = 'application/octet-stream',
}) async {
  final blob = web.Blob(
    [_toBlobPart(bytes)].toJS,
    web.BlobPropertyBag(type: mimeType, endings: 'transparent'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return '已开始下载 $fileName';
}

JSUint8Array _toBlobPart(Uint8List bytes) => bytes.toJS;