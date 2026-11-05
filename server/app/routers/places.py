from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query

from .. import store
from ..schemas import Place, Record

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


@router.get("/{place_id}/records")
def place_records(place_id: str) -> list[Record]:
    if place_id not in store.places:
        raise HTTPException(404, "식당을 찾을 수 없습니다")
    return [r for r in store.visible_records(store.ME_ID) if r.place_id == place_id]
