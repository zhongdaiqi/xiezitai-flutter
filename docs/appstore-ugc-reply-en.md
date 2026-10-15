# App Store 审核回复模板（Guideline 1.2 — User-Generated Content）

> 提交 ID：`6a042c95-8f52-45e0-a4d4-e365ecc52737`
> 拒审日期：2026-10-15 · 版本 1.0 (5) · 设备 iPad Air 11-inch (M3)
>
> **用法**：
> 1. 先在 App Store Connect → Resolution Center 直接回复下面「英文回复正文」；
> 2. 同时把「Notes 字段内容」填进 App Store Connect → App Information → **App Review Information → Notes**
>    （Notes 只收文本，放不了视频文件 —— 把录屏传到可公开访问的链接后，把**链接**贴进去）；
> 3. 重新提交版本。

---

## 一、Resolution Center 英文回复正文

```
Hello App Review Team,

Thank you for the detailed review of 写字台 (xiezitai) and for the clear guidance on Guideline 1.2. We have implemented every required precaution for user-generated content. Below is what changed in build 1.0 (6).

1. Terms of Use (EULA) shown before login

The full Terms of Use and Community Guidelines are now presented inside the app BEFORE a user can register or log in. The login screen shows a mandatory checkbox — "I have read and agree to the Terms of Use and Community Guidelines" — and the login button stays disabled until it is checked. Tapping the blue link opens the complete agreement in-app (it is bundled in the app binary, so it is readable offline). The same text is published at https://xiezitai.cn/terms.html

2. Mechanism to flag objectionable content

Users can now flag ARTICLES, COMMENTS, and other USERS — not just comments as before. Long-pressing any comment, or tapping the flag icon on any article, opens a report sheet with a required reason picker:
  • Spam / advertising
  • Harassment / personal attacks
  • Sexually explicit content
  • Violence or harm to others
  • Illegal content
  • Other (with optional free-text detail)
Each report creates a moderation ticket that immediately notifies the developer through our internal alerting channel.

3. Mechanism to block abusive users

Users can block any other user from the comment long-press menu ("Block @username") and manage the list in Settings → Blocked Users. When a block is created:
  • All content from the blocked user is removed from the blocker's feed and comment lists IMMEDIATELY — filtering happens on the server at query time, so it takes effect on the very next fetch, and the client additionally re-filters locally so the change is visible without waiting for a refresh.
  • The developer is notified automatically (the block event, including how many users have blocked that account, is pushed to our moderation channel).
  • The blocked user receives no notification and can never tell who blocked them.
Users can unblock at any time in Settings → Blocked Users.

4. Developer acts on reports within 24 hours

Every report is a tracked ticket with status, reason, timestamps, and the action taken. Our moderation console (后台 / Admin → 举报处理) provides one-click resolution with four actions:
  • Remove content — deletes the offending article/comment (including all nested replies)
  • Ban user — ejects the offending account: it is disabled and force-signed-out immediately (existing JWTs stop working at once, not at expiry)
  • Remove content AND ban user — the standard action for confirmed violations
  • Dismiss — report not substantiated
Our operating commitment is a 24-hour SLA: remove the content and eject the offending user within 24 hours of the report. An overdue scan surfaces any open ticket past 24 hours and re-alerts the moderation team. We also publish the moderation contact address — zhongdaiqi@qq.com — inside the app (Settings → 举报与申诉邮箱) and in the Terms of Use.

5. Additional safeguards already in place

  • Pre-publication review: all articles and comments from non-admin accounts must be approved by a moderator before they become publicly visible.
  • Account deletion: Settings → Delete Account removes the account together with all of its articles and comments.
  • Login lockout, TOTP two-factor authentication, full request logging, and upload type restrictions.

A screen recording captured on a physical device demonstrating items 1–3 is linked in the Notes field of App Review Information, as requested. Please let us know if you need anything else.

Best regards,
写字台 (xiezitai) Developer Team
Moderation contact: zhongdaiqi@qq.com
```

---

## 二、App Review Information → Notes 字段内容

Notes 只接受纯文本，视频放不进去 —— **把录屏传到可公开访问的链接**（阿里云 OSS / 腾讯云 COS / YouTube Unlisted / 百度网盘直链），再把链接贴这里。

```
Guideline 1.2 — User-Generated Content safeguards (implemented in build 1.0 (6))

Screen recording captured on a physical device:
https://<把录屏的公开链接填这里>

The recording demonstrates, in order:
  00:00–00:35  Terms of Use (EULA) presented before login — the agreement is opened and read
               in full, then the consent checkbox is ticked before the login button becomes active.
  00:35–01:20  Flagging objectionable content — long-press a comment → select a report reason →
               submit; then tap the flag icon on an article → select a reason → submit.
  01:20–02:00  Blocking an abusive user — long-press a comment → Block @username → confirm;
               the blocked user's content disappears from the feed immediately.
               Settings → Blocked Users shows the block list with an unblock action.

Moderation contact for objectionable content reports: zhongdaiqi@qq.com (24-hour response SLA).
Terms of Use published at: https://xiezitai.cn/terms.html
Privacy Policy published at: https://xiezitai.cn/privacy.html

Backend endpoints used (all require authentication except where noted):
  POST   /api/blocks                  Block a user (notifies the developer; filters the feed)
  DELETE /api/blocks/{username}       Unblock
  GET    /api/blocks                  List blocked users
  POST   /api/reports                 Flag article / comment / user with a reason
  GET    /api/admin/reports           Moderation ticket queue (admin)
  POST   /api/admin/reports/{id}/resolve   Remove content / ban user / both / dismiss (admin)
```

---

## 三、提交前检查清单

- [ ] 录屏已上传，链接可公开访问（**先用无痕窗口确认不用登录也能打开**）
- [ ] 版本号已升到 **1.0 (6)**（build 号必须比被拒的 5 大）
- [ ] `pubspec.yaml` 的 `version` 与 App Store Connect 上的版本一致
- [ ] 后端 `E:\xiezitai` 已重新打包并部署到 https://xiezitai.cn（举报/屏蔽接口要在线）
- [ ] `https://xiezitai.cn/terms.html` 与 `https://xiezitai.cn/privacy.html` 返回 200
- [ ] Notes 字段与 Resolution Center 都填了（两处都填最稳）
- [ ] 演示账号已准备：审查员需要能登录才能测举报与屏蔽
      → 建议提供一个**测试账号**并在 Notes 里写明账号密码（Apple 明确允许且鼓励提供 demo account）
