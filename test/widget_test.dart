import 'package:flutter_test/flutter_test.dart';
import 'package:xiezitai_flutter/main.dart';

void main() {
  testWidgets('首页渲染出应用标题与站点地址', (WidgetTester tester) async {
    await tester.pumpWidget(const XiezitaiApp());

    // AppBar 标题 + 正文标题，两处都应出现「写字台」
    expect(find.text('写字台'), findsNWidgets(2));
    expect(find.textContaining('移动客户端'), findsOneWidget);
    expect(find.textContaining(AppConfig.siteUrl), findsOneWidget);
  });
}
