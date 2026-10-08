// 应用冒烟测试：不依赖网络 —— 首页要么在加载、要么请求失败显示重试，都不能崩溃白屏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiezitai_flutter/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('App 启动渲染「写字台」与底部导航', (tester) async {
    await tester.pumpWidget(const XiezitaiApp());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('写字台'), findsWidgets);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('首页列表加载中/失败均不崩溃（测试环境无网络）', (tester) async {
    await tester.pumpWidget(const XiezitaiApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // 请求还在进行 → 加载圈；请求失败 → 错误视图（重试按钮）。两者都算「优雅降级」。
    final loading = find.byType(CircularProgressIndicator);
    final retry = find.text('重试');
    expect(loading.evaluate().isNotEmpty || retry.evaluate().isNotEmpty, isTrue);
  });
}
