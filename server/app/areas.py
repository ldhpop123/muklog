"""브리핑·지도에 쓰는 서울 주요 상권 목록.

좌표는 2026-11-06에 NAVER API HUB 지역 검색으로 확인한 각 상권의 기준점(주로 지하철역,
연남은 경의선숲길공원, 익선동은 한옥거리, 가로수길은 거리, 잠실은 송리단길)이다.
식당은 "반경 안에 있는 상권 중 가장 가까운 곳" 하나에만 속한다. 그래서 홍대·연남·합정처럼
붙어 있는 상권끼리도 같은 식당이 두 브리핑에 겹쳐 나오지 않는다.
"""

from pydantic import BaseModel

from . import taste


class Area(BaseModel):
    name: str
    lat: float
    lng: float
    radius_km: float


def _a(name: str, lat: float, lng: float, radius_km: float = 0.7) -> Area:
    return Area(name=name, lat=lat, lng=lng, radius_km=radius_km)


AREAS: list[Area] = [
    # 마포·서대문
    _a("홍대", 37.5570, 126.9240),  # 홍대입구역
    _a("연남", 37.5620, 126.9230),  # 경의선숲길공원(연남동)
    _a("합정", 37.5499, 126.9145),  # 합정역
    _a("상수", 37.5478, 126.9223),  # 상수역
    _a("망원", 37.5561, 126.9101),  # 망원역
    _a("신촌", 37.5552, 126.9369),  # 신촌역
    _a("이대", 37.5568, 126.9463),  # 이대역
    # 성동·광진
    _a("성수", 37.5446, 127.0560, 0.8),  # 성수역
    _a("서울숲", 37.5420, 127.0386),  # 서울숲
    _a("건대", 37.5404, 127.0693, 0.8),  # 건대입구역
    _a("왕십리", 37.5613, 127.0376),  # 왕십리역
    # 종로·중구
    _a("익선동", 37.5734, 126.9898, 0.5),  # 익선동 한옥거리
    _a("종로", 37.5702, 126.9831),  # 종각역
    _a("을지로", 37.5664, 126.9926),  # 을지로3가역
    _a("광화문", 37.5717, 126.9765),  # 광화문역
    _a("혜화", 37.5821, 127.0019),  # 혜화역(대학로)
    _a("동묘", 37.5730, 127.0160, 0.5),  # 동묘앞역(1·6호선 사이)
    # 용산
    _a("이태원", 37.5345, 126.9946),  # 이태원역
    _a("한남", 37.5398, 127.0018),  # 한강진역
    _a("용산", 37.5292, 126.9679),  # 신용산역(용리단길)
    # 강남·송파
    _a("강남역", 37.4980, 127.0276, 0.8),  # 강남역
    _a("신논현", 37.5046, 127.0249),  # 신논현역
    _a("가로수길", 37.5197, 127.0231),  # 신사동 가로수길
    _a("압구정로데오", 37.5274, 127.0406),  # 압구정로데오역
    _a("청담", 37.5195, 127.0539),  # 청담역
    _a("삼성", 37.5089, 127.0632, 0.8),  # 삼성역
    _a("잠실", 37.5098, 127.1095, 0.8),  # 송리단길
    # 영등포
    _a("문래", 37.5180, 126.8948),  # 문래역
    _a("여의도", 37.5215, 126.9239, 0.9),  # 여의도역
]

BY_NAME: dict[str, Area] = {a.name: a for a in AREAS}


def distance_to(area: Area, lat: float, lng: float) -> float:
    return taste.distance_km(lat, lng, area.lat, area.lng)


def nearest(lat: float, lng: float, limit: int = 5, within_km: float | None = None) -> list[tuple[Area, float]]:
    """가까운 상권 순으로 (상권, 거리 km). within_km를 주면 그 안의 상권만."""
    ranked = sorted(((a, distance_to(a, lat, lng)) for a in AREAS), key=lambda x: x[1])
    if within_km is not None:
        ranked = [(a, d) for a, d in ranked if d <= within_km]
    return ranked[:limit]


def area_of(lat: float, lng: float) -> str | None:
    """좌표가 속한 상권. 반경 안에 있는 상권 중 가장 가까운 곳, 없으면 None."""
    inside = [(a, d) for a in AREAS if (d := distance_to(a, lat, lng)) <= a.radius_km]
    if not inside:
        return None
    return min(inside, key=lambda x: x[1])[0].name
