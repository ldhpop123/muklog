"""인메모리 저장소. PostgreSQL(PostGIS + pgvector) 연결 전까지 쓰는 시드 데이터.

TODO(db): README 10장 스키마로 PostgreSQL 이관. 함수 시그니처는 유지한다.
"""

import threading
from collections import Counter
from datetime import datetime

from pydantic import BaseModel

from . import extract, taste
from .schemas import Attributes, Dislike, Place, PlaceIn, Record, RecordIn, TasteVector, User


def _tv(*v: float) -> TasteVector:
    return TasteVector(saltiness=v[0], spiciness=v[1], ambience=v[2], value=v[3], cuisine=v[4])


ME_ID = "me"  # TODO(auth): 카카오 로그인 후 토큰에서 사용자 식별

# 기록 처리(백그라운드)와 요청 처리가 같은 dict를 만지므로 갱신은 이 락 안에서 한다.
lock = threading.Lock()

users: dict[str, User] = {
    u.id: u
    for u in [
        User(id="me", nickname="나", avatar_url="https://api.dicebear.com/9.x/thumbs/png?seed=me",
             taste=_tv(-0.4, 0.3, -0.6, 0.7, -0.5)),
        User(id="u1", nickname="민수", avatar_url="https://api.dicebear.com/9.x/thumbs/png?seed=minsu",
             taste=_tv(-0.5, 0.2, -0.8, 0.6, -0.6), trust_temp=42.1, title="홍대 국밥 감별사", level="지역 감별사"),
        User(id="u2", nickname="지은", avatar_url="https://api.dicebear.com/9.x/thumbs/png?seed=jieun",
             taste=_tv(0.3, 0.8, 0.5, -0.2, 0.4), trust_temp=38.4, level="동네 맛잘알"),
        User(id="u3", nickname="현우", avatar_url="https://api.dicebear.com/9.x/thumbs/png?seed=hyunwoo",
             taste=_tv(0.1, -0.3, -0.2, 0.9, -0.3), trust_temp=36.9, level="동네 맛잘알"),
    ]
}

# 밸런스 게임 결과. 사용자 벡터 계산의 출발점(README 6.2의 V_onboarding).
onboarding: dict[str, TasteVector] = {u.id: u.taste for u in users.values()}

# 신뢰 온도 기준값. 시드 사용자는 시연용으로 정한 값에서 시작한다.
base_temps: dict[str, float] = {u.id: u.trust_temp for u in users.values()}
seed_titles: dict[str, str] = {u.id: u.title for u in users.values() if u.title}

follows: dict[str, set[str]] = {"me": {"u1", "u2", "u3"}}

dislikes: dict[str, list[Dislike]] = {
    "u2": [Dislike(target="국밥", kind="불호")],
    "u3": [Dislike(target="갑각류", kind="알레르기")],
}

places: dict[str, Place] = {
    p.id: p
    for p in [
        Place(id="p1", name="서교 순댓국", lat=37.5550, lng=126.9205, area="홍대", category="국밥",
              taste=_tv(-0.5, 0.0, -0.9, 0.8, -0.9), tags=["노포", "아재입맛", "혼밥"], revisit_total=11),
        Place(id="p2", name="연남 마라공방", lat=37.5612, lng=126.9248, area="연남", category="중식",
              taste=_tv(0.6, 0.9, 0.3, 0.2, 0.5), tags=["매운맛", "데이트"], revisit_total=3),
        Place(id="p3", name="홍대 골목포차", lat=37.5534, lng=126.9241, area="홍대", category="주점",
              taste=_tv(0.2, 0.3, -0.4, 0.6, -0.4), tags=["안주맛집", "노포"], revisit_total=7),
        Place(id="p4", name="상수 파스타랩", lat=37.5478, lng=126.9227, area="상수", category="양식",
              taste=_tv(0.0, -0.4, 0.9, -0.5, 0.9), tags=["데이트", "감성"], revisit_total=2),
    ]
}

# 시연 지역의 중심 좌표. 새 식당이 이 반경 안이면 해당 지역으로 묶는다.
AREA_CENTERS: dict[str, tuple[float, float]] = {
    "홍대": (37.5545, 126.9220),
    "연남": (37.5620, 126.9250),
    "상수": (37.5478, 126.9227),
}
AREA_RADIUS_KM = 0.8

# 식당 벡터의 사전값. 리뷰 추출값이 쌓이면 이 값과 평균낸다.
place_priors: dict[str, TasteVector] = {p.id: p.taste for p in places.values()}

records: list[Record] = [
    Record(id="r1", user_id="u1", place_id="p1", rating=4.5, visit_no=4,
           memo="간이 슴슴해서 매일 먹어도 질리지 않음. 오래된 노포 느낌 그대로.",
           visited_at=datetime(2026, 10, 28), tags=["노포", "아재입맛"]),
    Record(id="r2", user_id="u3", place_id="p1", rating=4.0, visit_no=2,
           memo="이 가격에 이 양이면 무조건 재방문.",
           visited_at=datetime(2026, 10, 15), tags=["가성비"]),
    Record(id="r3", user_id="u2", place_id="p2", rating=5.0, visit_no=1,
           memo="맵부심 자극하는 맛. 얼얼함이 오래 감.",
           visited_at=datetime(2026, 11, 1), tags=["매운맛"]),
    Record(id="r4", user_id="u1", place_id="p3", rating=4.0, visit_no=3,
           memo="분위기 좋은 안주 맛집. 계란말이 필수.",
           visited_at=datetime(2026, 10, 20), tags=["안주맛집"]),
]

# 기록별 추출 속성. 새 기록만 채워진다(시드 식당 벡터는 사전값에 이미 반영).
record_attrs: dict[str, Attributes] = {}


class TrustEvent(BaseModel):
    """방문자가 추천자의 기록을 보고 가서 남긴 평가 한 건 (README 7.2)."""

    recommender_id: str
    visitor_id: str
    source_record_id: str
    visit_record_id: str
    agreement: float
    score: float
    created_at: datetime


trust_events: list[TrustEvent] = []


def friends_of(user_id: str) -> list[User]:
    return [users[i] for i in sorted(follows.get(user_id, set()))]


def can_see(viewer_id: str, r: Record) -> bool:
    """- 내 기록: 전부
    - 내가 팔로우한 사람의 기록: private 제외
    - 그 외: public만
    """
    if r.user_id == viewer_id:
        return True
    if r.user_id in follows.get(viewer_id, set()):
        return r.visibility != "private"
    return r.visibility == "public"


def visible_records(viewer_id: str) -> list[Record]:
    """viewer가 볼 수 있는 기록. 타인의 기록은 모든 엔드포인트가 이 함수로만 읽는다.

    비공개 기록은 본인 취향 벡터 학습(refresh_user_taste)에만 쓰이고 타인 추천 신호에는 쓰이지 않는다.
    """
    return [r for r in records if can_see(viewer_id, r)]


def find_record(record_id: str) -> Record | None:
    return next((r for r in records if r.id == record_id), None)


def add_record(user_id: str, data: RecordIn) -> Record:
    """기록을 저장만 한다. 속성 추출과 벡터·온도 갱신은 process_record가 비동기로 한다."""
    with lock:
        visit_no = 1 + sum(1 for r in records if r.user_id == user_id and r.place_id == data.place_id)
        record = Record(
            **data.model_dump(),
            id=f"r{len(records) + 1}",
            user_id=user_id,
            visit_no=visit_no,
            visited_at=datetime.now(),
        )
        records.append(record)
        places[record.place_id] = places[record.place_id].model_copy(
            update={"revisit_total": places[record.place_id].revisit_total + 1}
        )
    return record


def process_record(record_id: str) -> None:
    """기록 저장 후 백그라운드 작업 (README 9.1의 워커 역할).

    1. 리뷰 속성 추출 → 2. 식당 벡터 갱신 → 3. 작성자 취향 벡터 갱신 → 4. 보고 온 기록이 있으면 추천자 신뢰 온도 갱신.
    TODO(worker): Redis 큐 + 별도 워커 프로세스로 분리.
    """
    record = find_record(record_id)
    if record is None:
        return
    # LLM 호출은 느릴 수 있으니 락 밖에서 한다.
    attrs = extract.extract(record.memo, record.tags)

    with lock:
        record_attrs[record.id] = attrs
        _refresh_place(record.place_id)
        refresh_user_taste(record.user_id)
        if record.inspired_by_record_id:
            _add_trust_event(record)


def _refresh_place(place_id: str) -> None:
    """식당 벡터·태그를 공개 범위 안의 기록으로 다시 계산한다.

    - 비공개 기록은 빼서, 비공개 메모 내용이 식당 벡터·태그로 새어 나가지 않게 한다(본인 취향 학습에는 쓴다).
    - 한 사용자의 여러 기록은 차원별 평균 1개 표본으로 합쳐, 한 사람이 기록을 반복해 식당 벡터를 끌고 가지 못하게 한다.
    - 태그는 서로 다른 사용자 2명 이상이 뒷받침해야 식당에 붙는다.
    """
    by_user: dict[str, list[Attributes]] = {}
    for r in records:
        if r.place_id == place_id and r.visibility != "private" and r.id in record_attrs:
            by_user.setdefault(r.user_id, []).append(record_attrs[r.id])

    samples = [_merge(attrs) for attrs in by_user.values()]
    tag_users = Counter(t for attrs in by_user.values() for t in {t for a in attrs for t in a.tags})
    place = places[place_id]
    new_tags = place.tags + [t for t, n in tag_users.most_common() if n >= 2 and t not in place.tags]
    places[place_id] = place.model_copy(update={
        "taste": TasteVector.from_list(taste.place_vector(place_priors[place_id].as_list(), samples)),
        "tags": new_tags,
    })


def _merge(attrs: list[Attributes]) -> list[float | None]:
    """여러 기록의 속성을 차원별 평균 1개로 합친다. 값이 하나도 없는 차원은 None."""
    merged: list[float | None] = []
    for d in range(len(taste.DIMENSIONS)):
        values = [v for a in attrs if (v := a.as_list()[d]) is not None]
        merged.append(sum(values) / len(values) if values else None)
    return merged


def refresh_user_taste(user_id: str) -> None:
    """V_u = α·V_onboarding + (1−α)·평점 가중 식당 벡터 평균 (README 6.2). 비공개 기록도 본인 학습에는 쓴다."""
    by_place: dict[str, list[Record]] = {}
    for r in records:
        if r.user_id == user_id:
            by_place.setdefault(r.place_id, []).append(r)
    rated = [
        (places[pid].taste.as_list(), sum(r.rating for r in rs) / len(rs), len(rs))
        for pid, rs in by_place.items()
    ]
    vector = taste.user_vector(onboarding[user_id].as_list(), rated)
    users[user_id] = users[user_id].model_copy(update={"taste": TasteVector.from_list(vector)})


def set_onboarding(user_id: str, vector: TasteVector) -> User:
    with lock:
        onboarding[user_id] = vector
        refresh_user_taste(user_id)
        return users[user_id]


def _add_trust_event(visit: Record) -> None:
    source = find_record(visit.inspired_by_record_id or "")
    # 라우터에서 검증하지만, 비동기 처리 사이에 바뀌었을 수 있어 다시 확인한다.
    if source is None or source.user_id == visit.user_id or source.place_id != visit.place_id:
        return
    agreement = taste.trust_agreement(source.rating, visit.rating)
    couple = taste.couple_percent(users[source.user_id].taste.as_list(), users[visit.user_id].taste.as_list())
    trust_events.append(TrustEvent(
        recommender_id=source.user_id,
        visitor_id=visit.user_id,
        source_record_id=source.id,
        visit_record_id=visit.id,
        agreement=agreement,
        score=taste.trust_event_score(agreement, couple),
        created_at=datetime.now(),
    ))
    refresh_trust(source.user_id)


TRUST_MAX_PER_VISITOR = 3  # 방문자 한 명이 추천자 한 명의 온도에 반영할 수 있는 최대 평가 수


def counted_trust_events(recommender_id: str) -> list[TrustEvent]:
    """온도에 반영할 평가만 고른다 (README 7.4 어뷰징 방지).

    - (방문자, 원본 기록) 쌍마다 가장 최근 평가 1건만 센다. 같은 기록을 보고 여러 번 기록해도 한 번이다.
    - 방문자 한 명당 최근 TRUST_MAX_PER_VISITOR건까지만 센다. 반복 평가로 온도를 계속 움직일 수 없다.
    """
    latest: dict[tuple[str, str], TrustEvent] = {}
    for e in trust_events:
        if e.recommender_id == recommender_id:
            latest[(e.visitor_id, e.source_record_id)] = e
    per_visitor: dict[str, list[TrustEvent]] = {}
    for e in latest.values():
        per_visitor.setdefault(e.visitor_id, []).append(e)
    return [
        e for events in per_visitor.values()
        for e in sorted(events, key=lambda x: x.created_at)[-TRUST_MAX_PER_VISITOR:]
    ]


def refresh_trust(user_id: str) -> None:
    """맛 신뢰 온도·레벨·칭호 재계산 (README 7.2~7.4).

    TODO(abuse): 방문 인증(체크인·영수증)된 평가만 반영, 단기간 몰린 평가 탐지.
    """
    counted = counted_trust_events(user_id)
    temp = taste.trust_temperature(base_temps.get(user_id, taste.BASE_TEMP), [(e.score, 1.0) for e in counted])
    level = taste.trust_level(temp)
    users[user_id] = users[user_id].model_copy(
        update={"trust_temp": temp, "level": level, "title": _title(counted, user_id, level)}
    )


def _title(counted: list[TrustEvent], user_id: str, level: str) -> str | None:
    """칭호 = 긍정 평가가 가장 많이 몰린 '지역 + 카테고리' (README 7.3). 지역 감별사 이상만."""
    if level not in ("지역 감별사", "먹로그 마스터"):
        return None
    combos: Counter[tuple[str, str]] = Counter()
    for e in counted:
        if e.agreement >= 0.75:
            source = find_record(e.source_record_id)
            if source:
                p = places[source.place_id]
                combos[(p.area, p.category)] += 1
    if not combos:
        return seed_titles.get(user_id)
    area, category = combos.most_common(1)[0][0]
    return f"{area} {category} 감별사"


def area_for(lat: float, lng: float, address: str) -> str:
    """가장 가까운 시연 지역(반경 안), 없으면 주소의 동·읍·면 이름, 그것도 없으면 '기타'."""
    nearest = min(AREA_CENTERS, key=lambda a: taste.distance_km(lat, lng, *AREA_CENTERS[a]))
    if taste.distance_km(lat, lng, *AREA_CENTERS[nearest]) <= AREA_RADIUS_KM:
        return nearest
    for token in address.split():
        if token.endswith(("동", "읍", "면", "가")) and not token[0].isdigit() and len(token) > 1:
            return token
    return "기타"


def find_place_by_external(external_id: str) -> Place | None:
    return next((p for p in places.values() if p.external_id == external_id), None)


def add_place(data: PlaceIn) -> tuple[Place, bool]:
    """외부 검색 결과로 식당을 등록한다. 같은 external_id가 있으면 기존 식당과 False를 돌려준다.

    취향 벡터 사전값은 0(중립)으로 두고, 기록이 쌓이면 리뷰 추출값으로 채워진다.
    """
    with lock:
        existing = find_place_by_external(data.external_id)
        if existing:
            return existing, False
        n = len(places) + 1
        while f"p{n}" in places:
            n += 1
        neutral = TasteVector.from_list([0.0] * len(taste.DIMENSIONS))
        place = Place(
            id=f"p{n}", name=data.name, lat=data.lat, lng=data.lng, category=data.category,
            area=area_for(data.lat, data.lng, data.address), taste=neutral,
            address=data.address or None, external_id=data.external_id,
        )
        places[place.id] = place
        place_priors[place.id] = neutral
        return place, True
