#!/usr/bin/env bash
# Flutter 웹을 빌드한다 (결과: app/build/web). 키는 app/.env에서 읽는다.
# API 주소와 목 모드만 여기서 덮어쓴다 (app/.env는 바꾸지 않는다).
#
#   scripts/build-web.sh                                      # https://api.muklog.app
#   API_BASE_URL=http://localhost:8010 scripts/build-web.sh
set -euo pipefail

cd "$(dirname "$0")/../app"
API_BASE_URL="${API_BASE_URL:-https://api.muklog.app}"

if [ ! -f .env ]; then
  echo "app/.env가 없습니다. app/.env.example을 복사해서 채워 주세요." >&2
  exit 1
fi

defines=$(mktemp)
trap 'rm -f "$defines"' EXIT
grep -vE '^(API_BASE_URL|USE_MOCK)=' .env > "$defines" || true
printf 'API_BASE_URL=%s\nUSE_MOCK=false\n' "$API_BASE_URL" >> "$defines"

flutter pub get
flutter build web --release --dart-define-from-file="$defines"
echo "빌드 완료: app/build/web (API: $API_BASE_URL)"
