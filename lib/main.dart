import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/herb_dictionary.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await HerbDictionary.instance.load();
  } catch (e) {
    // 字典加载失败不阻断启动，界面会把所有药材显示为未识别
    debugPrint('[main] 药材字典加载失败: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '计算器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        // 用内置字体，避免 CanvasKit 去 fonts.gstatic.com 拉 Roboto / Noto 兜底字体
        fontFamily: 'AppLatin',
        fontFamilyFallback: const ['AppCJK'],
      ),
      home: const HomeScreen(),
    );
  }
}