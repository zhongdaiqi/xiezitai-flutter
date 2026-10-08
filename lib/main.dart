import 'package:flutter/material.dart';

import 'api.dart';
import 'detail_page.dart';
import 'mine_page.dart';
import 'settings_page.dart';

void main() {
  runApp(const XiezitaiApp());
}

class XiezitaiApp extends StatelessWidget {
  const XiezitaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E293B);
    return MaterialApp(
      title: '写字台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const RootPage(),
    );
  }
}

/// 根页面：恢复登录态后进入首页（底部导航：首页 / 我的 / 设置）
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  late Future<ApiClient> _client;

  @override
  void initState() {
    super.initState();
    _client = ApiClient.load();
  }

  /// 子页面改了登录态（登录/登出）后回调：整个根重建
  void _refresh() => setState(() => _client = ApiClient.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiClient>(
      future: _client,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return HomeShell(client: snap.data!, onAuthChanged: _refresh);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.client, required this.onAuthChanged});

  final ApiClient client;
  final VoidCallback onAuthChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  CurrentUser? _user;
  bool _checkingUser = true;
  int _homeEpoch = 0; // 切回首页 tab 时强制列表刷新

  @override
  void initState() {
    super.initState();
    _restoreUser();
  }

  Future<void> _restoreUser() async {
    try {
      final u = await widget.client.me();
      if (mounted) setState(() { _user = u; _checkingUser = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingUser = false);
    }
  }

  Future<void> _refreshUser() async {
    final u = await widget.client.me().catchError((_) => null as CurrentUser?);
    if (mounted) setState(() { _user = u; _homeEpoch++; });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ArticleListPage(key: ValueKey('home-$_homeEpoch'), client: widget.client),
      _checkingUser
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : MinePage(client: widget.client, user: _user, onAuthChanged: widget.onAuthChanged),
      SettingsPage(client: widget.client, onSaved: () {
        widget.onAuthChanged();
      }),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() {
            _tab = i;
            if (i == 0) _homeEpoch++; // 从「我的」回到首页时刷新（可能有刚过审的文章）
            if (i == 1) _refreshUser();
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '首页'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

/* ==================== 首页：公开文章列表 ==================== */

class ArticleListPage extends StatefulWidget {
  const ArticleListPage({super.key, required this.client});

  final ApiClient client;

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  List<Article> _articles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await widget.client.listArticles();
      if (mounted) setState(() { _articles = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('写字台'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: '刷新'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _articles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = _articles[i];
                      return ListTile(
                        title: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            if (a.summary != null && a.summary!.isNotEmpty)
                              Expanded(
                                child: Text(a.summary!, maxLines: 1, overflow: TextOverflow.ellipsis),
                              )
                            else
                              const Spacer(),
                            Icon(Icons.visibility, size: 14, color: Colors.grey),
                            const SizedBox(width: 3),
                            Text('${a.viewCount}', style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ArticleDetailPage(client: widget.client, slug: a.slug))),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ]),
      ),
    );
  }
}
