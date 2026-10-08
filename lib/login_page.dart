import 'package:flutter/material.dart';

import 'api.dart';

/// 登录页。成功后 pop(true)，调用方据此刷新。
/// 支持 TOTP：服务端返回 NEED_TOTP 时追加动态码输入。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.client});

  final ApiClient client;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _totp = TextEditingController();
  bool _needTotp = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _username.text.trim();
    final pass = _password.text;
    if (name.isEmpty || pass.isEmpty) {
      setState(() => _error = '请输入用户名和密码');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.client.login(name, pass,
          totpCode: _needTotp ? _totp.text.trim() : null);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (e.statusCode == 401 && e.message.contains('NEED_TOTP')) {
        setState(() { _needTotp = true; _error = '该账号已开启两步验证，请输入动态码'; });
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录写字台')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline)),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline)),
            onSubmitted: (_) => _submit(),
          ),
          if (_needTotp) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _totp,
              decoration: const InputDecoration(labelText: '两步验证动态码',
                  prefixIcon: Icon(Icons.shield_outlined)),
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('登录'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
