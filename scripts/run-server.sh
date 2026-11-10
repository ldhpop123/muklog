#!/usr/bin/env bash
# API 서버(FastAPI)를 실행한다. 설정은 server/.env에서 읽는다.
# 처음 실행하면 server/.venv를 만들고, requirements.txt가 바뀌었을 때만 다시 설치한다.
#
#   scripts/run-server.sh                 # 127.0.0.1:8010
#   PORT=9000 scripts/run-server.sh
#   HOST=0.0.0.0 scripts/run-server.sh    # 같은 네트워크의 다른 기기에서도 접속 (터널을 쓰면 필요 없음)
set -euo pipefail

cd "$(dirname "$0")/../server"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8010}"

if [ ! -f .env ]; then
  echo "server/.env가 없습니다. server/.env.example을 복사해서 채워 주세요." >&2
  exit 1
fi

if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
fi

stamp=.venv/.requirements.sha256
want=$( (sha256sum requirements.txt 2>/dev/null || shasum -a 256 requirements.txt) | cut -d' ' -f1)
if [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt
  echo "$want" > "$stamp"
fi

exec .venv/bin/uvicorn app.main:app --host "$HOST" --port "$PORT"
