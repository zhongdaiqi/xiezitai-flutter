import 'package:flutter/material.dart';

import 'api.dart';
import 'legal.dart';
import 'safety.dart';

/// 登录页。成功后 pop(true)，调用方据此刷新。
/// 支持 TOTP：服务端返回 NEED_TOTP 时追加动态码输入。
///
/// App Store 准则 1.2：使用条款必须在**注册或登录之前**呈现，
/// 所以这里加了「已阅读并同意服务条款」勾选 —— 未勾选无法登录，点击「服务条款」可查看全文。
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
  bool _agreedToTerms = false;

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
    // 准则 1.2：使用条款必须在登录前被确认
    if (!_agreedToTerms) {
      setState(() => _error = '请先阅读并同意《服务条款与社区规范》');
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
          const SizedBox(height: 16),
          // EULA 前置确认（准则 1.2）：未勾选无法登录，点击蓝色文字可查看全文
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: 24, height: 24,
              child: Checkbox(
                value: _agreedToTerms,
                onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Wrap(children: [
                const Text('我已阅读并同意'),
                InkWell(
                  onTap: () => showTermsDialog(context),
                  child: const Text('《服务条款与社区规范》',
                      style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Text('举报受理：$kAbuseContactEmail（24 小时内处理）',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (_busy || !_agreedToTerms) ? null : _submit,
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
