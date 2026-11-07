"""소셜 로그인(카카오·네이버·구글)과 먹로그 세션.

- 앱은 각 회사 SDK로 받은 토큰을 POST /auth/login으로 보내고, 서버는 그 회사 API로 검증한 뒤 세션 토큰을 준다.
- 세션 토큰은 서버에 저장하는 무작위 문자열이다(해시로 보관, 30일). 로그아웃하면 바로 무효가 된다.
  세션은 persist.py가 SQLite에 같이 저장해서 서버를 다시 켜도 유지된다.
- 이후 요청은 Authorization: Bearer <세션 토큰>으로 사용자를 식별한다(current_user).
  MUKLOG_DEV_AUTH=1이면 헤더가 없을 때만 시드 사용자 "me"로 본다(로그인 화면 전 개발용).

키(server/.env):
- KAKAO_APP_ID: 카카오 앱 ID. 토큰이 우리 앱에서 발급됐는지 확인한다(다른 앱 토큰으로 로그인하는 것을 막음).
- NAVER_LOGIN_CLIENT_ID, NAVER_LOGIN_CLIENT_SECRET: developers.naver.com "네이버 로그인" 키(검색 API 키와 다름).
- GOOGLE_CLIENT_IDS: 허용할 OAuth 클라이언트 ID들(웹·Android·iOS), 쉼표로 구분.
"""

import base64
import hashlib
import hmac
import logging
import os
import secrets
import threading
import time
from dataclasses import dataclass
from typing import Annotated

import httpx
from fastapi import Depends, Header, HTTPException

from . import store

log = logging.getLogger(__name__)

SESSION_TTL = 30 * 24 * 60 * 60
LOGIN_CODE_TTL = 5 * 60
STATE_TTL = 10 * 60


class AuthError(Exception):
    """토큰 검증 실패. 메시지는 사용자에게 보여 줄 한국어 문장."""


class AuthUnavailable(Exception):
    """서버에 로그인 키가 없음. 메시지는 사용자에게 보여 줄 한국어 문장."""


@dataclass
class Profile:
    provider: str
    provider_user_id: str
    nickname: str | None
    avatar_url: str | None


# ── 세션 ──────────────────────────────────────────────

_lock = threading.Lock()
_sessions: dict[str, tuple[str, float]] = {}  # sha256(토큰) → (user_id, 만료 시각)
# sha256(코드) → (user_id, PKCE code_challenge 또는 None, 만료 시각). 1회용
_login_codes: dict[str, tuple[str, str | None, float]] = {}
# 네이버 state → (앱 redirect 주소, PKCE code_challenge 또는 None, 만료 시각)
_states: dict[str, tuple[str, str | None, float]] = {}


def _digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def create_session(user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    with _lock:
        _sessions[_digest(token)] = (user_id, time.time() + SESSION_TTL)
    return token


def session_user(token: str) -> str | None:
    with _lock:
        hit = _sessions.get(_digest(token))
        if hit is None:
            return None
        if hit[1] < time.time():
            _sessions.pop(_digest(token), None)
            return None
        return hit[0]


def revoke_session(token: str) -> None:
    with _lock:
        _sessions.pop(_digest(token), None)


def pkce_challenge(verifier: str) -> str:
    """PKCE S256: base64url(sha256(verifier)), '=' 없이."""
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()


def create_login_code(user_id: str, challenge: str | None = None) -> str:
    code = secrets.token_urlsafe(24)
    with _lock:
        _login_codes[_digest(code)] = (user_id, challenge, time.time() + LOGIN_CODE_TTL)
    return code


def redeem_login_code(code: str, verifier: str | None = None) -> str | None:
    """1회용. 한 번 쓰면(실패해도) 지운다. challenge가 묶여 있으면 맞는 code_verifier가 있어야 한다(PKCE)."""
    with _lock:
        hit = _login_codes.pop(_digest(code), None)
    if hit is None or hit[2] < time.time():
        return None
    user_id, challenge, _ = hit
    if challenge is not None and (verifier is None or not hmac.compare_digest(pkce_challenge(verifier), challenge)):
        return None
    return user_id


def create_state(redirect: str, challenge: str | None = None) -> str:
    state = secrets.token_urlsafe(24)
    now = time.time()
    with _lock:
        for k in [k for k, (_, _, t) in _states.items() if t < now]:
            _states.pop(k, None)
        _states[state] = (redirect, challenge, now + STATE_TTL)
    return state


def pop_state(state: str) -> tuple[str, str | None] | None:
    """(앱 redirect 주소, code_challenge). 없거나 만료면 None. 1회용."""
    with _lock:
        hit = _states.pop(state, None)
    if hit is None or hit[2] < time.time():
        return None
    return hit[0], hit[1]


def current_user(authorization: Annotated[str | None, Header()] = None) -> str:
    """요청한 사용자 id. 헤더가 없거나 무효면 401."""
    if authorization is None:
        if os.getenv("MUKLOG_DEV_AUTH") == "1":
            return store.ME_ID
        raise HTTPException(401, "로그인이 필요해요", headers={"WWW-Authenticate": "Bearer"})
    scheme, _, token = authorization.partition(" ")
    user_id = session_user(token.strip()) if scheme.lower() == "bearer" and token.strip() else None
    if user_id is None or user_id not in store.users:
        raise HTTPException(401, "로그인이 만료됐어요. 다시 로그인해 주세요", headers={"WWW-Authenticate": "Bearer"})
    return user_id


CurrentUser = Annotated[str, Depends(current_user)]


# ── 회사별 토큰 검증 ──────────────────────────────────

def _get_json(url: str, token: str) -> dict:
    try:
        res = httpx.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=5.0)
    except httpx.HTTPError as e:
        log.warning("로그인 검증 연결 실패 (%s): %s", url, e)
        raise AuthError("로그인 확인이 잠시 안 돼요. 조금 뒤에 다시 시도해 주세요")
    if res.status_code in (400, 401, 403):
        raise AuthError("로그인 정보가 올바르지 않아요. 다시 로그인해 주세요")
    if res.status_code != 200:
        log.warning("로그인 검증 실패 (%s %s): %s", url, res.status_code, res.text[:200])
        raise AuthError("로그인 확인이 잠시 안 돼요. 조금 뒤에 다시 시도해 주세요")
    return res.json()


def verify_kakao(access_token: str) -> Profile:
    app_id = os.getenv("KAKAO_APP_ID")
    if not app_id:
        raise AuthUnavailable("카카오 로그인 설정이 아직 안 되어 있어요")
    # 다른 앱에서 받은 토큰으로 로그인하지 못하게 발급 앱을 확인한다.
    info = _get_json("https://kapi.kakao.com/v1/user/access_token_info", access_token)
    if str(info.get("app_id")) != app_id:
        raise AuthError("로그인 정보가 올바르지 않아요. 다시 로그인해 주세요")
    me = _get_json("https://kapi.kakao.com/v2/user/me", access_token)
    profile = (me.get("kakao_account") or {}).get("profile") or {}
    props = me.get("properties") or {}
    return Profile(
        provider="kakao",
        provider_user_id=str(me["id"]),
        nickname=profile.get("nickname") or props.get("nickname"),
        avatar_url=profile.get("profile_image_url") or props.get("profile_image"),
    )


def naver_profile(access_token: str) -> Profile:
    data = _get_json("https://openapi.naver.com/v1/nid/me", access_token)
    if data.get("resultcode") != "00" or "response" not in data:
        raise AuthError("로그인 정보가 올바르지 않아요. 다시 로그인해 주세요")
    r = data["response"]
    return Profile(provider="naver", provider_user_id=str(r["id"]),
                   nickname=r.get("nickname") or r.get("name"), avatar_url=r.get("profile_image"))


def verify_google(id_token_str: str) -> Profile:
    client_ids = [c.strip() for c in os.getenv("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]
    if not client_ids:
        raise AuthUnavailable("구글 로그인 설정이 아직 안 되어 있어요")
    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    try:
        # 서명·만료·발급자(accounts.google.com)·aud(우리 클라이언트 ID)를 모두 확인한다.
        claims = id_token.verify_oauth2_token(id_token_str, google_requests.Request(), audience=client_ids)
    except ValueError as e:
        log.info("구글 ID 토큰 검증 실패: %s", e)
        raise AuthError("로그인 정보가 올바르지 않아요. 다시 로그인해 주세요")
    return Profile(provider="google", provider_user_id=str(claims["sub"]),
                   nickname=claims.get("name"), avatar_url=claims.get("picture"))


# ── 네이버 웹 로그인(서버 리다이렉트) ─────────────────

NAVER_AUTHORIZE_URL = "https://nid.naver.com/oauth2.0/authorize"
NAVER_TOKEN_URL = "https://nid.naver.com/oauth2.0/token"


def naver_keys() -> tuple[str, str]:
    client_id = os.getenv("NAVER_LOGIN_CLIENT_ID")
    client_secret = os.getenv("NAVER_LOGIN_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise AuthUnavailable("네이버 로그인 설정이 아직 안 되어 있어요")
    return client_id, client_secret


def naver_exchange_code(code: str, state: str) -> str:
    """인가 코드 → 액세스 토큰. Client Secret은 서버에만 있다."""
    client_id, client_secret = naver_keys()
    try:
        res = httpx.post(NAVER_TOKEN_URL, data={
            "grant_type": "authorization_code", "client_id": client_id, "client_secret": client_secret,
            "code": code, "state": state,
        }, timeout=5.0)
        data = res.json()
    except (httpx.HTTPError, ValueError) as e:
        log.warning("네이버 토큰 교환 실패: %s", e)
        raise AuthError("네이버 로그인이 잠시 안 돼요. 조금 뒤에 다시 시도해 주세요")
    token = data.get("access_token")
    if not token:
        log.warning("네이버 토큰 교환 거절: %s", data.get("error_description") or data.get("error"))
        raise AuthError("네이버 로그인에 실패했어요. 다시 시도해 주세요")
    return token


def public_url() -> str:
    """이 서버의 외부 주소. 네이버 콘솔의 Callback URL은 {public_url}/auth/naver/callback으로 등록한다."""
    return os.getenv("MUKLOG_PUBLIC_URL", "http://localhost:8010").rstrip("/")


DEFAULT_LOGIN_REDIRECTS = "http://localhost:8765,http://127.0.0.1:8765,muklog://auth"
_UNSAFE_SCHEMES = {"javascript", "data", "file", "vbscript", "about", "blob"}


def allowed_redirect(url: str) -> bool:
    """앱 주소 허용 목록(MUKLOG_LOGIN_REDIRECTS, 쉼표 구분)과 scheme·host·port가 정확히 같아야 한다.

    웹은 http://localhost:8765 같은 origin, 모바일은 muklog://auth 같은 커스텀 스킴 + 호스트. 경로·# 부분은 자유.
    """
    from urllib.parse import urlsplit

    allowed = os.getenv("MUKLOG_LOGIN_REDIRECTS", DEFAULT_LOGIN_REDIRECTS)
    origins = {o.strip().rstrip("/") for o in allowed.split(",") if o.strip()}
    try:
        parts = urlsplit(url)
        _ = parts.port  # 잘못된 포트면 ValueError
    except ValueError:
        return False
    if not parts.scheme or parts.scheme.lower() in _UNSAFE_SCHEMES or not parts.netloc:
        return False
    if parts.username or parts.password:
        return False
    return f"{parts.scheme}://{parts.netloc}" in origins
