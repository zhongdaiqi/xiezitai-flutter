# App Store Connect 交接指南（签名 + TestFlight）

> 目标：在 GitHub Actions（macOS runner）上自动签名并把 App 传到 TestFlight。
> **全程不需要 Mac，也不需要你导出任何证书 / 描述文件。**

---

## 0. 先分清：4 个值住在「两个不同的网站」

这是最容易出错的地方。苹果把身份信息拆到了两个产品里，名字很像但不是一回事：

| 值 | 长相 | 在哪个网站 | 用途 |
| --- | --- | --- | --- |
| **Team ID** | 10 位大写字母数字，如 `A1B2C3D4E5` | `developer.apple.com/account` | 标识开发者团队，Xcode 签名用 |
| **Issuer ID** | 带连字符的 UUID，如 `57246542-96fe-1a63-e053-0824d011072a` | `appstoreconnect.apple.com` | 全团队共用，JWT 的 `iss` |
| **Key ID** | 10 位，如 `2X9R4HXF34` | `appstoreconnect.apple.com`（每把钥匙一个） | JWT 的 `kid` |
| **.p8 私钥文件** | `AuthKey_2X9R4HXF34.p8`，纯文本 | `appstoreconnect.apple.com`（**只能下载一次**） | 给 JWT 签名 |

> ⚠️ **Team ID ≠ Issuer ID**。前者在 Apple Developer，后者在 App Store Connect，填反了会报 `Invalid ASC json key` 之类的错。

---

## 1. 前置条件（不满足会卡住）

| 条件 | 说明 |
| --- | --- |
| Apple Developer Program 会员（$99/年） | 你已有 |
| 你的 Apple ID 是 **Account Holder 或 Admin** | 只有这两个角色能创建 API 密钥 |
| 已同意最新版协议 | App Store Connect → **协议、税务和银行业务**（Business），有黄色横幅必须点同意。没同意会导致上传被拒 |
| 已注册 Bundle ID | `cn.xiezitai.app`（Certificates, Identifiers & Profiles → Identifiers） |
| 已在 App Store Connect 建好 App 记录 | App Store Connect → 我的 App → **+** → 新建 App，Bundle ID 选 `cn.xiezitai.app` |

> Bundle ID 注册和 App 记录是**两件事**：前者在 Apple Developer 站点，后者在 App Store Connect。首次用 `xcodebuild` 自动签名时可能也会自动注册 Bundle ID，但**App 记录必须你手动建**，否则 TestFlight 里没有落点。

---

## 2. 取 Team ID

1. 打开 <https://developer.apple.com/account>
2. 左侧菜单 → **Membership details**（成员资格详细信息）
3. 页面上 **Team ID** 就是那 10 位字符串

> 直链：`https://developer.apple.com/account#MembershipDetailsCard`

---

## 3. 取 Issuer ID / Key ID / .p8

1. 打开 <https://appstoreconnect.apple.com>
2. 顶部 **用户和访问**（Users and Access） → **集成**（Integrations）标签
3. 左栏选 **App Store Connect API** → 确认在 **Team Keys**（团队密钥）页
4. **Issuer ID** 在本页顶部，点 Copy 复制 → 这就是 Issuer ID
5. 点 **+**（或 Generate API Key）→ 起名（建议 `github-actions-ios`）→ 选角色（见下节）→ Generate
6. 列表里出现新钥匙：**Key ID** 在行内（点 Copy 复制）
7. 点 **Download API Key** 下载 `.p8`

> 首次进入这个页面可能显示 **Request Access**，需要 Account Holder 先点一次申请，通常很快通过。
> **`.p8` 只给下载一次**，苹果不留副本。丢了只能吊销重建（吊销是立刻生效的，重建后要更新 CI）。

### 角色怎么选

| 角色 | 能做什么 | 什么时候用 |
| --- | --- | --- |
| **Admin** | 几乎全部，含证书 / 描述文件管理 | **推荐**。CI 里用 `-allowProvisioningUpdates` 让苹果自动签发证书需要这个 |
| **App Manager** | 管理 App、元数据、构建，可提交审核 | 不给 Admin 时的次选 |
| **Developer** | 管理构建和元数据，可上传 TestFlight | 只上传、不自动管证书时够用 |

> **必须用 Team Key，不能用 Individual Key**：苹果明确限制 Individual Key **无法访问 Provisioning 接口**，自动签名会失败。

---

## 4. 把这 4 个值交给 CI

GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret：

| Secret 名 | 填什么 |
| --- | --- |
| `APPLE_TEAM_ID` | 第 2 步的 Team ID |
| `APP_STORE_CONNECT_ISSUER_ID` | 第 3 步的 Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | 第 3 步的 Key ID |
| `APP_STORE_CONNECT_API_KEY` | `.p8` **文件全文**（用记事本打开，整段粘贴，含 `-----BEGIN PRIVATE KEY-----` 和 `-----END PRIVATE KEY-----` 两行） |

> 也有的模板把 `.p8` 做 base64 后再存。我们直接用明文全文，CI 里写成文件即可。

---

## 5. 安全清单

- [ ] `.p8` 视为密码：只放密钥管理器 / GitHub Secret，**绝不提交进仓库**
- [ ] 每套集成一把独立钥匙，吊销其中一把不影响其他
- [ ] 怀疑泄漏 → App Store Connect → 该钥匙行 → **Revoke**，然后建新的
- [ ] ASC API 密钥**不会自动过期**，轮换靠自觉（建议一年一换）
- [ ] 别无脑用 Admin：只是上传构建的话 App Manager 更安全

---

## 6. 常见报错对照

| 报错 | 原因 |
| --- | --- |
| `Invalid ASC json key` / 认证失败 | Issuer ID 和 Team ID 填反了，或 `.p8` 与其他值不配套 |
| `You must accept the Apple Developer Program License Agreement` | 没同意协议，去 App Store Connect → 协议、税务和银行业务 点同意 |
| 找不到 App / bundle ID | App Store Connect 里还没建 App 记录 |
| Provisioning 相关报错 | 用了 Individual Key，或角色权限不够（换 Admin） |
| `.p8` 相关报错 | 文件内容不完整（少了 BEGIN/END 行），或文件名与 Key ID 不一致 |
