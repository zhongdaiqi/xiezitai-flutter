import 'package:flutter/material.dart';

import 'api.dart';
import 'detail_page.dart';
import 'editor_page.dart';
import 'login_page.dart';

/// 「我的」页：登录入口 / 我的作品（投稿管理）/ 管理员审核。
class MinePage extends StatefulWidget {
  const MinePage({super.key, required this.client, required this.user, required this.onAuthChanged});

  final ApiClient client;
  final CurrentUser? user;
  final VoidCallback onAuthChanged;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  List<Article> _mine = [];
  bool _loadingMine = true;
  String? _mineError;

  @override
  void initState() {
    super.initState();
    if (widget.user != null) _loadMine();
  }

  @override
  void didUpdateWidget(covariant MinePage old) {
    super.didUpdateWidget(old);
    if (old.user == null && widget.user != null) _loadMine();
  }

  Future<void> _loadMine() async {
    setState(() { _loadingMine = true; _mineError = null; });
    try {
      final list = await widget.client.myArticles();
      if (mounted) {
        setState(() { _mine = list; _loadingMine = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _mineError = e.toString(); _loadingMine = false; });
      }
    }
  }

  Future<void> _login() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => LoginPage(client: widget.client)));
    if (ok == true) widget.onAuthChanged();
  }

  Future<void> _logout() async {
    await widget.client.logout();
    widget.onAuthChanged();
  }

  Future<void> _write() async {
    final saved = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => EditorPage(client: widget.client)));
    if (saved == true) _loadMine();
  }

  Future<void> _open(Article a) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => ArticleDetailPage(client: widget.client, slug: a.slug)));
    _loadMine(); // 回来看状态有没有变化（比如自己又改了一版）
  }

  Future<void> _deleteMine(Article a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文章'),
        content: Text('确定删除「${a.title}」？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.client.deleteMyArticle(a.id);
      _loadMine();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          if (user != null)
            IconButton(
                tooltip: '写文章',
                icon: const Icon(Icons.edit_note),
                onPressed: _write),
          if (user != null)
            IconButton(tooltip: '退出登录', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: user == null
          ? _notLoginView()
          : ListView(
              children: [
                // 账号信息卡
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    CircleAvatar(child: Text(user.username.isEmpty ? '?' : user.username[0].toUpperCase())),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(user.isAdmin ? '管理员' : '注册用户',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ])),
                    FilledButton.tonalIcon(
                        onPressed: _write,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('写文章')),
                  ]),
                ),
                const SizedBox(height: 8),
                _sectionTitle('我的文章（${_mine.length}）'),
                if (user.isAdmin) ...[
                  PendingReviewPanel(client: widget.client, onReviewed: _loadMine),
                ],
                _mineList(),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _notLoginView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.account_circle_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('登录后可以发表文章、参与评论'),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _login,
              icon: const Icon(Icons.login),
              label: const Text('登录 / 注册需在网页端完成')),
        ]),
      );

  Widget _mineList() {
    if (_loadingMine) {
      return const Padding(
          padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_mineError != null) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(_mineError!, style: const TextStyle(color: Colors.grey)),
            TextButton(onPressed: _loadMine, child: const Text('重试')),
          ]));
    }
    if (_mine.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('还没有发表过文章，点右上角「写文章」开始',
              style: TextStyle(color: Colors.grey))));
    }
    return Column(children: [
      for (final a in _mine)
        ListTile(
          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: a.isRejected && (a.reviewNote ?? '').isNotEmpty
              ? Text('驳回原因：${a.reviewNote}', maxLines: 2, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _statusChip(a),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: '删除',
                onPressed: () => _deleteMine(a)),
          ]),
          onTap: () => _open(a),
        ),
    ]);
  }

  Widget _statusChip(Article a) => Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: switch (a.status) {
          'PUBLISHED' => Colors.green.shade50,
          'PENDING' => Colors.amber.shade50,
          'REJECTED' => Colors.red.shade50,
          _ => Colors.grey.shade100,
        },
        label: Text(a.statusLabel, style: const TextStyle(fontSize: 12)),
      );
}

/* ==================== 管理员：待审投稿 ==================== */

class PendingReviewPanel extends StatefulWidget {
  const PendingReviewPanel({super.key, required this.client, required this.onReviewed});

  final ApiClient client;
  final VoidCallback onReviewed;

  @override
  State<PendingReviewPanel> createState() => _PendingReviewPanelState();
}

class _PendingReviewPanelState extends State<PendingReviewPanel> {
  List<Article> _pending = [];
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
      final list = await widget.client.pendingArticles();
      if (mounted) setState(() { _pending = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _review(Article a, bool approve) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('驳回投稿'),
          content: TextField(controller: c, autofocus: true,
              decoration: const InputDecoration(
                  hintText: '驳回原因（作者会看到，可留空）')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('驳回')),
          ],
        ),
      );
      if (note == null) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('通过审核'),
          content: Text('公开「${a.title}」？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('通过')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.client.review(a.id, approve: approve, note: note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve ? '已通过并公开' : '已驳回')));
        _load();
        widget.onReviewed();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      leading: const Icon(Icons.rate_review_outlined),
      title: Text('待审核投稿（${_loading ? '…' : _pending.length}）'),
      children: [
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        if (!_loading && _pending.isEmpty)
          const Padding(padding: EdgeInsets.all(12),
              child: Text('没有待审核的投稿', style: TextStyle(color: Colors.grey))),
        for (final a in _pending)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('作者：${a.author ?? '?'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: '通过', icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _review(a, true)),
              IconButton(tooltip: '驳回', icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _review(a, false)),
            ]),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ArticleDetailPage(client: widget.client, slug: a.slug))),
          ),
      ],
    );
  }
}
