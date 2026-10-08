import 'package:flutter/material.dart';

/// 写字台 (xiezitai) 移动客户端。
///
/// 当前阶段的目标只有一个：先打通「提交 → GitHub Actions macOS runner 构建 →
/// 产出 iOS 安装包」这条 CI/CD 链路，所以这里先放一个最小可编译的壳子。
/// 登录 / 评论 / 阅读计数 / 看文章 / 发评论 / 发布文章等功能在此基础上逐步补齐。
void main() {
  runApp(const XiezitaiApp());
}

/// 编译期配置。
///
/// 构建时可以覆盖，不必改代码：
///   flutter build ios --dart-define=XIEZITAI_SITE_URL=https://xiezitai.cn
class AppConfig {
  const AppConfig._();

  /// 后端站点地址（写字台服务端）。
  static const String siteUrl = String.fromEnvironment(
    'XIEZITAI_SITE_URL',
    defaultValue: 'https://xiezitai.cn',
  );
}

class XiezitaiApp extends StatelessWidget {
  const XiezitaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '写字台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6FEB)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('写字台'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.edit_note,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('写字台', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '移动客户端 · 构建链路验证版',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SelectableText(
                '站点：${AppConfig.siteUrl}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
