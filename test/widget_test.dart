import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('首页显示导入提示', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('税费计算器'), findsOneWidget);
    expect(find.text('请导入收费明细 Excel 文件'), findsOneWidget);
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
  });
}