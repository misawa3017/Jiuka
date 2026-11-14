#!/usr/bin/env bash
# 以指定 Firebase 專案的 Web App 設定 build Flutter Web。
# 每次都從 Firebase CLI 重新取得設定值，缺任何一項就停止，避免 build 出無法啟動的網站。
#
# 用法：scripts/build_web.sh [專案 ID]   （預設讀 .firebaserc 的 default）
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

echo "使用專案 $PROJECT_ID 的設定 build Web…"
flutter build web \
  --dart-define=FIREBASE_API_KEY="$API_KEY" \
  --dart-define=FIREBASE_APP_ID="$APP_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$PROJECT_ID" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="$SENDER_ID" \
  --dart-define=FIREBASE_AUTH_DOMAIN="$AUTH_DOMAIN"

if ! grep -q "$PROJECT_ID" build/web/main.dart.js; then
  echo "錯誤：build 結果沒有包含專案設定。" >&2
  exit 1
fi
echo "完成：build/web 已包含 $PROJECT_ID 的設定。"
