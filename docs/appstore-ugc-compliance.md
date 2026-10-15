# 写字台 UGC 合规改造说明（App Store Guideline 1.2）

> 背景：版本 1.0 (5) 因 Guideline 1.2「User-Generated Content」被拒。
> 审查员要求四项：① 登录前呈现 EULA；② 举报不良内容；③ 屏蔽施虐用户（通知开发者 + 内容立即从信息流移除）；
> ④ 开发者 24 小时内删内容 + 踢人。
>
> 涉及两个仓库：后端 `E:\xiezitai`（Spring Boot）+ 客户端 `E:\xiezitai-flutter`（Flutter）。

---

## 一、改造前后对照

| 审查要求 | 改造前 | 改造后 |
|---|---|---|
| EULA 登录前呈现 | 无。登录页只有账号密码，设置页仅有隐私政策外跳链接 | 登录页增加「我已阅读并同意《服务条款与社区规范》」勾选，未勾选无法登录；点击可查看全文（内置在 App 里，离线可读） |
| 举报不良内容 | 仅 `POST /api/comments/{id}/report`，**只能举报评论**，无理由分类、无工单 | 统一 `POST /api/reports`，覆盖**文章 / 评论 / 用户**，带 6 类理由，落成工单并通知管理员 |
| 屏蔽施虐用户 | **完全没有** | `POST /api/blocks` 屏蔽；屏蔽时通知开发者；屏蔽后文章流与评论列表**立即**过滤 |
| 24h 内删内容 + 踢人 | 举报只是给评论打个 `reported` 标记，无工单、无 SLA、无封禁 | 举报工单 + 管理端一键处置（删内容 / 封禁 / 两者 / 驳回），封禁即时踢下线，含 24h 逾期扫描 |

---

## 二、后端新增（E:\xiezitai）

### 新增文件

| 文件 | 作用 |
|---|---|
| `entity/UserBlock.java` | 屏蔽关系（单向：`blockerId` + `blockedUsername`，唯一约束） |
| `entity/AbuseReport.java` | 举报工单（类型/目标/理由/状态/处置动作/处理人/处理时间 + 快照字段） |
| `repository/UserBlockRepository.java` | 屏蔽关系查询，含 `findBlockedUsernames` 供信息流过滤 |
| `repository/AbuseReportRepository.java` | 工单查询，含按状态统计与重复举报去重 |
| `service/SafetyService.java` | 屏蔽 / 举报 / 处置 / 解封的领域逻辑，含企微通知 |
| `controller/SafetyController.java` | 屏蔽与举报的 HTTP 接口 + 管理员处置接口 |
| `static/terms.html` | 服务条款与社区规范（EULA）公开页 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `entity/User.java` | 新增 `banned` / `bannedReason` / `bannedAt` 三个封禁字段 |
| `security/JwtAuthFilter.java` | 加 `!user.isBanned()` —— **已签发的令牌立即失效**，不等自然过期 |
| `controller/AuthController.java` | 登录后校验封禁，返回 `403 BANNED` |
| `security/SecurityConfig.java` | 放行 `/terms.html`；`/api/blocks`、`/api/reports` 设为必须登录 |
| `controller/ArticleController.java` | 文章流按屏蔽名单过滤（新增 `SafetyService` 依赖） |
| `repository/ArticleRepository.java` | 新增 `findPublishedExcludingAuthors`、`searchPublishedExcluding` |
| `controller/CommentController.java` | 评论列表按屏蔽名单过滤；旧举报接口委派到统一工单 |
| `controller/PageViewController.java` | 网页端首页与搜索同样按屏蔽名单过滤 |
| `static/privacy.html` | 补充「内容举报与屏蔽」章节与举报邮箱 |

### 接口清单

```
# 用户侧（需登录）
POST   /api/blocks                  屏蔽用户 {username}
DELETE /api/blocks/{username}       解除屏蔽
GET    /api/blocks                  我的屏蔽名单
POST   /api/reports                 举报 {type: ARTICLE|COMMENT|USER, targetId, reason, detail?}
POST   /api/comments/{id}/report    举报评论（兼容旧入口，内部走统一工单）

# 管理员侧
GET    /api/admin/reports                   工单列表（?status=OPEN 只看待处理）
GET    /api/admin/reports/stats             看板：待处理 / 逾期 / 今日已处理
POST   /api/admin/reports/{id}/resolve      处置 {action, note?}
POST   /api/admin/reports/scan-overdue      逾期扫描并推送告警
POST   /api/admin/users/{username}/unban    解封
```

**处置动作四种**：

| action | 行为 |
|---|---|
| `remove_content` | 删除被举报内容（文章删文章；评论连带子回复；用户则删其全部文章与评论） |
| `ban_user` | 封禁内容作者：`enabled=false` + `banned=true`，即时踢下线 |
| `remove_and_ban` | 两者都做 —— 审查员要求的标准处置 |
| `dismiss` | 举报不成立，结单不处置 |

### 举报理由枚举

`SPAM`（垃圾广告/刷屏）、`ABUSE`（辱骂骚扰/人身攻击）、`PORN`（色情或露骨）、
`VIOLENCE`（暴力或危害他人）、`ILLEGAL`（违法违规）、`OTHER`（其他）

### 关键设计决策

1. **屏蔽只存用户名、不存外键**：文章 `author` 与评论 `authorName` 本来就是字符串快照，
   过滤时用名字直接比对最快，也避免被屏蔽者注销后留下悬空引用。
2. **过滤在查询层，不删数据**：被屏蔽者的内容对其他人仍可见，只对屏蔽者不可见。
   `not in (:blocked)` 在集合为空时某些数据库会编译成恒假条件，所以空集单独走不带过滤的分支。
3. **封禁复用 `enabled` 链路**：`JwtAuthFilter` 本来就检查 `enabled`，封禁后已签发的令牌立刻失效，
   不需要等它自然过期（默认 72 小时，等不起）。
4. **工单留痕**：`targetSummary` / `targetAuthor` 是快照 —— 内容删掉之后工单还得能看懂当时举报的是什么。
5. **重复举报去重**：同一人对同一对象只保留一条 OPEN 工单，防刷单把后台灌满。

---

## 三、客户端新增（E:\xiezitai-flutter）

### 新增文件

| 文件 | 作用 |
|---|---|
| `lib/legal.dart` | EULA 全文（内置，离线可读）、举报受理邮箱常量、举报理由枚举 |
| `lib/safety.dart` | 通用弹层：条款弹窗、举报面板（理由单选 + 补充说明）、屏蔽确认 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `lib/api.dart` | 新增 `report` / `reportArticle` / `blockUser` / `unblockUser` / `myBlocks`；`reportComment` 改为走统一工单 |
| `lib/login_page.dart` | EULA 勾选前置，未勾选无法登录；点击可查看全文；底部展示举报受理邮箱 |
| `lib/detail_page.dart` | 右上角旗子图标举报文章；评论长按菜单增加「屏蔽 @用户」；举报带理由 |
| `lib/main.dart` | 首页拉取屏蔽名单，本地兜底过滤文章流 |
| `lib/settings_page.dart` | 新增「服务条款」「屏蔽名单」「举报与申诉邮箱」三个入口；新增 `BlockListPage`（查看/解除屏蔽） |

### 交互路径

```
登录前 EULA
  登录页 → 勾选「我已阅读并同意《服务条款与社区规范》」→ 点蓝色文字看全文 → 登录按钮才亮

举报文章
  文章详情 → 右上角 🚩 → 选理由 → 补充说明（选填）→ 提交 → 「24 小时内处理」提示

举报评论
  长按评论 → 举报该评论 → 选理由 → 提交

屏蔽用户
  长按评论 → 屏蔽 @xxx → 确认弹窗（说明三点后果）→ 屏蔽
  → 评论当场消失 → 返回首页下拉刷新，该用户文章也没了
  → 设置 → 屏蔽名单 → 解除屏蔽
```

---

## 四、验证情况

- 后端：`mvn -DskipTests compile` → **BUILD SUCCESS**
- 客户端：`flutter analyze` → **No issues found!**
- 网页条款页：`https://xiezitai.cn/terms.html`（部署后需确认 200）

### 管理端处置面板（static/admin.html）

新增「举报处理」tab，位置在「评论」与「用户」之间：

- tab 上有**待处理数量徽标**（有逾期则红色），登录即刷新，管理员不点进去也能看见欠账
- 工单列表：待处理排前、**逾期（超 24h）再顶一层并标红**，行内显示剩余/逾期小时数
- 一键处置四个按钮：删内容 / 封禁作者 / **删内容并封禁**（标准动作）/ 举报不成立
- 「扫描逾期」按钮：调 `/api/admin/reports/scan-overdue`，重新推送逾期告警
- 处置前弹窗二次确认 + 可填内部备注；处置结果弹窗回显

对应 JS：`loadReports(status)` / `resolveReport(id, action)` / `scanOverdueReports()` / `updateReportBadge()`

### 待办（部署后）

1. 后端打包部署，确认 `/api/blocks`、`/api/reports`、`/terms.html` 在线；
2. 准备**两个演示账号**供审查员测试（一个正常号、一个发违规内容的号，**违规内容需先过审**），
   并把账号密码写进 App Store Connect 的 Notes 字段；
3. 按 `appstore-ugc-recording-script.md` 真机录屏并上传公开链接。

---

## 五、运营要求（比代码更重要）

审查员会看开发者**实际**怎么做，所以上线后必须守住：

1. **24 小时 SLA**：收到举报后 24 小时内处置（删内容 + 封禁）。工单列表按 OPEN 排序，
   逾期会推送告警。
2. **举报邮箱有人看**：`zhongdaiqi@qq.com` 是写进条款和 App 的对外承诺邮箱，需要真实可用。
3. **先审后发别关**：普通用户的文章与评论默认 PENDING，管理员审核通过才公开展示 ——
   这是除了举报之外最重要的一道防线，别因为嫌麻烦改成直接公开。
