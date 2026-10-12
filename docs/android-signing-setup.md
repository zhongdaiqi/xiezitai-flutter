# Android 发布签名配置（CI 交接）

Android 发布流水线（`android-release.yml`）的签名**全部由 GitHub Secrets 提供**，
本机与仓库都不存放密钥文件。runner 在构建时从 Secret 还原 keystore 与 `key.properties`，用完即删。

> 与 iOS 不同，Android 的构建 / 签名 / 上架全流程都能在 Linux runner 上完成，不需要 Mac。

## 1. 生成上传密钥库（只需一次）

在本机用 JDK 自带的 `keytool` 生成（JDK 17 自带）：

```bash
keytool -genkey -v \
  -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

交互式填完信息后，得到 `upload-keystore.jks`。记住你设的：

- keystore 密码（= `KEYSTORE_PASSWORD`）
- key 别名（= `KEY_ALIAS`，上面用的是 `upload`）
- key 密码（= `KEY_PASSWORD`）

> 这是「上传密钥」，Google Play 用它来认你的更新。把它和上面的三个密码**妥善保管**，
> 丢了就只能联系 Play 支持重置，且旧包无法再用同一密钥升级。

## 2. 把 keystore 编码成 base64（填进 Secret）

**macOS / Linux：**

```bash
base64 -i upload-keystore.jks | tr -d '\n'
```

**Windows（PowerShell）：**

```powershell
certutil -encode upload-keystore.jks upload-keystore.b64
# 用记事本打开 upload-keystore.b64，复制 BEGIN CERTIFICATE 与 END CERTIFICATE 之间的内容（去掉首尾两行）
```

把得到的整段 base64 字符串填进仓库 Secret **`KEYSTORE_BASE64`**。

## 3. 在仓库配置 Secrets

路径：仓库 → Settings → Secrets and variables → Actions → New repository secret。

| Secret | 值 |
| --- | --- |
| `KEYSTORE_BASE64` | 第 2 步得到的整段 base64 |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | 别名（如 `upload`） |
| `KEY_PASSWORD` | key 密码 |

## 4.（可选）配置 Google Play 自动上传

只想要「产物下载自己发」可跳过这步。要 CI 自动传 Google Play 内部测试轨道：

1. Google Play Console → 用户和权限 → 服务账号 → 新建/选中一个 → 下载 JSON（包含 `client_email` / `private_key`）。
2. 把 JSON 全文填进 Secret **`PLAY_STORE_SERVICE_ACCOUNT_JSON`**。
3. 首次上传前，先在 Play Console 把 App 建好、把第 1 步的上传密钥证书
   （`keytool -export -rfc -file upload-certificate.pem -keystore upload-keystore.jks -alias upload`
   导出）登记到「App 签名」里。

配了之后，`android-release.yml` 会在签名构建成功后自动用 `r0adkll/upload-google-play`
传到 `internal` 轨道。

## 5. 本地验证签名配置（可选）

把 `upload-keystore.jks` 放到 `android/app/`，在 `android/key.properties` 写：

```
storePassword=你的store密码
keyPassword=你的key密码
keyAlias=upload
storeFile=upload-keystore.jks
```

然后 `flutter build appbundle --release`。注意：`android/key.properties` 和 `*.jks` 已在 `.gitignore` 忽略，**不要提交**。
