#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 把签名后的 HarmonyOS .app 上传到 AppGallery Connect（AGC）
#
# 流程（全部走 AGC Connect API，HarmonyOS 5 及以上用 v3 发布接口）：
#   1. 鉴权：Service Account（JWT PS256，推荐）或 API 客户端（换 access_token）
#   2. GET  /api/publish/v2/upload-url/for-obs        申请 OBS 上传地址
#   3. PUT  <urlInfo.url>                             直传文件（签名头必须原样带上）
#   4. PUT  /api/publish/v3/app-package-info          把 objectId 关联到当前版本草稿 → packageId
#   5. GET  /api/publish/v3/package/compile/status    轮询包解析状态（异步，通常 1~3 分钟）
#   6. POST /api/publish/v3/app-submit                可选：提交审核（AGC_SUBMIT=true 才执行）
#
# 用法：
#   AGC_SERVICE_ACCOUNT_JSON_BASE64=xxx AGC_APP_ID=xxx \
#     bash scripts/agc-upload.sh ohos/build/outputs/default/ohos-default-signed.app
#
# 鉴权二选一（都配时优先 Service Account）：
#   AGC_SERVICE_ACCOUNT_JSON_BASE64  Service Account 的 ****private.json 单行 base64（推荐）
#   AGC_SERVICE_ACCOUNT_FILE         同上，改成文件路径（本地调试用）
#   AGC_CLIENT_ID / AGC_CLIENT_SECRET  API 客户端（旧方式，华为已标记将被取代）
#   AGC_APP_ID                       必填，应用的 App ID（不是包名、不是 client_id）
#
# 可选环境变量：
#   AGC_RELEASE_TYPE     1=全网（默认）  6=HarmonyOS 测试发布
#   AGC_UPLOAD_TIMEOUT   等待包解析的超时秒数，默认 600
#   AGC_POLL_INTERVAL    解析状态轮询间隔秒数，默认 15
#   AGC_SUBMIT           true 表示解析成功后自动提交审核（会真的进审核队列）
#   AGC_SUBMIT_REMARK    提审备注，10~300 字，可不填
#   AGC_API_BASE         仅自测用：把 API 域名换成 mock 服务
#
# 注意：本脚本只做「上传 + 关联草稿版本」，不修改应用信息（简介、更新说明等）。
#       应用信息不完整时 app-submit 会报错，需先在控制台补齐。
# ---------------------------------------------------------------------------
set -euo pipefail

API="${AGC_API_BASE:-https://connect-api.cloud.huawei.com}"
APP_FILE="${1:-ohos/build/outputs/default/ohos-default-signed.app}"

die() { echo "❌ $*" >&2; exit 1; }

[ -f "$APP_FILE" ] || die "找不到安装包：$APP_FILE"
command -v jq >/dev/null 2>&1 || die "需要 jq（ubuntu-latest 自带；本地用 choco/scoop 装一个）"

# Windows 版 jq.exe 输出 CRLF：\r 会混进 URL、OBS 签名头和 JSON 字段，
# 表现为「上传成功但文件 0 字节 / 403 SignatureDoesNotMatch」。统一剥掉。
jq() { command jq "$@" | tr -d '\r'; }

need() { [ -n "${!1:-}" ] || die "缺少环境变量 $1"; }
need AGC_APP_ID

FILE_NAME="$(basename "$APP_FILE")"
SIZE="$(wc -c < "$APP_FILE" | tr -d ' ')"
SHA256="$(sha256sum "$APP_FILE" | cut -d' ' -f1)"

# 临时目录用全局变量：trap 在脚本退出时执行，函数内的 local 那时已经失效
# （踩过：local 变量进 trap 会让 set -u 报 "keyfile: unbound variable"）
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

printf '📦 待上传：%s  %s MB  sha256=%s…\n' "$FILE_NAME" "$((SIZE / 1024 / 1024))" "${SHA256:0:16}"

# ---------------------------------------------------------------------------
# 1. 鉴权
# ---------------------------------------------------------------------------
AUTH_HDR=()

_b64url() { "$OPENSSL" base64 -A | tr '+/' '-_' | tr -d '='; }

# Service Account：用 private.json 里的 key_id / sub_account / private_key
# 本地签一个 PS256 JWT，签名结果本身就直接当 Bearer token 用（不需要换 access_token）
_mint_sa_jwt() {
  local json="$1" key_id sub private_key iat exp keyfile sigfile h p sig
  key_id="$(jq -r '.key_id // empty' <<<"$json")"
  sub="$(jq -r '.sub_account // empty' <<<"$json")"
  private_key="$(jq -r '.private_key // empty' <<<"$json")"
  [ -n "$key_id" ] && [ -n "$sub" ] && [ -n "$private_key" ] \
    || die "Service Account 凭据缺少 key_id / sub_account / private_key，检查 private.json 是否完整"

  keyfile="$TMPD/sa.pem"; sigfile="$TMPD/jwt.sig"
  chmod 600 "$keyfile" 2>/dev/null || true
  printf '%s\n' "$private_key" > "$keyfile"

  iat="$(date +%s)"; exp=$((iat + 3600))
  h="$(printf '{"kid":"%s","typ":"JWT","alg":"PS256"}' "$key_id" | _b64url)"
  p="$(printf '{"aud":"https://oauth-login.cloud.huawei.com/oauth2/v3/token","iss":"%s","exp":%s,"iat":%s}' \
        "$sub" "$exp" "$iat" | _b64url)"
  # 先落盘再取 base64：避免 Windows 上二进制签名走管道被当文本处理
  printf '%s.%s' "$h" "$p" | "$OPENSSL" dgst -sha256 -sign "$keyfile" \
    -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:32 -sigopt rsa_mgf1_md:sha256 \
    -out "$sigfile"
  sig="$("$OPENSSL" base64 -A -in "$sigfile" | tr '+/' '-_' | tr -d '=')"
  printf '%s.%s.%s' "$h" "$p" "$sig"
}

SA_JSON=""
if [ -n "${AGC_SERVICE_ACCOUNT_JSON_BASE64:-}" ]; then
  SA_JSON="$(printf '%s' "$AGC_SERVICE_ACCOUNT_JSON_BASE64" | tr -d ' \r\n' | base64 -d 2>/dev/null || true)"
elif [ -n "${AGC_SERVICE_ACCOUNT_FILE:-}" ]; then
  SA_JSON="$(jq -c . "$AGC_SERVICE_ACCOUNT_FILE")"
fi

if [ -n "${SA_JSON//[[:space:]]/}" ]; then
  case "${SA_JSON:0:1}" in
    '{') ;;
    *) die "Service Account 凭据内容不是 JSON，确认是 private.json 的单行 base64（不是 .p12/.p7b）" ;;
  esac
  OPENSSL="$(command -v openssl || true)"
  [ -n "$OPENSSL" ] || die "Service Account 方式需要 openssl（ubuntu-latest 自带）"
  AUTH_MODE="Service Account（开发者级，JWT PS256）"
  TOKEN="$(_mint_sa_jwt "$SA_JSON")"
  AUTH_HDR=(-H "Authorization: Bearer $TOKEN")
elif [ -n "${AGC_CLIENT_ID:-}" ] && [ -n "${AGC_CLIENT_SECRET:-}" ]; then
  AUTH_MODE="API 客户端（client_id + access_token）"
  echo "🔑 换取 access_token"
  TOKEN_BODY="$(jq -nc --arg id "$AGC_CLIENT_ID" --arg secret "$AGC_CLIENT_SECRET" \
    '{client_id: $id, client_secret: $secret, grant_type: "client_credentials"}')"
  TOKEN_JSON="$(curl -sS -X POST "$API/api/oauth2/v1/token" \
    -H 'Content-Type: application/json' -d "$TOKEN_BODY")"
  TOKEN="$(jq -r '.access_token // empty' <<<"$TOKEN_JSON")"
  [ -n "$TOKEN" ] || die "获取 token 失败：$TOKEN_JSON"
  AUTH_HDR=(-H "Authorization: Bearer $TOKEN" -H "client_id: $AGC_CLIENT_ID")
else
  die "没有可用凭据：配 AGC_SERVICE_ACCOUNT_JSON_BASE64（推荐）或 AGC_CLIENT_ID + AGC_CLIENT_SECRET，外加 AGC_APP_ID"
fi

echo "🔐 鉴权方式：$AUTH_MODE"

# ---------------------------------------------------------------------------
# 2. 申请 OBS 上传地址（带上 sha256，AGC 会在上传后校验文件完整性）
# ---------------------------------------------------------------------------
echo "🔗 申请上传地址"
URL_JSON="$(curl -sS -G "$API/api/publish/v2/upload-url/for-obs" \
  "${AUTH_HDR[@]}" \
  --data-urlencode "appId=$AGC_APP_ID" \
  --data-urlencode "fileName=$FILE_NAME" \
  --data-urlencode "contentLength=$SIZE" \
  --data-urlencode "sha256=$SHA256" \
  --data-urlencode "releaseType=${AGC_RELEASE_TYPE:-1}")"

RET_CODE="$(jq -r '.ret.code // -1' <<<"$URL_JSON")"
[ "$RET_CODE" = "0" ] || die "申请上传地址失败：$(jq -c '.ret' <<<"$URL_JSON")"

UPLOAD_URL="$(jq -r '.urlInfo.url // empty' <<<"$URL_JSON")"
OBJECT_ID="$(jq -r '.urlInfo.objectId // empty' <<<"$URL_JSON")"
METHOD="$(jq -r '.urlInfo.method // "PUT"' <<<"$URL_JSON")"
[ -n "$UPLOAD_URL" ] && [ -n "$OBJECT_ID" ] || die "返回体缺少 urlInfo：$URL_JSON"
echo "   objectId=$OBJECT_ID"

# 3. 直传。urlInfo.headers 里的 x-amz-* / Authorization 是 OBS 的签名头，
#    少一个或改一个都会 403，所以原样透传，Content-Type 也不要覆盖。
HDR=()
while IFS=$'\t' read -r k v; do
  [ -n "${k:-}" ] && HDR+=(-H "$k: $v")
done < <(jq -r '.urlInfo.headers // {} | to_entries[] | [.key, .value] | @tsv' <<<"$URL_JSON")

echo "⬆️  直传文件（$METHOD，带 ${#HDR[@]} 个 header 参数）"
PUT_BODY="$TMPD/put-body"
# -H 'Expect:' 关掉 curl 对 >1KB 文件自动加的 Expect: 100-continue
# （OBS 兼容层对它有兼容性问题；Expect 不参与签名，去掉不影响校验）
HTTP_CODE="$(curl -sS -o "$PUT_BODY" -w '%{http_code}' \
  -X "$METHOD" -H 'Expect:' "${HDR[@]+"${HDR[@]}"}" -T "$APP_FILE" "$UPLOAD_URL" || true)"
case "$HTTP_CODE" in
  2*) echo "   HTTP $HTTP_CODE 上传完成" ;;
  *) die "上传失败（HTTP $HTTP_CODE）：$(head -c 300 "$PUT_BODY")" ;;
esac
rm -f "$PUT_BODY"

# ---------------------------------------------------------------------------
# 4. 关联到「当前版本草稿」→ packageId
# ---------------------------------------------------------------------------
echo "📎 关联软件包到版本草稿"
PKG_JSON="$(curl -sS -X PUT "$API/api/publish/v3/app-package-info?appId=$AGC_APP_ID" \
  "${AUTH_HDR[@]}" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg f "$FILE_NAME" --arg o "$OBJECT_ID" '{fileName: $f, objectId: $o}')")"

RET_CODE="$(jq -r '.ret.code // -1' <<<"$PKG_JSON")"
if [ "$RET_CODE" != "0" ]; then
  echo "   $(jq -c '.ret' <<<"$PKG_JSON")" >&2
  die "关联软件包失败。常见原因：① versionCode 与 AGC 上已有版本重复；② AGC 后台没有可落的版本草稿；③ 签名证书与 AGC 登记的不一致；④ 凭据是「项目级」而非「开发者级」（会报 project credential can not access the developer credentialType api）"
fi
PKG_ID="$(jq -r '.packageId // empty' <<<"$PKG_JSON")"
[ -n "$PKG_ID" ] || die "返回体缺少 packageId：$PKG_JSON"
echo "   packageId=$PKG_ID"

# ---------------------------------------------------------------------------
# 5. 轮询解析状态：successStatus 0=成功 1=解析中 2=失败
# ---------------------------------------------------------------------------
echo "⏳ 等待 AGC 解析软件包（异步，通常 1~3 分钟）"
DEADLINE=$(( $(date +%s) + ${AGC_UPLOAD_TIMEOUT:-600} ))
while :; do
  STATE_JSON="$(curl -sS -G "$API/api/publish/v3/package/compile/status" \
    "${AUTH_HDR[@]}" \
    --data-urlencode "appId=$AGC_APP_ID" \
    --data-urlencode "pkgIds=$PKG_ID")"
  STATUS="$(jq -r --arg p "$PKG_ID" \
    '.pkgStateList[]? | select(.pkgId == $p) | .successStatus' <<<"$STATE_JSON" 2>/dev/null || true)"
  case "${STATUS:-}" in
    0) echo "✅ 软件包解析成功"; break ;;
    2) die "软件包解析失败，请到 AGC 控制台查看具体错误（常见：证书链不全、profile 与包名不符、targetSdk 过低）" ;;
    *) echo "   …解析中（successStatus=${STATUS:-未知}）" ;;
  esac
  [ "$(date +%s)" -lt "$DEADLINE" ] || die "等待解析超时（${AGC_UPLOAD_TIMEOUT:-600}s），包已上传，可到 AGC 控制台确认状态"
  sleep "${AGC_POLL_INTERVAL:-15}"
done

# ---------------------------------------------------------------------------
# 6. 可选：提交审核
# ---------------------------------------------------------------------------
if [ "${AGC_SUBMIT:-false}" = "true" ]; then
  echo "🚀 提交发布（进审核队列）"
  if [ -n "${AGC_SUBMIT_REMARK:-}" ]; then
    SUBMIT_BODY="$(jq -nc --arg r "$AGC_SUBMIT_REMARK" '{releaseType: 1, remark: $r}')"
  else
    SUBMIT_BODY='{"releaseType":1}'
  fi
  SUBMIT_JSON="$(curl -sS -X POST "$API/api/publish/v3/app-submit?appId=$AGC_APP_ID" \
    "${AUTH_HDR[@]}" \
    -H 'Content-Type: application/json' \
    -d "$SUBMIT_BODY")"
  RET_CODE="$(jq -r '.ret.code // -1' <<<"$SUBMIT_JSON")"
  if [ "$RET_CODE" = "0" ]; then
    echo "✅ 已提交审核"
  else
    die "提交审核失败（应用信息可能不完整，如更新说明/图标/隐私政策）：$(jq -c '.ret' <<<"$SUBMIT_JSON")"
  fi
fi

echo "🎉 完成：$FILE_NAME 已进入 AppGallery Connect 的版本草稿（packageId=$PKG_ID）"
