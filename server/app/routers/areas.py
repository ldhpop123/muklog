from collections import Counter
from typing import Annotated

from fastapi import APIRouter, Query

from .. import areas, naver, store
from ..schemas import AreaSummary

router = APIRouter(prefix="/areas", tags=["areas"])

AREA_WITHIN_KM = 3.0  # 이보다 먼 상권은 주변으로 보지 않는다
DONG_FIRST_KM = 1.0  # 이 안에 상권이 없으면 행정동을 맨 앞에 둔다


@router.get("")
def nearby_areas(
    lat: Annotated[float, Query(ge=-90, le=90)],
    lng: Annotated[float, Query(ge=-180, le=180)],
    limit: Annotated[int, Query(ge=1, le=30)] = 5,
) -> list[AreaSummary]:
    """지도 가운데 주변의 브리핑 단위. 3km 안 상권(가까운 순) + 그 좌표의 행정동 하나.

    - 1km 안에 상권이 없으면 행정동이 맨 앞, 있으면 맨 뒤. 전체 개수는 limit 이하.
    - 행정동은 역지오코딩 키(NAVER_MAP_CLIENT_ID/SECRET)가 있을 때만 넣는다. lat·lng는 지도 가운데 좌표.
    - record_count는 내가 볼 수 있는 친구 기록 수(0 포함). 상권은 소속 규칙, 행정동은 Place.dong 기준.
    """
    friend_ids = store.follows.get(store.ME_ID, set())
    friend_records = [r for r in store.visible_records(store.ME_ID) if r.user_id in friend_ids]
    area_counts = Counter(areas.area_of(store.places[r.place_id].lat, store.places[r.place_id].lng)
                          for r in friend_records)

    nearby = [
        AreaSummary(kind="area", name=a.name, lat=a.lat, lng=a.lng, distance_km=round(d, 2),
                    record_count=area_counts[a.name])
        for a, d in areas.nearest(lat, lng, limit=limit, within_km=AREA_WITHIN_KM)
    ]

    dong = naver.admin_dong(lat, lng)
    if dong is None or dong in areas.BY_NAME:
        return nearby
    dong_entry = AreaSummary(
        kind="dong", name=dong, lat=lat, lng=lng, distance_km=0.0,
        record_count=sum(1 for r in friend_records if store.places[r.place_id].dong == dong),
    )
    if not nearby or nearby[0].distance_km > DONG_FIRST_KM:
        return [dong_entry, *nearby][:limit]
    return [*nearby[: limit - 1], dong_entry]
