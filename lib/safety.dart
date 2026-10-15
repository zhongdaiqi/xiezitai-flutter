/// 内容安全相关的通用弹层：服务条款、举报、屏蔽。
///
/// 抽成独立文件是因为登录页、文章详情、评论列表、设置页都要用同一套交互，
/// 分开写迟早会出现「两处举报弹窗文案不一致」这种被审查员一眼看穿的破绽。
library;

import 'package:flutter/material.dart';

import 'legal.dart';

/// 举报结果：理由 code + 补充说明
class ReportResult {
  final String reason;
  final String detail;
  const ReportResult(this.reason, this.detail);
}

/// 展示服务条款全文（登录前点击「服务条款」时打开）。
Future<void> showTermsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('服务条款与社区规范'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Text(kTermsOfUse, style: const TextStyle(fontSize: 13, height: 1.6)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我已阅读')),
      ],
    ),
  );
}

/// 举报弹层：选理由 + 可选补充说明。用户取消返回 null。
Future<ReportResult?> showReportSheet(BuildContext context, {required String targetLabel}) {
  String reason = 'OTHER';
  final detail = TextEditingController();
  return showModalBottomSheet<ReportResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('举报：$targetLabel', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('请选择举报理由，我们会在 24 小时内处理并移除违规内容',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            // 刻意不用 RadioListTile：它的 groupValue/onChanged 在 Flutter 3.32+
            // 已被标记 deprecated（3.47.6 的 analyze 会报 info 并让 CI 退出码变 1）。
            // 自绘单选图标可同时兼容新旧 SDK，避免本地与 CI 版本不一致导致的假通过。
            ...ReportReason.all.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    reason == r.code
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: reason == r.code ? Theme.of(ctx).colorScheme.primary : null,
                  ),
                  title: Text(r.label, style: const TextStyle(fontSize: 14)),
                  onTap: () => setLocal(() => reason = r.code),
                )),
            TextField(
              controller: detail,
              maxLines: 2,
              minLines: 1,
              maxLength: 200,
              decoration: const InputDecoration(
                  hintText: '补充说明（选填）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.flag_outlined),
                label: const Text('提交举报'),
                onPressed: () => Navigator.pop(ctx, ReportResult(reason, detail.text.trim())),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ),
  );
}

/// 屏蔽用户二次确认。返回 true 表示确认屏蔽。
Future<bool> showBlockConfirm(BuildContext context, String username) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('屏蔽用户'),
      content: Text('屏蔽 $username 后：\n\n'
          '• 该用户的文章与评论将立即从你的信息流中消失\n'
          '• 该行为会通知平台管理员，便于我们发现反复骚扰他人的账号\n'
          '• 对方不会收到任何通知\n\n'
          '可在「设置 → 屏蔽名单」中解除屏蔽。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('屏蔽'),
        ),
      ],
    ),
  );
  return ok == true;
}
