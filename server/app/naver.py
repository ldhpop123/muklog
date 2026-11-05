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

import httpx
from pydantic import BaseModel

log = logging.getLogger(__name__)

LOCAL_SEARCH_URL = "https://naverapihub.apigw.ntruss.com/search/v1/local"
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
    return list({p.external_id: p for p in places}.values())
