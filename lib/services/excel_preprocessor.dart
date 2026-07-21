import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Excel预处理服务 - 纯Dart实现，修复Flutter excel包的解析兼容性问题
///
/// 问题：某些Excel文件在styles.xml中将内置numFmtId（41-44，会计格式）
/// 错误地放在<numFmts>自定义段中，导致excel包报错：
/// "custom numFmtId starts at 164 but found a value of 41"
///
/// 解决方案：直接从xlsx的zip中修复styles.xml，移除非法的自定义格式定义
class ExcelPreprocessor {
  /// 预处理Excel文件字节数据，修复格式问题
  /// 返回修复后的Excel字节数据
  static Uint8List fixExcelBytes(Uint8List originalBytes) {
    // 解压xlsx（zip格式）
    final archive = ZipDecoder().decodeBytes(originalBytes);

    // 修复 styles.xml
    final stylesEntry = archive.firstWhere((e) => e.name == 'xl/styles.xml');
    String stylesXml = String.fromCharCodes(stylesEntry.content);

    // 修复策略：
    // 1. 移除 <numFmts> 中 numFmtId 为 41-44 的条目（这些是内置会计格式）
    // 2. 将 cellStyleXfs 中引用这些ID的 numFmtId 改为 0
    stylesXml = _fixNumFmts(stylesXml);

    // 创建新的 ArchiveFile 替换原来的
    final fixedStylesContent = Uint8List.fromList(stylesXml.codeUnits);
    final fixedStylesFile = ArchiveFile(
      stylesEntry.name,
      fixedStylesContent.length,
      fixedStylesContent,
    );
    archive.addFile(fixedStylesFile); // addFile 会替换同名文件

    // 修复 workbook.xml 中的中文sheet名
    final workbookEntry = archive.firstWhere((e) => e.name == 'xl/workbook.xml');
    String workbookXml = String.fromCharCodes(workbookEntry.content);
    workbookXml = _fixSheetName(workbookXml);
    
    final fixedWorkbookContent = Uint8List.fromList(workbookXml.codeUnits);
    final fixedWorkbookFile = ArchiveFile(
      workbookEntry.name,
      fixedWorkbookContent.length,
      fixedWorkbookContent,
    );
    archive.addFile(fixedWorkbookFile); // addFile 会替换同名文件

    // 重新打包为zip
    final fixedBytes = ZipEncoder().encode(archive);
    if (fixedBytes == null) {
      throw Exception('重新打包xlsx失败');
    }

    return Uint8List.fromList(fixedBytes);
  }

  /// 修复 styles.xml 中的 numFmts 段
  static String _fixNumFmts(String xml) {
    // 移除 <numFmts>...</numFmts> 段中 numFmtId 为 41-44 的条目
    // 这些是内置会计格式，不应该出现在自定义段中
    // 匹配 <numFmt numFmtId="41" .../> 等
    final numFmtPattern = RegExp(
      r'<numFmt\s+numFmtId="(4[1-4])"[^/]*/>',
    );

    // 先移除这些条目
    String fixed = xml.replaceAll(numFmtPattern, '');

    // 更新 numFmts 的 count 属性
    final numFmtsPattern = RegExp(r'<numFmts\s+count="(\d+)"');
    final match = numFmtsPattern.firstMatch(fixed);
    if (match != null) {
      final oldCount = int.parse(match.group(1)!);
      // 计算被移除的条目数量
      final removedCount = numFmtPattern.allMatches(xml).length;
      final newCount = oldCount - removedCount;
      if (newCount <= 0) {
        // 如果没有自定义格式了，移除整个 <numFmts> 段
        fixed = fixed.replaceAll(
          RegExp(r'<numFmts[^>]*>\s*</numFmts>'),
          '',
        );
      } else {
        fixed = fixed.replaceFirst(numFmtsPattern, '<numFmts count="$newCount"');
      }
    }

    // 将 cellStyleXfs 中引用 41-44 的 numFmtId 改为 0
    // 匹配 <xf numFmtId="41" 或 <xf numFmtId="42" 等
    for (int id = 41; id <= 44; id++) {
      fixed = fixed.replaceAll(
        'numFmtId="$id"',
        'numFmtId="0"',
      );
    }

    return fixed;
  }

  /// 修复 workbook.xml 中的中文sheet名
  static String _fixSheetName(String xml) {
    // 将 sheet name="明细" 改为 sheet name="Sheet1"
    // 匹配 <sheet name="..." 并替换名称
    return xml.replaceAllMapped(
      RegExp(r'(<sheet\s+name=")[^"]*(")'),
      (match) => '${match.group(1)}Sheet1${match.group(2)}',
    );
  }

  /// 解析修复后的Excel文件
  static Excel parseExcel(Uint8List originalBytes) {
    final fixedBytes = fixExcelBytes(originalBytes);
    return Excel.decodeBytes(fixedBytes);
  }
}
