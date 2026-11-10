#!/usr/bin/env bash
# 빌드된 웹(app/build/web)을 서빙한다. 먼저 scripts/build-web.sh를 실행한다.
# 다시 빌드하면 브라우저가 바로 새 파일을 받도록 캐시하지 않게 응답한다.
#
#   scripts/run-web.sh                 # 127.0.0.1:8765
#   PORT=8080 scripts/run-web.sh
set -euo pipefail

cd "$(dirname "$0")/../app/build/web" 2>/dev/null || {
  echo "app/build/web이 없습니다. scripts/build-web.sh를 먼저 실행해 주세요." >&2
  exit 1
}
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8765}"

exec python3 - "$HOST" "$PORT" <<'PY'
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

host, port = sys.argv[1], int(sys.argv[2])
print(f"웹: http://{host}:{port}", flush=True)
ThreadingHTTPServer((host, port), Handler).serve_forever()
PY
