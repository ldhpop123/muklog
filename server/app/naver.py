"""NAVER API HUB(네이버 클라우드) 지역 검색 연동. 식당 이름·주소·좌표만 가져온다.

문서: https://api.ncloud-docs.com/docs/naver-api-hub-search-local
네이버 평점·리뷰는 가져오지 않는다("네이버 추천 배제" 원칙). 키는 server/.env 또는 환경변수의
NAVER_SEARCH_CLIENT_ID, NAVER_SEARCH_CLIENT_SECRET에 둔다
(NCP 콘솔 > Application Services > NAVER API HUB > Application 등록에서 발급. 기존 개발자센터 키는 쓸 수 없다).
"""

import hashlib
import html
import logging
import os
import re
import threading
import time

import httpx
from pydantic import BaseModel

log = logging.getLogger(__name__)

LOCAL_SEARCH_URL = "https://naverapihub.apigw.ntruss.com/search/v1/local"
# NCP Maps Reverse Geocoding. 문서: https://api.ncloud-docs.com/docs/application-maps-reversegeocoding
REVERSE_GEOCODE_URL = "https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc"
MAX_RESULTS = 5  # 지역 검색 API가 한 번에 주는 최대 개수 (기본값은 1이라 꼭 보낸다)


class SearchUnavailable(Exception):
    """키가 없거나 네이버 호출이 실패했을 때. 메시지는 사용자에게 그대로 보여 줄 한국어 문장."""


class NaverPlace(BaseModel):
    external_id: str
    name: str
    category: str
    address: str
    lat: float
    lng: float


_TAG = re.compile(r"<[^>]+>")


def _clean(text: str) -> str:
    """제목의 <b> 강조 태그와 HTML 엔티티(&amp; 등)를 없앤다."""
    return html.unescape(_TAG.sub("", text)).strip()


def _external_id(name: str, address: str) -> str:
    """지역 검색 결과에는 고유 ID가 없어서 이름 + 주소로 만든다. 같은 가게면 항상 같은 값."""
    digest = hashlib.sha1(f"{name}|{address}".encode()).hexdigest()[:16]
    return f"naver:{digest}"


def parse_item(item: dict) -> NaverPlace | None:
    """검색 결과 한 건을 변환한다.

    mapx·mapy는 WGS84 경도·위도다. 문서에 단위가 없어서, 10^7을 곱한 정수(예 "1269205000")와
    소수(예 "126.9205")를 모두 받는다. 180보다 크면 10^7로 나눈다.
    """
    try:
        lng = _degrees(item["mapx"])
        lat = _degrees(item["mapy"])
    except (KeyError, TypeError, ValueError):
        return None
    name = _clean(item.get("title", ""))
    # 지번 주소를 먼저 쓴다. 동 이름이 들어 있어 지역(area)을 정하기 쉽다.
    address = item.get("address") or item.get("roadAddress") or ""
    if not name or not (33 <= lat <= 39 and 124 <= lng <= 132):  # 국내 좌표가 아니면 버린다
        return None
    category = (item.get("category") or "").split(">")[-1].strip() or "기타"
    return NaverPlace(
        external_id=_external_id(name, address), name=name, category=category, address=address, lat=lat, lng=lng
    )


def _degrees(raw: str | float) -> float:
    value = float(raw)
    return value / 1e7 if abs(value) > 180 else value


def search_local(query: str) -> list[NaverPlace]:
    client_id = os.getenv("NAVER_SEARCH_CLIENT_ID")
    client_secret = os.getenv("NAVER_SEARCH_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise SearchUnavailable("식당 검색 설정이 아직 안 되어 있어요. 서버에 네이버 검색 API 키를 넣어 주세요.")
    try:
        res = httpx.get(
            LOCAL_SEARCH_URL,
            params={"query": query, "display": MAX_RESULTS, "format": "json"},
            headers={"X-NCP-APIGW-API-KEY-ID": client_id, "X-NCP-APIGW-API-KEY": client_secret},
            timeout=5.0,
        )
        res.raise_for_status()
    except httpx.HTTPStatusError as e:
        log.warning("네이버 지역 검색 실패 (%s): %s", e.response.status_code, e.response.text[:200])
        if e.response.status_code in (401, 403):
            raise SearchUnavailable("네이버 검색 API 키가 올바르지 않아요. 서버 설정을 확인해 주세요.")
        raise SearchUnavailable("식당 검색이 잠시 안 돼요. 조금 뒤에 다시 시도해 주세요.")
    except httpx.HTTPError as e:
        log.warning("네이버 지역 검색 연결 실패: %s", e)
        raise SearchUnavailable("식당 검색이 잠시 안 돼요. 조금 뒤에 다시 시도해 주세요.")

    places = [p for item in res.json().get("items", []) if (p := parse_item(item))]
    # 같은 가게가 두 번 나오는 경우를 합친다.
    unique = list({p.external_id: p for p in places}.values())
    _remember(unique)
    return unique


# 서버가 직접 받은 검색 결과. 식당 등록(POST /places)은 이 안에 있는 후보만 받아서,
# 클라이언트가 이름·좌표·external_id를 지어내 식당을 만들지 못하게 한다.
_SEEN_TTL = 60 * 60
_SEEN_MAX = 2000
_seen: dict[str, tuple[NaverPlace, float]] = {}
_seen_lock = threading.Lock()


def _remember(places: list[NaverPlace]) -> None:
    now = time.monotonic()
    with _seen_lock:
        if len(_seen) + len(places) > _SEEN_MAX:
            for key in [k for k, (_, t) in _seen.items() if now - t > _SEEN_TTL] or list(_seen)[: len(places)]:
                _seen.pop(key, None)
        for p in places:
            _seen[p.external_id] = (p, now)


def recall(external_id: str) -> NaverPlace | None:
    """최근 1시간 안에 이 서버가 검색해서 돌려준 후보면 그 값을, 아니면 None."""
    with _seen_lock:
        hit = _seen.get(external_id)
    if hit is None or time.monotonic() - hit[1] > _SEEN_TTL:
        return None
    return hit[0]


# 검색어에 이미 지역이 들어 있는지 보는 단어. "서교동 칼국수", "홍대 국밥", "합정역 파스타" 같은 경우.
_REGION_SUFFIX = re.compile(r"\S+(동|구|역|시|군|읍|면|로|길)$")
_REGION_WORDS = ("홍대", "연남", "상수", "합정", "망원", "신촌", "이태원", "성수", "강남", "건대", "종로", "을지로")


def has_region(query: str) -> bool:
    return any(_REGION_SUFFIX.match(t) or t in _REGION_WORDS for t in query.split())


def _reverse(lat: float, lng: float) -> dict[str, str]:
    """좌표 → {"legalcode": 법정동, "admcode": 행정동}. 키가 없거나 실패하면 빈 dict.

    키는 NAVER_MAP_CLIENT_ID, NAVER_MAP_CLIENT_SECRET (앱 지도와 같은 NCP Maps 애플리케이션).
    """
    client_id = os.getenv("NAVER_MAP_CLIENT_ID")
    client_secret = os.getenv("NAVER_MAP_CLIENT_SECRET")
    if not client_id or not client_secret:
        return {}
    try:
        res = httpx.get(
            REVERSE_GEOCODE_URL,
            params={"coords": f"{lng},{lat}", "orders": "legalcode,admcode", "output": "json"},
            headers={"x-ncp-apigw-api-key-id": client_id, "x-ncp-apigw-api-key": client_secret},
            timeout=3.0,
        )
        res.raise_for_status()
    except httpx.HTTPStatusError as e:
        log.warning("역지오코딩 실패 (%s): %s", e.response.status_code, e.response.text[:200])
        return {}
    except httpx.HTTPError as e:
        log.warning("역지오코딩 연결 실패: %s", e)
        return {}
    names = {}
    for result in res.json().get("results", []):
        name = result.get("region", {}).get("area3", {}).get("name")
        if name and result.get("name") in ("legalcode", "admcode"):
            names[result["name"]] = name
    return names


def reverse_geocode(lat: float, lng: float) -> str | None:
    """좌표 → 법정동 이름(예 "서교동"). 검색어에 붙이는 용도. 실패하면 None."""
    names = _reverse(lat, lng)
    return names.get("legalcode") or names.get("admcode")


def admin_dong(lat: float, lng: float) -> str | None:
    """좌표 → 행정동 이름(예 "숭인1동"). 동네 브리핑 단위. 실패하면 None."""
    return _reverse(lat, lng).get("admcode")
