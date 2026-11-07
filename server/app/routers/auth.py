from typing import Annotated
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from fastapi import APIRouter, Header, HTTPException, Query
from fastapi.responses import RedirectResponse

from .. import auth, store
from ..auth import CurrentUser
from ..schemas import ExchangeIn, LoginIn, LoginOut

router = APIRouter(prefix="/auth", tags=["auth"])


def _login_out(user_id: str, is_new: bool) -> LoginOut:
    return LoginOut(access_token=auth.create_session(user_id), user=store.users[user_id], is_new=is_new)


def _login_profile(profile: auth.Profile) -> LoginOut:
    user, is_new = store.login_user(profile.provider, profile.provider_user_id, profile.nickname, profile.avatar_url)
    return _login_out(user.id, is_new)


@router.post("/login")
def login(data: LoginIn) -> LoginOut:
    """앱이 각 회사 SDK로 받은 토큰을 검증하고 먹로그 세션 토큰을 준다.

    kakao는 액세스 토큰, google은 ID 토큰.
    네이버는 받지 않는다: 액세스 토큰이 우리 앱에서 발급됐는지 확인할 수 없어서, 다른 앱이 받은 토큰으로
    남의 계정에 로그인할 수 있다. 네이버는 모바일·웹 모두 /auth/naver/start(서버가 우리 키로 코드 교환)를 쓴다.
    """
    if data.provider == "naver":
        raise HTTPException(400, "네이버 로그인은 /auth/naver/start로 진행해 주세요")
    try:
        if data.provider == "kakao":
            profile = auth.verify_kakao(data.token)
        else:
            profile = auth.verify_google(data.token)
    except auth.AuthUnavailable as e:
        raise HTTPException(503, str(e))
    except auth.AuthError as e:
        raise HTTPException(401, str(e))
    return _login_profile(profile)


@router.post("/exchange")
def exchange(data: ExchangeIn) -> LoginOut:
    """네이버 웹 로그인 콜백이 준 1회용 login_code(5분)를 세션 토큰으로 바꾼다."""
    user_id = auth.redeem_login_code(data.login_code, data.code_verifier)
    if user_id is None or user_id not in store.users:
        raise HTTPException(401, "로그인 시간이 지났어요. 다시 로그인해 주세요")
    return _login_out(user_id, is_new=False)


@router.post("/logout", status_code=204)
def logout(_: CurrentUser, authorization: Annotated[str | None, Header()] = None) -> None:
    if authorization:
        auth.revoke_session(authorization.partition(" ")[2].strip())


@router.get("/naver/start")
def naver_start(
    redirect: Annotated[str, Query(max_length=500)],
    code_challenge: Annotated[str, Query(pattern=r"^[A-Za-z0-9_-]{43}$")],
) -> RedirectResponse:
    """네이버 인증 화면으로 보낸다. redirect는 로그인 뒤 돌아갈 앱 주소(허용 목록만).

    code_challenge는 PKCE S256 값(base64url(sha256(verifier)), 43자)으로 웹·모바일 모두 필수다.
    교환할 때 POST /auth/exchange에 code_verifier를 같이 보내야 한다. 이렇게 login_code를 시작한 앱에 묶어서
    - 로그인 CSRF(공격자가 자기 계정으로 시작한 콜백 URL을 피해자에게 열게 해 공격자 계정으로 로그인시키기)와
    - 커스텀 스킴 가로채기(다른 앱이 muklog://를 등록해 login_code를 받기)를 막는다.
    """
    if not auth.allowed_redirect(redirect):
        raise HTTPException(400, "허용되지 않은 앱 주소예요")
    try:
        client_id, _ = auth.naver_keys()
    except auth.AuthUnavailable as e:
        raise HTTPException(503, str(e))
    query = urlencode({
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": f"{auth.public_url()}/auth/naver/callback",
        "state": auth.create_state(redirect, code_challenge),
    })
    return RedirectResponse(f"{auth.NAVER_AUTHORIZE_URL}?{query}", status_code=302)


@router.get("/naver/callback")
def naver_callback(
    state: str = "",
    code: str | None = None,
    error: str | None = None,
) -> RedirectResponse:
    """네이버가 돌려보내는 곳. 사용자를 만들거나 찾은 뒤 앱 주소로 1회용 login_code를 붙여 보낸다.

    세션 토큰은 URL에 싣지 않는다. 앱이 POST /auth/exchange로 바꾼다.
    """
    popped = auth.pop_state(state)
    if popped is None:
        # state가 없거나 만료: 어디로 돌려보낼지 모르므로 오류만 준다(오픈 리다이렉트 방지).
        raise HTTPException(400, "로그인 요청이 만료됐어요. 다시 시도해 주세요")
    redirect, challenge = popped
    if error or not code:
        return RedirectResponse(_with_query(redirect, login_error="네이버 로그인을 취소했어요"), status_code=302)
    try:
        profile = auth.naver_profile(auth.naver_exchange_code(code, state))
    except (auth.AuthError, auth.AuthUnavailable) as e:
        return RedirectResponse(_with_query(redirect, login_error=str(e)), status_code=302)
    user, _ = store.login_user(profile.provider, profile.provider_user_id, profile.nickname, profile.avatar_url)
    return RedirectResponse(_with_query(redirect, login_code=auth.create_login_code(user.id, challenge)), status_code=302)


def _with_query(url: str, **params: str) -> str:
    parts = urlsplit(url)
    query = urlencode([*parse_qsl(parts.query), *params.items()])
    return urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))
