import os
from pathlib import Path

from dotenv import load_dotenv

# server/.env의 값(네이버 검색 키 등)을 환경변수로 읽는다. 이미 설정된 환경변수가 우선한다.
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from fastapi import FastAPI, Request  # noqa: E402
from fastapi.concurrency import run_in_threadpool  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402

from . import persist, store  # noqa: E402

from .routers import areas, auth, briefing, places, ranking, recommend, records, uploads, users  # noqa: E402

app = FastAPI(title="먹로그 API", version="0.5.0")

# 저장된 상태가 있으면 불러온다(없으면 시드 데이터로 시작). MUKLOG_DB=""이면 저장하지 않는다.
persist.load()
# 시연 모드: 이미 가입한 사용자까지 모두 서로 팔로우하게 채워 저장한다.
if store.demo_mode():
    store.connect_all_users()
    persist.save()


@app.middleware("http")
async def save_after_write(request: Request, call_next):
    """쓰기 요청이 성공하면 상태를 SQLite에 저장한다(로그인 세션 포함)."""
    response = await call_next(request)
    if request.method in ("POST", "PUT", "PATCH", "DELETE") and response.status_code < 400:
        await run_in_threadpool(persist.save)
    return response


# 업로드 본문 크기를 받는 도중에 제한한다. CORS보다 먼저 추가해 안쪽에 두어야 413 응답에도 CORS 헤더가 붙는다.
app.add_middleware(uploads.UploadSizeLimit)

# Flutter 웹 개발 서버(임의 포트)에서 호출할 수 있도록 허용. 그 밖의 웹 주소(ngrok 시연, 배포 도메인)는
# MUKLOG_CORS_ORIGINS에 쉼표로 정확한 origin을 넣는다. 와일드카드는 쓰지 않는다(ngrok 주소는 누구나 만들 수 있다).
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip().rstrip("/") for o in os.getenv("MUKLOG_CORS_ORIGINS", "").split(",") if o.strip()],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(places.router)
app.include_router(records.router)
app.include_router(recommend.router)
app.include_router(briefing.router)
app.include_router(areas.router)
app.include_router(ranking.router)
app.include_router(uploads.router)

# 업로드한 사진 정적 서빙. POST /uploads 라우트가 먼저 등록되어 있어 업로드 요청과 겹치지 않는다.
uploads.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=uploads.UPLOAD_DIR), name="uploads")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
