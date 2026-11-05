from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routers import briefing, places, ranking, recommend, records, users

app = FastAPI(title="먹로그 API", version="0.2.0")

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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
