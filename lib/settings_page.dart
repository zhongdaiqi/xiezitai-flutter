import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// 设置：服务器地址。登录态显示、隐私政策与账号注销也在这一页。
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

  @override
  Widget build(BuildContext context) {
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
