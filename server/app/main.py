from pathlib import Path

from dotenv import load_dotenv

# server/.env의 값(네이버 검색 키 등)을 환경변수로 읽는다. 이미 설정된 환경변수가 우선한다.
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

from fastapi import FastAPI  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.staticfiles import StaticFiles  # noqa: E402

from .routers import briefing, places, ranking, recommend, records, uploads, users  # noqa: E402

app = FastAPI(title="먹로그 API", version="0.3.0")

# Flutter 웹 개발 서버(임의 포트)에서 호출할 수 있도록 허용. 배포 시 도메인으로 제한.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(users.router)
app.include_router(places.router)
app.include_router(records.router)
app.include_router(recommend.router)
app.include_router(briefing.router)
app.include_router(ranking.router)
app.include_router(uploads.router)

# 업로드한 사진 정적 서빙. POST /uploads 라우트가 먼저 등록되어 있어 업로드 요청과 겹치지 않는다.
uploads.UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=uploads.UPLOAD_DIR), name="uploads")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
