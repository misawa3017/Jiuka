#!/usr/bin/env bash
# 以指定 Firebase 專案的 Web App 設定 build Flutter Web。
# 每次都從 Firebase CLI 重新取得設定值，缺任何一項就停止，避免 build 出無法啟動的網站。
#
# 用法：scripts/build_web.sh [專案 ID]   （預設讀 .firebaserc 的 default）
# 瀏覽器推播（選用）：VAPID 公開金鑰（Firebase Console → 專案設定 → Cloud Messaging →
# 網路推播憑證）放在 config/vapid_public_keys.json，或用 FIREBASE_VAPID_KEY 環境變數覆寫；
# 沒有設定時推播停用，站內通知照常運作。
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="${1:-$(python3 -c 'import json; print(json.load(open(".firebaserc"))["projects"]["default"])')}"

APP_ID="$(firebase apps:list WEB --project "$PROJECT" --json \
  | python3 -c 'import json,sys; apps=json.load(sys.stdin)["result"]; print(apps[0]["appId"] if apps else "")')"
if [[ -z "$APP_ID" ]]; then
  echo "錯誤：專案 $PROJECT 沒有 Web App。" >&2
  exit 1
fi

CONFIG="$(firebase apps:sdkconfig WEB "$APP_ID" --project "$PROJECT")"
value() { grep -o "\"$1\": \"[^\"]*\"" <<<"$CONFIG" | cut -d'"' -f4; }

API_KEY="$(value apiKey)"
PROJECT_ID="$(value projectId)"
SENDER_ID="$(value messagingSenderId)"
AUTH_DOMAIN="$(value authDomain)"
for name in API_KEY PROJECT_ID SENDER_ID AUTH_DOMAIN; do
  if [[ -z "${!name}" ]]; then
    echo "錯誤：取不到 $name，停止 build。" >&2
    exit 1
  fi
done

# 瀏覽器推播的 VAPID 公開金鑰：優先用環境變數，否則讀 config/vapid_public_keys.json。
if [[ -z "${FIREBASE_VAPID_KEY:-}" && -f config/vapid_public_keys.json ]]; then
  FIREBASE_VAPID_KEY="$(python3 -c 'import json,sys; print(json.load(open("config/vapid_public_keys.json")).get(sys.argv[1], ""))' "$PROJECT_ID")"
fi

echo "使用專案 $PROJECT_ID 的設定 build Web…"
flutter build web \
  --dart-define=FIREBASE_API_KEY="$API_KEY" \
  --dart-define=FIREBASE_APP_ID="$APP_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$PROJECT_ID" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="$SENDER_ID" \
  --dart-define=FIREBASE_AUTH_DOMAIN="$AUTH_DOMAIN" \
  --dart-define=FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY:-}"

# 瀏覽器推播需要的 service worker（網站在背景時由它顯示通知），設定值與 App 相同。
cat > build/web/firebase-messaging-sw.js <<SW
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: '$API_KEY',
  appId: '$APP_ID',
  projectId: '$PROJECT_ID',
  messagingSenderId: '$SENDER_ID',
  authDomain: '$AUTH_DOMAIN',
});
// 帶 notification 欄位的訊息由 SDK 自動顯示；點擊時開啟 fcmOptions.link 指定的場次。
firebase.messaging();
SW

if ! grep -q "$PROJECT_ID" build/web/main.dart.js; then
  echo "錯誤：build 結果沒有包含專案設定。" >&2
  exit 1
fi
if [[ -z "${FIREBASE_VAPID_KEY:-}" ]]; then
  echo "提醒：未設定 FIREBASE_VAPID_KEY，這次 build 不含瀏覽器推播（站內通知仍正常）。"
fi
echo "完成：build/web 已包含 $PROJECT_ID 的設定。"
