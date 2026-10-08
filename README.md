# 写字台移动客户端（xiezitai-flutter）

[写字台](https://github.com/zhongdaiqi/xiezitai) 的移动客户端，一套 Flutter 代码同时出 **iOS / Android**。

- **服务端**：<https://github.com/zhongdaiqi/xiezitai>（Spring Boot，MIT）
- **本项目**：仅客户端，通过 HTTP 与后端通信

## 当前进度

| 阶段 | 状态 |
| --- | --- |
| 项目骨架（iOS + Android 双平台） | ✅ 已完成 |
| iOS CI（未签名构建）：macOS runner 构建 + 产出未签名 ipa | ✅ 已完成（`.github/workflows/ios.yml`） |
| iOS 签名 + 上传 TestFlight | ✅ 已完成（`.github/workflows/ios-release.yml`） |
| Android CI | ⏳ 待接入 |
| 业务功能（登录 / 看文章 / 评论 / 阅读计数 / 投稿） | ✅ 已完成（`lib/`） |
| 应用图标 | ✅ 已生成（logo → iOS AppIconSet + Android mipmap，`flutter_launcher_icons`） |

> ⚠️ 没有 Mac 电脑，iOS 的编译、签名、上架全部依赖 **GitHub Actions 的 macOS runner**。

## 标识信息

| 项 | 值 |
| --- | --- |
| Dart 包名 | `xiezitai_flutter`（Dart 包名只能小写 + 下划线） |
| iOS Bundle ID | `cn.xiezitai.app` |
| Android applicationId / namespace | `cn.xiezitai.app` |
| 应用显示名 | 写字台 |
| iOS 最低版本 | 15.0（Flutter 3.47 的下限就是 15.0，写低会被自动抬高） |
| Flutter 版本（CI 钉住） | 3.47.6 |

> iOS Bundle ID 一旦在 App Store Connect 建了 App 记录就不好改，动之前先想清楚。

## CI：iOS 构建

`.github/workflows/ios.yml` 在每次 push 到 `main`、发 PR、或手动触发时运行：

1. 在 `macos-latest` 上装 Flutter 3.47.6（带缓存）
2. `flutter pub get` → `flutter analyze` → `flutter test`
3. `flutter build ios --release --no-codesign`
4. 把 `Runner.app` 打进 `Payload/` 压成 `Runner-unsigned.ipa`，作为 artifact 上传

产物在 Actions 那次运行的页面底部 **Artifacts → ios-unsigned-ipa** 下载，保留 14 天。

> 未签名的 ipa **不能直接装到手机上**（需要重签）。这一步的作用是证明「编译链路通」。
> 要能装到手机 / 上 TestFlight，得先接签名（见下）。

### 构建日志里的两行「自动迁移」是正常的

用 Flutter 3.47.6 构建时，日志里会出现：

```
Updating minimum iOS deployment target to 15.0.
Upgrading project.pbxproj / AppFrameworkInfo.plist / Runner.xcscheme
Finished migration to UIScene lifecycle.
```

这是 Flutter 把旧版模板生成的 iOS 工程**就地升级**（部署目标抬到 15.0、切到 UIScene 生命周期）。
它只作用于 CI 的临时工作区，不会提交回仓库，所以每次构建都会重做一遍。

当前已经在仓库里把部署目标对齐成 15.0，所以第一行不该再出现；
UIScene 那步仍会执行，属正常现象。真要彻底消掉，需要在有 Mac 的环境里用
Flutter 3.47.x 重新生成一次 iOS 工程（或用新版 Flutter 本地跑一次 `flutter build ios` 后把改动提交）。

## CI：iOS 发布（签名 → TestFlight）

`.github/workflows/ios-release.yml` 在**手动触发**或**打 `v*` tag** 时运行
（刻意不挂 `push` 到 main——macOS runner 计费是 Linux 的 10 倍，日常提交走 `ios.yml` 的未签名构建就够）：

1. 装 Flutter 3.47.6 → `flutter pub get`
2. 把 Secret 里的 `.p8` 写成 `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`，并校验 BEGIN/END 两行是否完整
3. `flutter build ios --release --no-codesign --build-number=<run_number>`
   （先跑一遍是为了生成 `Generated.xcconfig` 并执行 `pod install`）
4. `xcodebuild archive` + `xcodebuild -exportArchive`
   —— `ExportOptions.plist` 里 `method=app-store-connect`、`destination=upload`，
   导出时**直接上传 App Store Connect**，不需要额外调 `altool`
5. 清理密钥（`if: always()`，失败也删）

**已实测跑通**（[运行记录](https://github.com/zhongdaiqi/xiezitai-flutter/actions/runs/37812064216)）：
归档 `** ARCHIVE SUCCEEDED **` → 上传 `Upload succeeded.` / `** EXPORT SUCCEEDED **`，
产物 `CFBundleIdentifier=cn.xiezitai.app`、`CFBundleShortVersionString=1.0.0`、
`CFBundleVersion=2`、`MinimumOSVersion=15.0`，全程无错误。

> `destination=upload` 是「边导出边上传」，**本地不会留下 `.ipa`**（TestFlight 里那个包就是产物）。
> 想留存 ipa 就把 `destination` 改成 `export`，再自己加一步 `xcrun altool --upload-app`。

### ⚠️ macOS runner 会排队，别误判成卡死

`macos-latest` 的机器池比 Linux 紧张得多，而且**账户级 macOS 并发上限远低于 Linux**，
所以 iOS 流水线常常是第一个排队的。实测踩到过一次：

- 推送 commit 触发的 `ios.yml` 正好占着 runner，紧接着手动触发的发布流程排队等机器；
- **排队满 15 分钟被 GitHub 自动取消**（`runner_name` 为空、`steps` 为空是这个状态的典型特征）；
- 隔几分钟**重新触发一次就正常了**（那次只等了 5 秒就上机器，全程 5 分 40 秒跑完）。

所以：**避免两条 macOS 任务同时跑**；被取消先看 `runner_name` 是否为空，是就重试，不要急着改 workflow。

签名走 **自动签名 + `-allowProvisioningUpdates`**：runner 现场向苹果申请证书和描述文件，用完即弃，
**本机不需要导出任何 `.p12` / `.mobileprovision`**。

> 构建号取 `github.run_number`，天然递增——App Store Connect 会拒绝重复的 `CFBundleVersion`，
> 这样就不会踩「build 已存在」这个坑。
> 上传成功后构建会先在 App Store Connect 里**处理几分钟**，之后才出现在 TestFlight。

### Secrets（已配置）

| Secret | 说明 |
| --- | --- |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect → 用户和访问 → 集成 → App Store Connect API 里的 Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | 同上，新建 Key 时给的 Key ID |
| `APP_STORE_CONNECT_API_KEY` | 该 Key 的 `.p8` 文件**全文**（含 `-----BEGIN/END PRIVATE KEY-----` 两行） |
| `APPLE_TEAM_ID` | Apple Developer 账号的 Team ID（10 位） |

获取路径见 [docs/app-store-connect-setup.md](docs/app-store-connect-setup.md)。

## 本地开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # 需要已连接的设备或模拟器
```

### ⚠️ 本机 Flutter 的坑

这台开发机上装的 Flutter 是 **鸿蒙定制分支**：

```
Flutter 3.27.5-ohos-1.0.1  (gitcode.com/openharmony-tpc/flutter_flutter)
```

而上游 stable 已经到 **3.47.6**，且**上游根本没有 3.27.5 这个版本**（只有 3.27.0 ~ 3.27.4）。
两个后果：

1. 用它生成的项目模板、`pubspec.lock` 与 CI 用的 3.47.6 不是一套，容易出现「本地能跑、CI 挂」。
2. 用 2024 年底的 Flutter 构建的包，提交 App Store 审核时有 **SDK 版本门槛**风险。

**建议**：给这个项目单独装一份上游 Flutter stable（与鸿蒙分支并存、互不干扰），
版本跟 CI 保持一致。在装好之前，本地只当编辑环境用，**以 CI 的构建结果为准**。

## 后端接口现状（做功能前必读）

后端**已经有**移动端要用的绝大部分接口，直接调即可：

| 客户端功能 | 接口 | 鉴权 |
| --- | --- | --- |
| 登录 | `POST /api/auth/login` → 返回 `{token, username, role}` | 无（公开） |
| 注册 | `POST /api/auth/register` → 默认 `PENDING`，需管理员审核 | 无（公开） |
| 当前用户 | `GET /api/auth/me` | `Authorization: Bearer <token>` |
| 文章列表 | `GET /api/articles` | 无（公开） |
| 文章详情 | `GET /api/articles/{slug}` | 无（公开） |
| 读评论 | `GET /api/articles/{slug}/comments` | 无（公开） |
| 发评论 | `POST /api/articles/{slug}/comments` | Bearer；提交后 `PENDING` 待审 |
| 发布文章 | `POST /api/my/articles`（登录用户；管理员直接公开，普通用户进入待审核） | Bearer |

几个必须注意的实现细节：

- **鉴权方式是 `Authorization: Bearer <JWT>` 请求头**（不是 Cookie），登录响应里的 `token` 直接用。
- 登录失败的分支要按响应体区分：`error` 为 `NEED_TOTP`（需两步验证码，把 `totpCode` 一起再提交）、
  `PENDING_REVIEW` / `REJECTED`（待审 / 被驳回），密码错是 401，账号锁定时返回 423。
- **发评论不接受请求体里的 `authorName` / `email`**，服务端一律取登录账号，客户端不用传。
- `SecurityConfig` 末尾是 `.anyRequest().permitAll()`，真正的权限判断在各 Controller 内部，
  所以**不能只靠 401 判断是否登录**，要看具体接口的返回。

**发布权限模型（2026-10 定稿，后端已实现）**：

| 角色 | 保存路径 | 结果 |
| --- | --- | --- |
| 管理员 | `POST /api/my/articles` 或后台 | 直接 `PUBLISHED` 公开 |
| 普通用户 | `POST /api/my/articles` | `PENDING` 待审核，只有作者本人和管理员可见 |
| 审核通过 | `POST /api/admin/articles/{id}/review` `{action:"approve"}` | `PUBLISHED` 公开 |
| 审核驳回 | 同上 `{action:"reject","note":"原因"}` | `REJECTED`（作者可见原因），改完重新提交再进审核 |
| 普通用户改已发布文章 | `PUT /api/my/articles/{id}` | 回炉 `PENDING` 重新审核（防止先过审再改内容） |

**阅读计数**：`GET /api/articles/{slug}`（手机 App 与网页共用）在服务端累加 `viewCount`，
手机端取详情即计入，无需单独上报；预览自己的未公开文章不计数。

## 目录结构

```
lib/                    Dart 源码
  api.dart              HTTP 客户端 + 数据模型（唯一出网入口）
  main.dart             入口 + 首页文章列表
  detail_page.dart      文章详情（Markdown 渲染 + 评论）
  mine_page.dart        我的（投稿管理 / 管理员审核面板）
  editor_page.dart      写文章 / 编辑
  login_page.dart       登录（含 TOTP）
  settings_page.dart    服务器地址设置
test/                   widget 测试
assets/icon/            应用图标源文件（logo）
ios/                    iOS 原生工程（Runner.xcodeproj）
android/                Android 原生工程
docs/
  app-store-connect-setup.md   ASC 密钥获取与 CI 交接指南
.github/workflows/
  ios.yml               iOS 未签名构建（push/PR 触发）
  ios-release.yml       iOS 签名 + 上传 TestFlight（手动/tag 触发）
```

## 许可

MIT，见 [LICENSE](LICENSE)。
