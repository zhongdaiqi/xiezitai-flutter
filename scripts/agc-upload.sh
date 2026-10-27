#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 把签名后的 HarmonyOS .app 上传到 AppGallery Connect（AGC）
#
# 流程（全部走 AGC Connect API，HarmonyOS 5 及以上用 v3 发布接口）：
#   1. POST /api/oauth2/v1/token                      换取 access_token
#   2. GET  /api/publish/v2/upload-url/for-obs        申请 OBS 上传地址
#   3. PUT  <urlInfo.url>                             直传文件（签名头必须原样带上）
#   4. PUT  /api/publish/v3/app-package-info          把 objectId 关联到当前版本草稿 → packageId
#   5. GET  /api/publish/v3/package/compile/status    轮询包解析状态（异步，通常 1~3 分钟）
#   6. POST /api/publish/v3/app-submit                可选：提交审核（AGC_SUBMIT=true 才执行）
#
# 用法：
#   AGC_CLIENT_ID=xxx AGC_CLIENT_SECRET=xxx AGC_APP_ID=xxx \
#     bash scripts/agc-upload.sh ohos/build/outputs/default/ohos-default-signed.app
#
# 可选环境变量：
#   AGC_RELEASE_TYPE     1=全网（默认）  6=HarmonyOS 测试发布
#   AGC_UPLOAD_TIMEOUT   等待包解析的超时秒数，默认 600
#   AGC_POLL_INTERVAL    解析状态轮询间隔秒数，默认 15
#   AGC_API_BASE         仅自测用：把 API 域名换成 mock 服务
#   AGC_SUBMIT           true 表示解析成功后自动提交审核（会真的进审核队列）
#   AGC_SUBMIT_REMARK    提审备注，10~300 字，可不填
#
# 注意：本脚本只做「上传 + 关联草稿版本」，不修改应用信息（简介、更新说明等）。
#       应用信息不完整时 app-submit 会报错，需先在控制台补齐或用 app-info 接口写入。
# ---------------------------------------------------------------------------
set -euo pipefail

API="${AGC_API_BASE:-https://connect-api.cloud.huawei.com}"
APP_FILE="${1:-ohos/build/outputs/default/ohos-default-signed.app}"

die() { echo "❌ $*" >&2; exit 1; }
need() { [ -n "${!1:-}" ] || die "缺少环境变量 $1"; }

need AGC_CLIENT_ID
need AGC_CLIENT_SECRET
need AGC_APP_ID

[ -f "$APP_FILE" ] || die "找不到安装包：$APP_FILE"
command -v jq >/dev/null 2>&1 || die "需要 jq（ubuntu-latest 自带；本地用 choco/scoop 装一个）"

# Windows 版 jq.exe 输出 CRLF：\r 会混进 URL、OBS 签名头和 JSON 字段，
# 表现为「上传成功但文件 0 字节 / 403 SignatureDoesNotMatch」。统一剥掉。
jq() { command jq "$@" | tr -d '\r'; }

FILE_NAME="$(basename "$APP_FILE")"
SIZE="$(wc -c < "$APP_FILE" | tr -d ' ')"
SHA256="$(sha256sum "$APP_FILE" | cut -d' ' -f1)"

echo "📦 待上传：$FILE_NAME  $((SIZE / 1024 / 1024)) MB  sha256=${SHA256:0:16}…"

# ---------------------------------------------------------------------------
# 1. access_token（API 客户端方式）
# ---------------------------------------------------------------------------
echo "🔑 换取 access_token"
TOKEN_BODY="$(jq -nc \
  --arg id "$AGC_CLIENT_ID" \
  --arg secret "$AGC_CLIENT_SECRET" \
  '{client_id: $id, client_secret: $secret, grant_type: "client_credentials"}')"

TOKEN_JSON="$(curl -sS -X POST "$API/api/oauth2/v1/token" \
  -H 'Content-Type: application/json' -d "$TOKEN_BODY")"
TOKEN="$(jq -r '.access_token // empty' <<<"$TOKEN_JSON")"
[ -n "$TOKEN" ] || die "获取 token 失败：$TOKEN_JSON"

# ---------------------------------------------------------------------------
# 2. 申请 OBS 上传地址（带上 sha256，AGC 会在上传后校验文件完整性）
# ---------------------------------------------------------------------------
echo "🔗 申请上传地址"
URL_JSON="$(curl -sS -G "$API/api/publish/v2/upload-url/for-obs" \
  -H "client_id: $AGC_CLIENT_ID" \
  -H "Authorization: Bearer $TOKEN" \
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
PUT_BODY="$(mktemp)"
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
  -H "client_id: $AGC_CLIENT_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg f "$FILE_NAME" --arg o "$OBJECT_ID" '{fileName: $f, objectId: $o}')")"

RET_CODE="$(jq -r '.ret.code // -1' <<<"$PKG_JSON")"
if [ "$RET_CODE" != "0" ]; then
  echo "   $(jq -c '.ret' <<<"$PKG_JSON")" >&2
  die "关联软件包失败。常见原因：① versionCode 与 AGC 上已有版本重复；② AGC 后台没有可落的版本草稿；③ 签名证书与 AGC 登记的不一致；④ appId 与包名不属于同一应用"
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
    -H "client_id: $AGC_CLIENT_ID" \
    -H "Authorization: Bearer $TOKEN" \
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
    SUBMIT_BODY='{"releaseType": 1}'
  fi
  SUBMIT_JSON="$(curl -sS -X POST "$API/api/publish/v3/app-submit?appId=$AGC_APP_ID" \
    -H "client_id: $AGC_CLIENT_ID" \
    -H "Authorization: Bearer $TOKEN" \
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
