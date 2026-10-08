import 'package:flutter/material.dart';

import 'api.dart';

/// 写文章 / 编辑自己的文章。
///
/// 保存规则由服务端决定：管理员保存直接公开；
/// 普通用户保存一律进入待审核（改自己已发布的文章也会回炉重审）。
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.client, this.article});

  final ApiClient client;
  final Article? article; // 传了就是编辑

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _summary;
  late final TextEditingController _tags;
  bool _busy = false;

  bool get _editing => widget.article != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.article?.title ?? '');
    _content = TextEditingController(text: widget.article?.content ?? '');
    _summary = TextEditingController(text: widget.article?.summary ?? '');
    _tags = TextEditingController(text: widget.article?.tags ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _summary.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final content = _content.text;
    if (title.isEmpty || content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标题和正文都不能为空')));
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await widget.client.saveMyArticle(
        id: _editing ? widget.article!.id : null,
        title: title,
        content: content,
        summary: _summary.text.trim(),
        tags: _tags.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved.isPublished
                ? '已发布'
                : saved.isRejected
                    ? '已保存（此前被驳回，重新进入审核）'
                    : '已提交，等待管理员审核通过后公开')));
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? '编辑文章' : '写文章'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(height: 16, width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '标题', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _summary,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: '摘要（可空）', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
                labelText: '标签（逗号分隔，最多 10 个）',
                hintText: 'Java, 随笔',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: '正文（支持 Markdown）',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text(
            widget.client.token == null
                ? ''
                : '普通用户提交后进入审核，管理员提交后直接公开',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
