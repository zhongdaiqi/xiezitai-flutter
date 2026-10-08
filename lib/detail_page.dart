import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'api.dart';
import 'login_page.dart';

/// 文章详情：Markdown 正文 + 评论列表 + 发评论。
///
/// 阅读计数：打开本页时调用的 `getArticle` 在服务端累加 viewCount，
/// 所以手机端读文章天然计入统计，无需额外上报。
class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({super.key, required this.client, required this.slug});

  final ApiClient client;
  final String slug;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  Article? _article;
  List<CommentNode> _comments = [];
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
      final a = await widget.client.getArticle(widget.slug);
      List<CommentNode> comments = [];
      try {
        comments = await widget.client.listComments(widget.slug);
      } catch (_) {/* 评论挂了不影响正文 */}
      if (mounted) setState(() { _article = a; _comments = comments; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _writeComment() async {
    final controller = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            maxLength: 2000,
            decoration: const InputDecoration(
                hintText: '友善评论，理性发言（需管理员审核后展示）',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('提交评论'))),
        ]),
      ),
    );
    if (ok != true) return;
    final content = controller.text.trim();
    if (content.isEmpty) return;
    try {
      final msg = await widget.client.postComment(widget.slug, content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) {
        final login = e.statusCode == 401;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(login ? '请先登录后再评论' : e.message),
            action: login
                ? SnackBarAction(label: '去登录', onPressed: () async {
                    final r = await Navigator.push<bool>(context,
                        MaterialPageRoute(builder: (_) => LoginPage(client: widget.client)));
                    if (r == true) _load();
                  })
                : null));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文章')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                ]))
              : Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        Text(_article!.title,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Row(children: [
                          if (_article!.author != null) Text('作者：${_article!.author}  '),
                          Icon(Icons.visibility, size: 14, color: Colors.grey),
                          Text(' ${_article!.viewCount}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                        if (!_article!.isPublished) ...[
                          const SizedBox(height: 8),
                          Chip(
                            avatar: Icon(_article!.isRejected ? Icons.block : Icons.hourglass_top,
                                size: 16),
                            label: Text(_article!.isRejected
                                ? '已驳回：${_article!.reviewNote ?? ''}'
                                : '该文章尚未通过审核，仅你自己可见'),
                            backgroundColor: _article!.isRejected
                                ? Colors.red.shade50
                                : Colors.amber.shade50,
                          ),
                        ],
                        if (_article!.tagList.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, children: _article!.tagList
                              .map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact))
                              .toList()),
                        ],
                        const Divider(height: 24),
                        MarkdownBlock(data: _article!.content),
                        const Divider(height: 32),
                        Text('评论 (${_comments.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (_comments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('还没有评论，来抢沙发', style: TextStyle(color: Colors.grey)),
                          )
                        else
                          ..._comments.map(_commentTile),
                      ],
                    ),
                    // 底部常驻「写评论」栏
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: FilledButton.icon(
                          onPressed: _writeComment,
                          icon: const Icon(Icons.comment_outlined),
                          label: const Text('写评论'),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _commentTile(CommentNode c) {
    return Column(children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: CircleAvatar(child: Text(c.authorName.isEmpty ? '?' : c.authorName[0])),
        title: Text(c.authorName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.replyToName != null && c.replyToName!.isNotEmpty)
            Text('回复 @${c.replyToName}',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          Text(c.content),
        ]),
      ),
      ...c.replies.map((r) => Padding(
            padding: const EdgeInsets.only(left: 36),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(radius: 12,
                  child: Text(r.authorName.isEmpty ? '?' : r.authorName[0],
                      style: const TextStyle(fontSize: 11))),
              title: Text(r.authorName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              subtitle: Text(r.content, style: const TextStyle(fontSize: 13)),
            ),
          )),
      const Divider(height: 1),
    ]);
  }
}
