import 'package:flutter/material.dart';

import 'api.dart';

/// 设置：服务器地址。登录态显示与退出也在这一页。
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
