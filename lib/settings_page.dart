import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'legal.dart';
import 'safety.dart';

/// 设置：服务器地址。登录态显示、隐私政策、服务条款、屏蔽名单与账号注销都在这一页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.client, required this.onSaved});

  final ApiClient client;
  final VoidCallback onSaved;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.client.baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    widget.client.updateBaseUrl(_url.text);
    await widget.client.persist();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服务器已设为 ${widget.client.baseUrl}')));
      widget.onSaved();
    }
  }

  /// 打开隐私政策（系统浏览器，App Store 要求可访问的隐私政策 URL）
  Future<void> _openPrivacy() async {
    final uri = Uri.parse('${widget.client.baseUrl}/privacy.html');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法打开 $uri')));
      }
    }
  }

  /// 注销账号：密码二次确认 → 服务端删除文章/评论/账号 → 清本地登录态。
  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('注销将删除你的账号、全部文章与评论，且不可恢复。', style: TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: '输入登录密码确认', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.client.deleteAccount(controller.text);
      await widget.client.logout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('账号已注销')));
        widget.onSaved();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 屏蔽名单：展示与解除屏蔽（准则 1.2 要求用户能管理屏蔽关系）
  Future<void> _openBlockList() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => BlockListPage(client: widget.client)));
    if (mounted) widget.onSaved(); // 解除屏蔽后回首页刷新列表
  }

  /// 给举报邮箱发信（mailto），App Store 要求 App 内可见的举报受理渠道
  Future<void> _mailAbuse() async {
    final uri = Uri(
      scheme: 'mailto',
      path: kAbuseContactEmail,
      query: 'subject=${Uri.encodeComponent('写字台内容举报')}',
    );
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法打开邮件客户端，请手动发送至 $kAbuseContactEmail')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = widget.client.token != null;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('服务器', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '写字台地址',
              hintText: 'https://xiezitai.cn',
              border: OutlineInputBorder(),
              helperText: '不带末尾斜杠；自部署用户填自己的域名',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私政策'),
            subtitle: const Text('数据收集与使用说明', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openPrivacy,
          ),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('服务条款与社区规范'),
            subtitle: const Text('EULA · 登录前需确认', style: TextStyle(fontSize: 12)),
            onTap: () => showTermsDialog(context),
          ),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('屏蔽名单'),
            subtitle: const Text('管理你屏蔽的用户', style: TextStyle(fontSize: 12)),
            enabled: loggedIn,
            onTap: _openBlockList,
          ),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('举报与申诉邮箱'),
            subtitle: Text('$kAbuseContactEmail · 24 小时内处理',
                style: const TextStyle(fontSize: 12)),
            onTap: _mailAbuse,
          ),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
            title: const Text('删除账号', style: TextStyle(color: Colors.red)),
            subtitle: const Text('注销并删除全部文章与评论，不可恢复',
                style: TextStyle(fontSize: 12)),
            enabled: !_busy && widget.client.token != null,
            onTap: _deleteAccount,
          ),
          const Divider(height: 8),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('写字台 xiezitai'),
            subtitle: Text('自托管 SEO / AI 友好博客 · Flutter 客户端'),
          ),
        ],
      ),
    );
  }
}

/// 屏蔽名单：列出已屏蔽的用户，支持解除。
class BlockListPage extends StatefulWidget {
  const BlockListPage({super.key, required this.client});

  final ApiClient client;

  @override
  State<BlockListPage> createState() => _BlockListPageState();
}

class _BlockListPageState extends State<BlockListPage> {
  List<String> _blocks = [];
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
      final list = await widget.client.myBlocks();
      if (mounted) setState(() { _blocks = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _unblock(String username) async {
    try {
      await widget.client.unblockUser(username);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已解除对 $username 的屏蔽')));
      }
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('屏蔽名单')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center)))
              : _blocks.isEmpty
                  ? const Center(child: Text('你还没有屏蔽任何用户',
                      style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: _blocks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final name = _blocks[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text(name[0].toUpperCase())),
                          title: Text(name),
                          subtitle: const Text('其文章与评论对你不可见',
                              style: TextStyle(fontSize: 12)),
                          trailing: TextButton(
                            onPressed: () => _unblock(name),
                            child: const Text('解除屏蔽'),
                          ),
                        );
                      },
                    ),
    );
  }
}
