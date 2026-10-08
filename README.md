# 写字台移动客户端（xiezitai-flutter）

[写字台](https://github.com/zhongdaiqi/xiezitai) 的移动客户端，一套 Flutter 代码同时出 **iOS / Android**。

- **服务端**：<https://github.com/zhongdaiqi/xiezitai>（Spring Boot，MIT）
- **本项目**：仅客户端，通过 HTTP 与后端通信

## 当前进度

| 阶段 | 状态 |
| --- | --- |
| 项目骨架（iOS + Android 双平台） | ✅ 已完成 |
| iOS CI：macOS runner 构建 + 产出未签名 ipa | ✅ 已完成（[首次运行成功](https://github.com/zhongdaiqi/xiezitai-flutter/actions/runs/37806249260)） |
| iOS 签名 + 上传 TestFlight | ⏳ 待接入（需 App Store Connect API Key） |
| Android CI | ⏳ 待接入 |
| 业务功能（登录 / 看文章 / 评论 / 阅读计数 / 发布文章） | ⏳ 待开发 |

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

### 接签名与 TestFlight 需要准备的 Secrets

都不需要本机导出证书，走 App Store Connect API Key 即可：

| Secret | 说明 |
| --- | --- |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect → 用户和访问 → 集成 → App Store Connect API 里的 Issuer ID |
| `APP_STORE_CONNECT_KEY_ID` | 同上，新建 Key 时给的 Key ID |
| `APP_STORE_CONNECT_API_KEY` | 该 Key 的 `.p8` 文件**全文** |
| `APPLE_TEAM_ID` | Apple Developer 账号的 Team ID（10 位） |

有了这些，CI 里用 `xcodebuild -allowProvisioningUpdates` 就能让 Apple 自动签发证书与描述文件，
再用 App Store Connect API 直接上传构建到 TestFlight。

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

## 目录结构

```
lib/                    Dart 源码
  main.dart             入口 + 首页（当前是最小壳子）
test/                   widget 测试
ios/                    iOS 原生工程（Runner.xcodeproj）
android/                Android 原生工程
.github/workflows/      CI
  ios.yml               iOS 构建流水线
```

## 后端接口现状（做功能前必读）

后端目前对外开放的 API（`/api/v1/*`，Header `X-API-Token`）只有：

| 接口 | 用途 |
| --- | --- |
| `POST /api/v1/publish` | 发布文章 |
| `PUT /api/v1/articles/{id}` | 更新自己发布的文章 |
| `GET /api/v1/articles` | 文章列表（仅已发布） |
| `GET /api/v1/articles/{id}` | 单篇详情（Markdown 原文） |

而客户端要做的 **登录、评论、阅读计数、发评论** 这几项，**开放 API 里都还没有**，
需要先在服务端补接口。所以功能开发的顺序建议是：

1. 服务端补移动端需要的接口（登录换 JWT、评论列表/发表、阅读计数上报）
2. 客户端接接口

## 许可

MIT，见 [LICENSE](LICENSE)。
