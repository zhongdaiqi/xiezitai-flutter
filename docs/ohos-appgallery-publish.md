# 鸿蒙 .app 自动上传 AppGallery Connect（AGC）

CI 里 `ohos-release.yml` 打完 `ohos-default-signed.app` 之后，直接调 AGC 发布 API 把包传上去，
省掉登录 AGC 控制台手动拖文件这一步。实现只有两个文件：

| 文件 | 作用 |
|---|---|
| `scripts/agc-upload.sh` | 换 token → 申请 OBS 上传地址 → 直传 → 关联版本草稿 → 轮询解析状态 →（可选）提交审核 |
| `.github/workflows/ohos-release.yml` | 打 `v*` tag 或手动触发时，构建完成后调用上面的脚本 |

---

## 一、准备（只有第一次要做）

### 1. AGC 后台已有这个应用

应用包名必须是 **`cn.xiezitai.app.hm`**（与 `.p7b` Profile 绑定的包名一致），并且
「证书、APP ID 和 Profile」里登记的**发布证书**就是 CI 用的那张 `.cer`。
否则包能传上去，但解析/提审一定失败。

### 2. 创建凭据：选「服务账号 + 开发者级」，或退一步用「API 客户端 + N/A」

AGC 的 API 凭证分几种「类型」，**只有开发者级能调发布接口**：

| 类型 | 能不能传包 | 说明 |
|---|---|---|
| **服务账号（开发者级）** | ✅ 推荐 | 华为明确说「Service Account 将取代 API 客户端」。下载 `private.json`，本地签 PS256 JWT 直接当 Bearer token，无需换 token |
| **API 客户端（项目选 N/A）** | ✅ 可用 | 老方式，`client_id` + `client_secret` 换 `access_token`。项目选 N/A 等价于开发者级 |
| 服务账号 / API 客户端（**项目级**） | ❌ | 报 `403 project credential can not access the developer credentialType api` |
| **应用级** | ❌ | 权限只覆盖单个应用的部分读接口，发布接口不认 |
| OAuth 2.0 客户端（项目设置 → 常规里的 Client ID） | ❌ | 那就是 App ID，一律 403 |

**服务账号（推荐）**：用户与访问 → API 密钥 → Connect API → **Service Account** 页签 → 创建
- 类型：**开发者级**
- 角色：勾上「应用发布 / 应用管理员」
- 创建后自动下载 `****private.json`（内含 `key_id` / `private_key` / `sub_account`），
  转成单行 base64 存成 Secret `AGC_SERVICE_ACCOUNT_JSON_BASE64`

**API 客户端（本项目当前用的就是这个）**：同一个页面切到 **API 客户端** 页签 → 创建
- **项目：必须选「N/A」**
- 角色：至少「应用管理员」或「APP管理员」
- 记下 **Client ID**（19 位）和 **Client Secret**（64 位，只显示一次）

脚本两种都支持：配了 `AGC_SERVICE_ACCOUNT_JSON_BASE64` 就优先走服务账号，否则用 client_id/secret。

### 3. 取 App ID

AGC → 我的应用 → 点进应用 → 「应用信息」页，**App ID**（APP ID 一栏，约 10~16 位数字串）。
注意不是包名，也不是 client_id。

### 4. 写进 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → **New repository secret**：

| Secret | 值 | 必需 |
|---|---|---|
| `AGC_APP_ID` | 第 3 步的 App ID | ✅ |
| `AGC_SERVICE_ACCOUNT_JSON_BASE64` | 服务账号 `private.json` 的单行 base64 | 二选一 |
| `AGC_CLIENT_ID` | API 客户端的 Client ID | 二选一 |
| `AGC_CLIENT_SECRET` | API 客户端的 Client Secret | 二选一 |

任一鉴权方式配齐（再加 `AGC_APP_ID` 和已有的 `OHOS_SIGN_STORE_FILE_BASE64`）才会触发上传；
缺了，workflow 里这步直接跳过（只留 artifact，不会报红）。

---

## 二、跑起来

```bash
git tag v1.0.1 && git push origin v1.0.1     # 或 Actions 页面手动 Run workflow
```

日志里应该出现：

```
📦 待上传：ohos-default-signed.app  11 MB  sha256=ea492d23dba60526…
🔑 换取 access_token
🔗 申请上传地址
   objectId=CN/2026xxxx/xxxx.app
⬆️  直传文件（PUT，带 8 个 header 参数）
   HTTP 200 上传完成
📎 关联软件包到版本草稿
   packageId=1573xxxx5952
⏳ 等待 AGC 解析软件包（异步，通常 1~3 分钟）
✅ 软件包解析成功
🎉 完成：… 已进入 AppGallery Connect 的版本草稿
```

包落到 AGC 的**当前版本草稿**，不会自动上架——还要在控制台补更新说明、点「提交审核」。

### 要不要连提审也自动化

默认不自动提审（提审是对外生效的动作，且要求应用信息齐全）。想开就在
Settings → Secrets and variables → Actions → **Variables** 里加：

| Variable | 说明 |
|---|---|
| `SUBMIT_FOR_REVIEW` | `true` = 包解析成功后自动调 `app-submit` 进审核队列 |

开了之后，`app-submit` 失败大概率是应用信息不全（缺更新说明 / 图标 / 隐私政策链接），
需要先在控制台补齐。

---

## 三、必须知道的几个坑

| 现象 | 原因 | 处理 |
|---|---|---|
| 关联软件包报错，`ret.msg` 提到版本号 | **versionCode 重复**。写字台的 versionCode 写在 `ohos/AppScope/app.json5`（当前 `1000000`），每次上架必须递增 | 改 `app.json5` 的 `versionCode`（Flutter 的 `pubspec.yaml version: 1.0.0+1` 不会自动同步到鸿蒙侧） |
| 报「无草稿版本 / 版本不存在」 | 应用还没建过版本，或上一次的版本已提审完了 | 控制台手动点「创建版本」建个草稿，再重跑 |
| 解析 `successStatus=2` | 证书链不全、profile 与包名不符、targetSdk 太低 | 控制台版本详情页有具体错误 |
| `HTTP 403 SignatureDoesNotMatch`（上传那步） | OBS 签名头被改过 | 脚本已原样透传 `urlInfo.headers`，别自己加 `Content-Type` |
| 传上去文件 0 字节 | Windows 下 `jq.exe` 输出带 `\r`，混进 URL/header | 脚本里已用 `jq() { command jq "$@" \| tr -d '\r'; }` 兜住 |
| 上传地址 5 分钟内失效 | 先申请地址、再排队等几分钟才传 | 脚本是拿到地址立刻传，别在这两步之间插长任务 |

---

## 四、本地验证（不想真传到线上）

脚本支持 `AGC_API_BASE` 指向 mock 服务，可以整套跑通而不碰华为服务器：

```bash
AGC_API_BASE=http://127.0.0.1:18099 \
AGC_CLIENT_ID=cid AGC_CLIENT_SECRET=secret AGC_APP_ID=appid \
AGC_POLL_INTERVAL=1 AGC_SUBMIT=true \
  bash scripts/agc-upload.sh path/to/ohos-default-signed.app
```

mock 服务需要实现 5 个端点：`/api/oauth2/v1/token`、`/api/publish/v2/upload-url/for-obs`、
上传用的 `PUT`、`/api/publish/v3/app-package-info`、`/api/publish/v3/package/compile/status`。

---

## 五、接口速查

| 步骤 | 方法与路径 | 关键参数 |
|---|---|---|
| 换 token | `POST /api/oauth2/v1/token` | body: `client_id` `client_secret` `grant_type=client_credentials` |
| 申请上传地址 | `GET /api/publish/v2/upload-url/for-obs` | `appId` `fileName` `contentLength` `sha256`，头带 `client_id` + `Bearer` |
| 直传 | `PUT {urlInfo.url}` | 原样带 `urlInfo.headers`，`urlInfo.method` 是 PUT |
| 关联草稿 | `PUT /api/publish/v3/app-package-info?appId=` | body: `{fileName, objectId}` → `packageId` |
| 查解析状态 | `GET /api/publish/v3/package/compile/status?appId=&pkgIds=` | `successStatus`: 0 成功 / 1 解析中 / 2 失败 |
| 提交审核 | `POST /api/publish/v3/app-submit?appId=` | body: `{releaseType:1, remark}` |

HarmonyOS 5+ 的发布接口是 **v3**（`app-package-info` / `app-submit` / `compile/status`），
但上传地址仍是 v2 的 `upload-url/for-obs`——这个混用是官方如此，不是笔误。
