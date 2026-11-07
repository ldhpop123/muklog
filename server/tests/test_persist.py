from fastapi.testclient import TestClient

from app import auth, persist, store
from app.main import app

client = TestClient(app)


def test_state_survives_restart(tmp_path, monkeypatch):
    monkeypatch.setenv("MUKLOG_DB", str(tmp_path / "muklog.db"))
    monkeypatch.setenv("KAKAO_APP_ID", "999")

    import httpx

    class R:
        def __init__(self, body):
            self.status_code, self._body, self.text = 200, body, ""

        def json(self):
            return self._body

    def fake_get(url, headers, timeout):
        if url.endswith("/access_token_info"):
            return R({"app_id": 999})
        return R({"id": 7, "kakao_account": {"profile": {"nickname": "저장친구"}}})

    monkeypatch.setattr(httpx, "get", fake_get)
    login = client.post("/auth/login", json={"provider": "kakao", "token": "t"}).json()
    token, uid = login["access_token"], login["user"]["id"]
    headers = {"Authorization": f"Bearer {token}"}
    taste = {"saltiness": 0.1, "spiciness": 0.2, "ambience": 0.3, "value": 0.4, "cuisine": 0.5}
    client.put("/users/me/taste", json=taste, headers=headers)
    rec = client.post("/records", json={"place_id": "p1", "rating": 5, "memo": "슴슴한 노포"}, headers=headers).json()

    # 서버 재시작 흉내: 메모리를 비우고 DB에서 다시 읽는다.
    store.users.clear()
    store.records.clear()
    store.accounts.clear()
    store.record_attrs.clear()
    auth._sessions.clear()
    assert persist.load() is True

    assert store.users[uid].nickname == "저장친구"
    assert store.users[uid].onboarded is True
    assert any(r.id == rec["id"] for r in store.records)
    assert rec["id"] in store.record_attrs  # 백그라운드 후처리 결과도 저장됨
    assert client.get("/users/me", headers=headers).json()["id"] == uid  # 세션 유지
    again = client.post("/auth/login", json={"provider": "kakao", "token": "t"}).json()
    assert again["user"]["id"] == uid and again["is_new"] is False


def test_logout_is_persisted(tmp_path, monkeypatch):
    monkeypatch.setenv("MUKLOG_DB", str(tmp_path / "muklog.db"))
    token = auth.create_session("me")
    client.post("/auth/logout", headers={"Authorization": f"Bearer {token}"})
    auth._sessions.clear()
    persist.load()
    assert auth.session_user(token) is None


def test_disabled_when_empty(monkeypatch):
    monkeypatch.setenv("MUKLOG_DB", "")
    assert persist.db_path() is None
    persist.save()  # 아무 일도 하지 않는다
    assert persist.load() is False
