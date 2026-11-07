import httpx
import pytest
from fastapi.testclient import TestClient

from app import auth, store
from app.main import app

# 네이버 로그인 쿠키가 콜백 주소(기본 public_url)에 묶이므로 같은 주소로 요청한다.
client = TestClient(app, base_url="http://localhost:8010")


class _R:
    def __init__(self, status, body):
        self.status_code = status
        self._body = body
        self.text = str(body)

    def json(self):
        return self._body


KAKAO_ME = {"id": 4242, "kakao_account": {"profile": {"nickname": "카카오친구", "profile_image_url": "https://k/p.jpg"}}}


@pytest.fixture
def strict(monkeypatch):
    """헤더 없는 요청을 401로 만드는 실제 모드."""
    monkeypatch.delenv("MUKLOG_DEV_AUTH", raising=False)


def _kakao(monkeypatch, app_id="999"):
    monkeypatch.setenv("KAKAO_APP_ID", "999")

    def fake_get(url, headers, timeout):
        if headers["Authorization"] != "Bearer good":
            return _R(401, {"msg": "invalid"})
        if url.endswith("/access_token_info"):
            return _R(200, {"id": 4242, "app_id": int(app_id)})
        return _R(200, KAKAO_ME)

    monkeypatch.setattr(httpx, "get", fake_get)


def test_requests_without_token_are_401(strict):
    for path in ("/users/me", "/recommend", "/places", "/areas?lat=37.55&lng=126.92"):
        assert client.get(path).status_code == 401, path
    assert client.get("/users/me", headers={"Authorization": "Bearer nope"}).status_code == 401
    assert client.get("/health").status_code == 200


def test_kakao_login_creates_user_and_session(strict, monkeypatch):
    _kakao(monkeypatch)
    res = client.post("/auth/login", json={"provider": "kakao", "token": "good"})
    assert res.status_code == 200
    body = res.json()
    assert body["is_new"] is True
    assert body["user"]["nickname"] == "카카오친구"
    assert body["user"]["onboarded"] is False
    headers = {"Authorization": f"Bearer {body['access_token']}"}

    me = client.get("/users/me", headers=headers).json()
    assert me["id"] == body["user"]["id"]
    assert client.get("/users/me/friends", headers=headers).json() == []

    # 다시 로그인하면 같은 사용자, is_new=false
    again = client.post("/auth/login", json={"provider": "kakao", "token": "good"}).json()
    assert again["user"]["id"] == me["id"] and again["is_new"] is False

    # 온보딩 저장 후 onboarded=true
    taste = {"saltiness": 0.1, "spiciness": 0.2, "ambience": 0.3, "value": 0.4, "cuisine": 0.5}
    assert client.put("/users/me/taste", json=taste, headers=headers).json()["onboarded"] is True

    # 로그아웃하면 그 토큰은 무효
    assert client.post("/auth/logout", headers=headers).status_code == 204
    assert client.get("/users/me", headers=headers).status_code == 401


def test_kakao_token_from_other_app_is_rejected(strict, monkeypatch):
    _kakao(monkeypatch, app_id="111")
    res = client.post("/auth/login", json={"provider": "kakao", "token": "good"})
    assert res.status_code == 401
    assert "다시 로그인" in res.json()["detail"]


def test_bad_kakao_token_and_missing_keys(strict, monkeypatch):
    _kakao(monkeypatch)
    assert client.post("/auth/login", json={"provider": "kakao", "token": "bad"}).status_code == 401
    monkeypatch.delenv("KAKAO_APP_ID")
    assert client.post("/auth/login", json={"provider": "kakao", "token": "good"}).status_code == 503
    monkeypatch.delenv("GOOGLE_CLIENT_IDS", raising=False)
    assert client.post("/auth/login", json={"provider": "google", "token": "x"}).status_code == 503


def test_google_login_checks_audience(strict, monkeypatch):
    from google.oauth2 import id_token

    monkeypatch.setenv("GOOGLE_CLIENT_IDS", "web.apps.googleusercontent.com, ios.apps.googleusercontent.com")
    seen = {}

    def fake_verify(token, request, audience):
        seen["audience"] = audience
        if token != "valid":
            raise ValueError("bad signature")
        return {"sub": "g-1", "name": "구글친구", "picture": "https://g/p.jpg"}

    monkeypatch.setattr(id_token, "verify_oauth2_token", fake_verify)
    ok = client.post("/auth/login", json={"provider": "google", "token": "valid"})
    assert ok.status_code == 200 and ok.json()["user"]["nickname"] == "구글친구"
    assert seen["audience"] == ["web.apps.googleusercontent.com", "ios.apps.googleusercontent.com"]
    assert client.post("/auth/login", json={"provider": "google", "token": "forged"}).status_code == 401


def test_demo_mode_connects_everyone(strict, monkeypatch):
    monkeypatch.setenv("MUKLOG_DEMO", "1")
    _kakao(monkeypatch)
    first = client.post("/auth/login", json={"provider": "kakao", "token": "good"}).json()
    friends = client.get("/users/me/friends", headers={"Authorization": f"Bearer {first['access_token']}"}).json()
    assert {f["id"] for f in friends} == set(store.users) - {first["user"]["id"]}

    # 두 번째 가입자와 첫 가입자가 서로 팔로우한다.
    second, _ = store.login_user("google", "g-2", "구글친구", None)
    assert second.id in store.follows[first["user"]["id"]]
    assert first["user"]["id"] in store.follows[second.id]
    assert second.id in store.follows["u1"]


def test_connect_all_users_backfills():
    store.follows.clear()
    store.connect_all_users()
    assert all(store.follows[u] == set(store.users) - {u} for u in store.users)


def test_naver_web_flow(strict, monkeypatch):
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    monkeypatch.setenv("MUKLOG_PUBLIC_URL", "http://localhost:8010")

    import secrets

    verifier = secrets.token_urlsafe(48)
    no_pkce = client.get("/auth/naver/start", params={"redirect": "http://localhost:8765/"}, follow_redirects=False)
    assert no_pkce.status_code == 422
    start = client.get("/auth/naver/start", params={"redirect": "http://localhost:8765/#/login",
                                                    "code_challenge": auth.pkce_challenge(verifier)},
                       follow_redirects=False)
    assert start.status_code == 302
    location = httpx.URL(start.headers["location"])
    assert location.host == "nid.naver.com"
    assert location.params["redirect_uri"] == "http://localhost:8010/auth/naver/callback"
    state = location.params["state"]

    monkeypatch.setattr(httpx, "post", lambda url, data, timeout: _R(200, {"access_token": "nat"}))
    monkeypatch.setattr(httpx, "get", lambda url, headers, timeout: _R(200, {
        "resultcode": "00", "response": {"id": "n-1", "nickname": "네이버친구", "profile_image": None}}))
    cb = client.get("/auth/naver/callback", params={"code": "c", "state": state}, follow_redirects=False)
    assert cb.status_code == 302
    back = httpx.URL(cb.headers["location"])
    assert back.host == "localhost" and back.port == 8765
    code = back.params["login_code"]
    assert "access_token" not in str(back)

    ex = client.post("/auth/exchange", json={"login_code": code, "code_verifier": verifier})
    assert ex.status_code == 200 and ex.json()["user"]["nickname"] == "네이버친구"
    # 1회용
    assert client.post("/auth/exchange", json={"login_code": code, "code_verifier": verifier}).status_code == 401
    # state 재사용 불가
    again = client.get("/auth/naver/callback", params={"code": "c", "state": state}, follow_redirects=False)
    assert again.status_code == 400


def test_naver_start_rejects_open_redirect(monkeypatch):
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    for bad in ("https://evil.example/", "http://localhost:8765@evil.example/", "javascript:alert(1)",
                "http://localhost:9999/", "muklog://evil", "evil://auth", "muklog://auth:1@x",
                "http://localhost:8765:bad/"):
        res = client.get("/auth/naver/start", params={"redirect": bad, "code_challenge": "A" * 43},
                         follow_redirects=False)
        assert res.status_code == 400, bad


def test_naver_cancel_returns_error_to_app(monkeypatch):
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    state = auth.create_state("http://127.0.0.1:8765/", "A" * 43)
    cb = client.get("/auth/naver/callback", params={"state": state, "error": "access_denied"},
                    follow_redirects=False)
    assert "login_error" in httpx.URL(cb.headers["location"]).params


def test_dev_auth_header_still_validated():
    # DEV_AUTH 모드에서도 헤더를 보냈다면 검증한다.
    assert client.get("/users/me").json()["id"] == store.ME_ID
    assert client.get("/users/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_naver_access_token_login_is_refused():
    res = client.post("/auth/login", json={"provider": "naver", "token": "anything"})
    assert res.status_code == 400
    assert "/auth/naver/start" in res.json()["detail"]


def test_naver_app_flow_requires_pkce(monkeypatch):
    import secrets

    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    no_pkce = client.get("/auth/naver/start", params={"redirect": "muklog://auth"}, follow_redirects=False)
    assert no_pkce.status_code == 422

    verifier = secrets.token_urlsafe(48)
    challenge = auth.pkce_challenge(verifier)
    start = client.get("/auth/naver/start", params={"redirect": "muklog://auth", "code_challenge": challenge},
                       follow_redirects=False)
    assert start.status_code == 302
    state = httpx.URL(start.headers["location"]).params["state"]

    monkeypatch.setattr(httpx, "post", lambda url, data, timeout: _R(200, {"access_token": "nat"}))
    monkeypatch.setattr(httpx, "get", lambda url, headers, timeout: _R(200, {
        "resultcode": "00", "response": {"id": "n-app", "nickname": "앱친구"}}))
    cb = client.get("/auth/naver/callback", params={"code": "c", "state": state}, follow_redirects=False)
    location = cb.headers["location"]
    assert location.startswith("muklog://auth?login_code=")
    code = httpx.URL(location).params["login_code"]

    # 가로챈 코드(또는 공격자가 피해자에게 넘긴 코드)는 다른 verifier로 교환할 수 없다. 실패하면 코드도 사라진다.
    attacker = secrets.token_urlsafe(48)
    assert client.post("/auth/exchange", json={"login_code": code, "code_verifier": attacker}).status_code == 401
    assert client.post("/auth/exchange", json={"login_code": code, "code_verifier": verifier}).status_code == 401


def test_naver_app_flow_exchange_with_verifier(monkeypatch):
    import secrets

    verifier = secrets.token_urlsafe(48)
    code = auth.create_login_code("me", auth.pkce_challenge(verifier))
    wrong = secrets.token_urlsafe(48)
    assert client.post("/auth/exchange", json={"login_code": code, "code_verifier": wrong}).status_code == 401
    code = auth.create_login_code("me", auth.pkce_challenge(verifier))
    ok = client.post("/auth/exchange", json={"login_code": code, "code_verifier": verifier})
    assert ok.status_code == 200 and ok.json()["user"]["id"] == "me"


def test_naver_callback_requires_browser_that_started(monkeypatch):
    """공격자가 자기 challenge로 시작한 네이버 링크를 피해자가 열어도 login_code가 나가지 않는다."""
    import secrets

    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    attacker = TestClient(app, base_url="http://localhost:8010")
    victim = TestClient(app, base_url="http://localhost:8010")
    challenge = auth.pkce_challenge(secrets.token_urlsafe(48))
    start = attacker.get("/auth/naver/start", params={"redirect": "muklog://auth", "code_challenge": challenge},
                         follow_redirects=False)
    assert "muklog_naver_state" in start.headers["set-cookie"]
    assert "HttpOnly" in start.headers["set-cookie"]
    state = httpx.URL(start.headers["location"]).params["state"]

    calls = []
    monkeypatch.setattr(httpx, "post", lambda url, data, timeout: calls.append(url) or _R(200, {"access_token": "nat"}))
    cb = victim.get("/auth/naver/callback", params={"code": "c", "state": state}, follow_redirects=False)
    back = httpx.URL(cb.headers["location"])
    assert "login_code" not in back.params and "login_error" in back.params
    assert calls == []  # 네이버 코드도 교환하지 않는다
    # state는 이미 소모돼서 공격자 브라우저로도 다시 쓸 수 없다.
    assert attacker.get("/auth/naver/callback", params={"code": "c", "state": state},
                        follow_redirects=False).status_code == 400


def test_naver_start_moves_to_public_url(monkeypatch):
    """다른 주소(예: ngrok)로 시작하면 쿠키를 콜백 주소에 심도록 public_url에서 다시 시작한다."""
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_ID", "nid")
    monkeypatch.setenv("NAVER_LOGIN_CLIENT_SECRET", "nsecret")
    other = TestClient(app, base_url="http://127.0.0.1:8010")
    params = {"redirect": "muklog://auth", "code_challenge": "A" * 43}
    res = other.get("/auth/naver/start", params=params, follow_redirects=False)
    location = httpx.URL(res.headers["location"])
    assert res.status_code == 302 and "set-cookie" not in res.headers
    assert (location.host, location.port, location.path) == ("localhost", 8010, "/auth/naver/start")
    assert dict(location.params) == params
