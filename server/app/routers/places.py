from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Response

from .. import naver, store, taste
from ..schemas import Place, PlaceCandidate, PlaceIn, Record

router = APIRouter(prefix="/places", tags=["places"])


def parse_bbox(bbox: str | None) -> tuple[float, float, float, float] | None:
    """'남서위도,남서경도,북동위도,북동경도' 문자열을 파싱한다."""
    if bbox is None:
        return None
    try:
        south, west, north, east = (float(x) for x in bbox.split(","))
    except ValueError:
        raise HTTPException(422, "bbox는 '남서위도,남서경도,북동위도,북동경도' 형식이어야 합니다")
    return south, west, north, east


def in_bbox(p: Place, box: tuple[float, float, float, float] | None) -> bool:
    if box is None:
        return True
    south, west, north, east = box
    return south <= p.lat <= north and west <= p.lng <= east


@router.get("")
def list_places(
    bbox: str | None = None,
    tags: Annotated[list[str] | None, Query()] = None,
    layer: Literal["all", "friends", "mine"] = "all",
) -> list[Place]:
    """지도에 표시할 식당.

    - bbox: 지도 영역으로 자르기. TODO(geo): PostGIS 반경·영역 검색.
    - tags: 하나라도 가진 식당만 (취향 태그 필터).
    - layer: friends면 친구 기록이 있는 곳, mine이면 내 기록이 있는 곳만 (친구 레이어).
    """
    box = parse_bbox(bbox)
    if layer == "all":
        allowed = None
    else:
        authors = {store.ME_ID} if layer == "mine" else set(store.follows.get(store.ME_ID, set()))
        allowed = {r.place_id for r in store.visible_records(store.ME_ID) if r.user_id in authors}

    return [
        p for p in store.places.values()
        if in_bbox(p, box)
        and (not tags or set(tags) & set(p.tags))
        and (allowed is None or p.id in allowed)
    ]


@router.get("/search")
def search_places(
    query: Annotated[str, Query(min_length=1, max_length=50)],
    lat: float | None = None,
    lng: float | None = None,
) -> list[PlaceCandidate]:
    """네이버 지역 검색으로 식당 후보를 찾는다. 이름·주소·좌표만 쓰고 네이버 평점·리뷰는 쓰지 않는다.

    lat·lng를 주면 가까운 순으로 정렬한다. 이미 등록된 식당이면 place_id를 채운다.
    """
    if (lat is None) != (lng is None):
        raise HTTPException(422, "lat과 lng은 함께 보내야 합니다")
    try:
        found = naver.search_local(query.strip())
    except naver.SearchUnavailable as e:
        raise HTTPException(503, str(e))

    candidates = []
    for p in found:
        existing = store.find_place_by_external(p.external_id)
        candidates.append(PlaceCandidate(**p.model_dump(), place_id=existing.id if existing else None))
    if lat is not None and lng is not None:
        candidates.sort(key=lambda c: taste.distance_km(lat, lng, c.lat, c.lng))
    return candidates


@router.post("", status_code=201)
def create_place(data: PlaceIn, response: Response) -> Place:
    """검색 후보를 먹로그 식당으로 등록한다. 이미 있는 external_id면 기존 식당을 200으로 돌려준다."""
    place, created = store.add_place(data)
    if not created:
        response.status_code = 200
    return place


@router.get("/{place_id}/records")
def place_records(place_id: str) -> list[Record]:
    if place_id not in store.places:
        raise HTTPException(404, "식당을 찾을 수 없습니다")
    return [r for r in store.visible_records(store.ME_ID) if r.place_id == place_id]
