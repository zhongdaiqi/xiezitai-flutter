/// 写字台 API 客户端：封装后端 HTTP 接口与登录态。
///
/// 后端接口（与 Spring 服务端一一对应）：
/// - POST /api/auth/login           登录，返回 {token, username, role}
/// - GET  /api/articles             公开文章列表（分页，仅已发布）
/// - GET  /api/articles/{slug}      文章详情（服务端在此计数 —— 手机端取详情即计入阅读数）
/// - GET  /api/articles/{slug}/comments      评论树（公开）
/// - POST /api/articles/{slug}/comments      发评论（需登录）
/// - POST /api/comments/{id}/report          举报评论（需登录，兼容入口，内部走统一工单）
/// - DEL  /api/comments/{id}                 删除评论（作者本人或管理员）
/// - POST /api/reports                       统一举报：文章 / 评论 / 用户（App Store 1.2 UGC）
/// - POST /api/blocks                        屏蔽用户（内容立即从信息流消失，并通知开发者）
/// - DEL  /api/blocks/{username}             解除屏蔽
/// - GET  /api/blocks                        我的屏蔽名单
/// - DEL  /api/auth/me                       注销账号（需密码确认，连带删除文章与评论）
/// - GET  /api/my/articles          我自己的文章（含待审/驳回）
/// - POST /api/my/articles          投稿：管理员直接公开；普通用户进入待审核
/// - PUT  /api/my/articles/{id}     改自己的文章（普通用户改完回炉重审）
/// - DEL  /api/my/articles/{id}     删自己的文章
/// - POST /api/admin/articles/{id}/review    审核投稿 {action: approve|reject, note?}
/// - GET  /api/admin/articles?status=PENDING  待审列表（管理员）
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 文章（后端 Article 实体的移动端视图）
class Article {
  final int id;
  final String slug;
  final String title;
  final String content;
  final String? summary;
  final String? cover;
  final String status; // DRAFT / PENDING / PUBLISHED / REJECTED
  final String? author;
  final String? tags;
  final String? reviewNote;
  final int viewCount;
  final String? publishedAt;
  final String? updatedAt;

  Article({
    required this.id,
    required this.slug,
    required this.title,
    this.content = '',
    this.summary,
    this.cover,
    required this.status,
    this.author,
    this.tags,
    this.reviewNote,
    this.viewCount = 0,
    this.publishedAt,
    this.updatedAt,
  });

  factory Article.fromJson(Map<String, dynamic> j) => Article(
        id: (j['id'] as num).toInt(),
        slug: j['slug'] as String? ?? '',
        title: j['title'] as String? ?? '',
        content: j['content'] as String? ?? '',
        summary: j['summary'] as String?,
        cover: j['cover'] as String?,
        status: j['status'] as String? ?? 'DRAFT',
        author: j['author'] as String?,
        tags: j['tags'] as String?,
        reviewNote: j['reviewNote'] as String?,
        viewCount: (j['viewCount'] as num?)?.toInt() ?? 0,
        publishedAt: j['publishedAt'] as String?,
        updatedAt: j['updatedAt'] as String?,
      );

  bool get isPublished => status == 'PUBLISHED';
  bool get isPending => status == 'PENDING';
  bool get isRejected => status == 'REJECTED';

  /// 状态中文标签
  String get statusLabel => switch (status) {
        'PUBLISHED' => '已发布',
        'PENDING' => '待审核',
        'REJECTED' => '已驳回',
        _ => '草稿',
      };

  List<String> get tagList =>
      (tags ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

/// 评论节点（后端 CommentNode，两级树）
class CommentNode {
  final int id;
  final String authorName;
  final String? replyToName;
  final String content;
  final String createdAt;
  final List<CommentNode> replies;

  CommentNode({
    required this.id,
    required this.authorName,
    this.replyToName,
    required this.content,
    required this.createdAt,
    this.replies = const [],
  });

  factory CommentNode.fromJson(Map<String, dynamic> j) => CommentNode(
        id: (j['id'] as num).toInt(),
        authorName: j['authorName'] as String? ?? '匿名',
        replyToName: j['replyToName'] as String?,
        content: j['content'] as String? ?? '',
        createdAt: j['createdAt'] as String? ?? '',
        replies: ((j['replies'] as List?) ?? [])
            .map((e) => CommentNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 登录后的用户信息
class CurrentUser {
  final String username;
  final String role;
  CurrentUser(this.username, this.role);
  bool get isAdmin => role == 'ADMIN';
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  String baseUrl;
  String? token;

  ApiClient({required this.baseUrl, this.token});

  static const String defaultBaseUrl = 'https://xiezitai.cn';

  /// 从本地持久化恢复（服务器地址 + 登录态）
  static Future<ApiClient> load() async {
    final sp = await SharedPreferences.getInstance();
    final c = ApiClient(
      baseUrl: sp.getString('xz_base_url') ?? defaultBaseUrl,
      token: sp.getString('xz_token'),
    );
    return c;
  }

  Future<void> persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('xz_base_url', baseUrl);
    if (token == null) {
      await sp.remove('xz_token');
    } else {
      await sp.setString('xz_token', token!);
    }
  }

  void updateBaseUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) u = defaultBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    baseUrl = u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json; charset=utf-8',
        if (auth && token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? qp]) => Uri.parse('$baseUrl$path')
      .replace(queryParameters: qp == null ? null : {...Uri.parse('$baseUrl$path').queryParameters, ...qp});

  /// 统一请求：非 2xx 抛 ApiException（带服务端 error 文案）
  Future<dynamic> _send(String method, String path, {Object? body, Map<String, String>? qp}) async {
    final res = await http.Client()
        .send(http.Request(method, _uri(path, qp))
          ..headers.addAll(_headers())
          ..body = body == null ? '' : jsonEncode(body));
    final bytes = await res.stream.toBytes();
    final text = utf8.decode(bytes);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = text;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = data is Map ? (data['error'] ?? data['message'] ?? '请求失败(${res.statusCode})') : '请求失败(${res.statusCode})';
      throw ApiException(res.statusCode, msg.toString());
    }
    return data;
  }

  /* ---------- 认证 ---------- */

  /// 登录成功后持久化 token。
  /// 开了 TOTP 的账号：不带 totpCode 时服务端回 401 NEED_TOTP，前端据此追加动态码输入。
  Future<CurrentUser> login(String username, String password, {String? totpCode}) async {
    final data = await _send('POST', '/api/auth/login', body: {
      'username': username,
      'password': password,
      if (totpCode != null && totpCode.isNotEmpty) 'totpCode': totpCode,
    }) as Map<String, dynamic>;
    token = data['token'] as String?;
    await persist();
    return CurrentUser(data['username'] as String? ?? username, data['role'] as String? ?? 'USER');
  }

  /// 用现有 token 换用户信息；token 失效返回 null（并清掉本地登录态）
  Future<CurrentUser?> me() async {
    if (token == null) return null;
    try {
      final data = await _send('GET', '/api/auth/me') as Map<String, dynamic>;
      return CurrentUser(data['username'] as String? ?? '', data['role'] as String? ?? 'USER');
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        token = null;
        await persist();
        return null;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    token = null;
    await persist();
  }

  /* ---------- 文章（公开） ---------- */

  Future<List<Article>> listArticles({int page = 0, int size = 20}) async {
    final data = await _send('GET', '/api/articles', qp: {'page': '$page', 'size': '$size'}) as Map<String, dynamic>;
    return ((data['content'] as List?) ?? [])
        .map((e) => Article.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 详情。服务端在这条接口上累加阅读计数（预览自己的未公开文章除外）。
  Future<Article> getArticle(String slug) async {
    final data = await _send('GET', '/api/articles/$slug') as Map<String, dynamic>;
    return Article.fromJson(data);
  }

  /* ---------- 评论 ---------- */

  Future<List<CommentNode>> listComments(String slug) async {
    final data = await _send('GET', '/api/articles/$slug/comments');
    return ((data as List?) ?? [])
        .map((e) => CommentNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> postComment(String slug, String content, {int? parentId}) async {
    final data = await _send('POST', '/api/articles/$slug/comments',
        body: {'content': content, if (parentId != null) 'parentId': parentId});
    return (data as Map<String, dynamic>)['message'] as String? ?? '已提交';
  }

  /// 举报评论（App Store 1.2 UGC 要求具备举报机制）
  /// 走统一工单接口，带理由分类，服务端 24 小时内处置。
  Future<void> reportComment(int commentId, {String reason = 'OTHER', String? detail}) =>
      report(type: 'COMMENT', targetId: commentId, reason: reason, detail: detail);

  /* ---------- 内容安全：举报 / 屏蔽（App Store 准则 1.2） ---------- */

  /// 统一举报入口。
  /// [type] ARTICLE / COMMENT / USER；[reason] SPAM / ABUSE / PORN / VIOLENCE / ILLEGAL / OTHER
  Future<void> report({
    required String type,
    required int targetId,
    String reason = 'OTHER',
    String? detail,
  }) =>
      _send('POST', '/api/reports', body: {
        'type': type,
        'targetId': targetId,
        'reason': reason,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      });

  /// 举报文章（文章也是 UGC，审查员会看能不能举报到）
  Future<void> reportArticle(int articleId, {String reason = 'OTHER', String? detail}) =>
      report(type: 'ARTICLE', targetId: articleId, reason: reason, detail: detail);

  /// 屏蔽用户：屏蔽后其文章与评论立即从我的信息流消失，服务端同时通知管理员。
  /// 返回服务端文案（含「累计被 N 人屏蔽」等信息）。
  Future<String> blockUser(String username) async {
    final data = await _send('POST', '/api/blocks', body: {'username': username})
        as Map<String, dynamic>;
    return data['message'] as String? ?? '已屏蔽 $username';
  }

  /// 解除屏蔽
  Future<void> unblockUser(String username) =>
      _send('DELETE', '/api/blocks/${Uri.encodeComponent(username)}');

  /// 我的屏蔽名单（首页过滤用）
  Future<List<String>> myBlocks() async {
    try {
      final data = await _send('GET', '/api/blocks') as Map<String, dynamic>;
      return ((data['blocks'] as List?) ?? [])
          .map((e) => (e as Map<String, dynamic>)['username'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } on ApiException catch (e) {
      if (e.statusCode == 401) return <String>[]; // 未登录没有屏蔽名单
      rethrow;
    }
  }

  /// 删除评论（作者本人或管理员；服务端会连带删除其下回复）
  Future<void> deleteComment(int commentId) => _send('DELETE', '/api/comments/$commentId');

  /// 注销账号：需密码二次确认；服务端在一个事务里删除本人文章与评论后删账号
  Future<void> deleteAccount(String password) =>
      _send('DELETE', '/api/auth/me', body: {'password': password});

  /* ---------- 我的文章（投稿） ---------- */

  Future<List<Article>> myArticles({int page = 0, int size = 50}) async {
    final data = await _send('GET', '/api/my/articles', qp: {'page': '$page', 'size': '$size'}) as Map<String, dynamic>;
    return ((data['content'] as List?) ?? [])
        .map((e) => Article.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 投稿/保存。返回保存后的文章。
  Future<Article> saveMyArticle({int? id, required String title, required String content,
      String? summary, String? tags, String? slug}) async {
    final body = {
      'title': title,
      'content': content,
      if (summary != null && summary.isNotEmpty) 'summary': summary,
      if (tags != null && tags.isNotEmpty) 'tags': tags,
      if (slug != null && slug.isNotEmpty) 'slug': slug,
    };
    final data = await _send(id == null ? 'POST' : 'PUT', id == null ? '/api/my/articles' : '/api/my/articles/$id',
        body: body) as Map<String, dynamic>;
    return Article.fromJson(data);
  }

  Future<void> deleteMyArticle(int id) => _send('DELETE', '/api/my/articles/$id');

  /* ---------- 管理员审核 ---------- */

  Future<List<Article>> pendingArticles() async {
    final data = await _send('GET', '/api/admin/articles', qp: {'status': 'PENDING', 'size': '100'})
        as Map<String, dynamic>;
    return ((data['content'] as List?) ?? [])
        .map((e) => Article.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> review(int articleId, {required bool approve, String? note}) =>
      _send('POST', '/api/admin/articles/$articleId/review',
          body: {'action': approve ? 'approve' : 'reject', if (note != null) 'note': note});
}
