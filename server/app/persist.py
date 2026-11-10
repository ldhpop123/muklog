"""SQLite 저장. 서버를 다시 켜도 가입자·로그인·기록·식당·신뢰 온도가 남게 한다.

요청 처리는 지금처럼 store의 메모리 자료구조로 하고, 데이터가 바뀌면(쓰기 요청 성공, 기록 후처리 완료)
전체 상태를 한 트랜잭션으로 SQLite에 덮어쓴다. 켤 때 DB에 데이터가 있으면 그것으로 메모리를 채운다.
시연 규모(사용자·기록 수천 건 이하)에서는 이 방식이 가장 단순하다.
TODO(db): 사용자가 늘면 README 10장 스키마로 PostgreSQL에 행 단위로 쓰도록 바꾼다.

경로는 MUKLOG_DB(기본 server/data/muklog.db). 빈 문자열이면 저장하지 않는다(테스트 기본값).
"""

import json
import logging
import os
import sqlite3
import threading
from datetime import datetime
from pathlib import Path
from typing import Any

from . import auth, store
from .schemas import Attributes, Dislike, Place, Record, TasteVector, User

log = logging.getLogger(__name__)

DEFAULT_PATH = Path(__file__).resolve().parents[1] / "data" / "muklog.db"
_save_lock = threading.Lock()

_SCHEMA = """
CREATE TABLE IF NOT EXISTS entities (
    kind TEXT NOT NULL,
    id   TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (kind, id)
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""


def db_path() -> Path | None:
    raw = os.getenv("MUKLOG_DB")
    if raw is None:
        return DEFAULT_PATH
    return Path(raw) if raw.strip() else None


def _connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.executescript(_SCHEMA)
    return conn


def _snapshot() -> list[tuple[str, str, str]]:
    """메모리 상태 → (kind, id, json) 행 목록. 락 안에서 부른다."""
    rows: list[tuple[str, str, str]] = []

    def add(kind: str, key: str, value: object) -> None:
        rows.append((kind, key, json.dumps(value, ensure_ascii=False, default=str)))

    for uid, u in store.users.items():
        add("user", uid, u.model_dump(mode="json"))
    for (provider, pid), uid in store.accounts.items():
        add("account", f"{provider}|{pid}", {"provider": provider, "provider_user_id": pid, "user_id": uid})
    for uid, ids in store.follows.items():
        add("follows", uid, sorted(ids))
    for uid, items in store.dislikes.items():
        add("dislikes", uid, [d.model_dump(mode="json") for d in items])
    for uid, v in store.onboarding.items():
        add("onboarding", uid, v.model_dump(mode="json"))
    for uid, t in store.base_temps.items():
        add("base_temp", uid, t)
    for pid, p in store.places.items():
        add("place", pid, p.model_dump(mode="json"))
    for pid, v in store.place_priors.items():
        add("place_prior", pid, v.model_dump(mode="json"))
    for i, r in enumerate(store.records):
        add("record", f"{i:08d}", r.model_dump(mode="json"))
    for rid, a in store.record_attrs.items():
        add("record_attrs", rid, a.model_dump(mode="json"))
    for i, e in enumerate(store.trust_events):
        add("trust_event", f"{i:08d}", e.model_dump(mode="json"))
    now = datetime.now().timestamp()
    for digest, (uid, expires) in auth._sessions.items():
        if expires > now:
            add("session", digest, {"user_id": uid, "expires": expires})
    return rows


def save() -> None:
    """전체 상태를 SQLite에 덮어쓴다. 저장이 꺼져 있으면 아무것도 하지 않는다."""
    path = db_path()
    if path is None:
        return
    with _save_lock:
        with store.lock, auth._lock:
            rows = _snapshot()
        try:
            conn = _connect(path)
            with conn:
                conn.execute("DELETE FROM entities")
                conn.executemany("INSERT INTO entities (kind, id, data) VALUES (?, ?, ?)", rows)
                conn.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('saved_at', ?)",
                             (datetime.now().isoformat(timespec="seconds"),))
            conn.close()
        except sqlite3.Error:
            log.exception("SQLite 저장 실패: %s", path)


def load() -> bool:
    """DB에 저장된 상태가 있으면 메모리를 그것으로 바꾼다. 불러왔으면 True, DB가 비어 있으면 False(시드 유지)."""
    path = db_path()
    if path is None or not path.exists():
        return False
    conn = _connect(path)
    try:
        rows = conn.execute("SELECT kind, id, data FROM entities ORDER BY kind, id").fetchall()
    finally:
        conn.close()
    if not rows:
        return False

    by_kind: dict[str, list[tuple[str, Any]]] = {}
    for kind, key, data in rows:
        by_kind.setdefault(kind, []).append((key, json.loads(data)))

    def items(kind: str) -> list[tuple[str, Any]]:
        return by_kind.get(kind, [])

    with store.lock, auth._lock:
        _replace(store.users, {k: User.model_validate(v) for k, v in items("user")})
        _replace(store.accounts, {(v["provider"], v["provider_user_id"]): v["user_id"] for _, v in items("account")})
        _replace(store.follows, {k: set(v) for k, v in items("follows")})
        _replace(store.dislikes, {k: [Dislike.model_validate(d) for d in v] for k, v in items("dislikes")})
        _replace(store.onboarding, {k: TasteVector.model_validate(v) for k, v in items("onboarding")})
        _replace(store.base_temps, {k: float(v) for k, v in items("base_temp")})
        _replace(store.places, {k: Place.model_validate(v) for k, v in items("place")})
        _replace(store.place_priors, {k: TasteVector.model_validate(v) for k, v in items("place_prior")})
        store.records[:] = [Record.model_validate(v) for _, v in items("record")]
        _replace(store.record_attrs, {k: Attributes.model_validate(v) for k, v in items("record_attrs")})
        store.trust_events[:] = [store.TrustEvent.model_validate(v) for _, v in items("trust_event")]
        now = datetime.now().timestamp()
        _replace(auth._sessions, {k: (v["user_id"], v["expires"]) for k, v in items("session") if v["expires"] > now})
    log.info("SQLite에서 상태를 불러왔습니다: 사용자 %d명, 기록 %d건", len(store.users), len(store.records))
    return True


def _replace(target: dict, values: dict) -> None:
    """다른 모듈이 같은 dict 객체를 참조하고 있을 수 있어 새로 만들지 않고 내용을 바꾼다."""
    target.clear()
    target.update(values)
