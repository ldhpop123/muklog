from fastapi import APIRouter, HTTPException

from .. import store, taste
from ..schemas import Dislike, PartyRequest, Place, ScoredPlace, User

router = APIRouter(prefix="/recommend", tags=["recommend"])


def excluded_by(place: Place, dislikes: list[Dislike]) -> Dislike | None:
    """불호·알레르기 항목이 식당 카테고리·태그·이름에 걸리면 그 항목을 돌려준다."""
    for d in dislikes:
        if d.target == place.category or d.target in place.tags or d.target in place.name:
            return d
    return None


def scored_for(me: User, lat: float | None = None, lng: float | None = None) -> list[ScoredPlace]:
    """Fit × Trust × Context 점수 순 추천 (README 6.4). 내 불호 식당은 뺀다."""
    friends = {f.id: f for f in store.friends_of(me.id)}
    me_v = me.taste.as_list()
    my_dislikes = store.dislikes.get(me.id, [])
    records = store.visible_records(me.id)

    results = []
    for place in store.places.values():
        if excluded_by(place, my_dislikes):
            continue
        visits: dict[str, int] = {}
        for r in records:
            if r.place_id == place.id and r.user_id in friends:
                visits[r.user_id] = max(visits.get(r.user_id, 0), r.visit_no)

        signals = [(friends[fid].taste.as_list(), friends[fid].trust_temp, n) for fid, n in visits.items()]
        reason = None
        if visits:
            top = max(visits, key=lambda fid: taste.cosine(me_v, friends[fid].taste.as_list()))
            pct = taste.couple_percent(me_v, friends[top].taste.as_list())
            reason = f"{friends[top].nickname}님(입맛 {pct}%)이 {visits[top]}번 방문"

        context = 1.0
        if lat is not None and lng is not None:
            km = taste.distance_km(lat, lng, place.lat, place.lng)
            context = taste.distance_decay(km)
            reason = f"{reason} · {km:.1f}km" if reason else f"{km:.1f}km"

        score = taste.score(me_v, place.taste.as_list(), signals, context)
        results.append(ScoredPlace(place=place, score=score, reason=reason))

    return sorted(results, key=lambda s: s.score, reverse=True)


@router.get("")
def recommend(lat: float | None = None, lng: float | None = None) -> list[ScoredPlace]:
    """개인화 추천 리스트. lat·lng을 주면 거리 감쇠를 Context 보정으로 곱한다."""
    if (lat is None) != (lng is None):
        raise HTTPException(422, "lat과 lng은 함께 보내야 합니다")
    return scored_for(store.users[store.ME_ID], lat, lng)


def _party_reason(members: list[User], place: Place) -> str:
    """구성원마다 이 식당과 가장 잘 맞는 취향 차원을 골라 문장으로 만든다 (README 6.5 설명)."""
    pv = place.taste.as_list()
    parts = []
    for m in members:
        mv = m.taste.as_list()
        d = max(range(len(pv)), key=lambda i: mv[i] * pv[i])
        if mv[d] * pv[d] < 0.1:
            continue
        low, high = taste.DIMENSION_LABELS[taste.DIMENSIONS[d]]
        who = "나" if m.id == store.ME_ID else f"{m.nickname}님"
        parts.append(f"{who}의 {high if pv[d] > 0 else low} 취향")
    if not parts:
        return "모두에게 무난한 곳"
    if len(parts) == 1:
        return f"{parts[0]}에 잘 맞아요"
    return f"{', '.join(parts[:-1])}과 {parts[-1]}을 모두 만족"


@router.post("/party")
def party(req: PartyRequest) -> list[ScoredPlace]:
    """파티 모드 교집합 추천 (README 6.5)."""
    # 친구만 파티에 넣을 수 있다. 아무 사용자 ID로 남의 취향을 떠보지 못하게 막는다.
    friend_ids = store.follows.get(store.ME_ID, set())
    not_friends = [i for i in req.member_ids if i != store.ME_ID and i not in friend_ids]
    if not_friends:
        raise HTTPException(403, f"친구가 아닌 사용자: {not_friends}")
    members = [store.users[store.ME_ID], *(store.users[i] for i in dict.fromkeys(req.member_ids) if i != store.ME_ID)]
    vectors = [m.taste.as_list() for m in members]
    # 한 명이라도 불호·알레르기로 등록한 식당은 후보에서 뺀다. 누가 싫어하는지는 밝히지 않는다.
    group_dislikes = [d for m in members for d in store.dislikes.get(m.id, [])]

    results = []
    for place in store.places.values():
        if excluded_by(place, group_dislikes):
            continue
        results.append(ScoredPlace(
            place=place,
            score=taste.party_score(vectors, place.taste.as_list()),
            reason=_party_reason(members, place),
        ))
    return sorted(results, key=lambda s: s.score, reverse=True)
