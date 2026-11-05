from fastapi import APIRouter, HTTPException

from .. import store, taste
from ..schemas import Coupling, DimensionDiff, Dislike, Record, ScoredPlace, TasteVector, User

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me")
def me() -> User:
    return store.users[store.ME_ID]


@router.get("/me/friends")
def my_friends() -> list[User]:
    return store.friends_of(store.ME_ID)


@router.put("/me/taste")
def save_onboarding_taste(vector: TasteVector) -> User:
    """밸런스 게임 결과로 초기 취향 벡터를 저장한다. 기록이 있으면 기록과 섞어 다시 계산한다."""
    return store.set_onboarding(store.ME_ID, vector)


@router.get("/me/dislikes")
def my_dislikes() -> list[Dislike]:
    return store.dislikes.get(store.ME_ID, [])


@router.put("/me/dislikes")
def save_dislikes(items: list[Dislike]) -> list[Dislike]:
    """불호·알레르기 목록 전체를 바꾼다. 같은 항목은 하나로 합친다."""
    unique = list({(d.target.strip(), d.kind): Dislike(target=d.target.strip(), kind=d.kind) for d in items}.values())
    store.dislikes[store.ME_ID] = unique
    return unique


@router.get("/{user_id}/couple")
def couple(user_id: str) -> Coupling:
    """입맛 커플링 지수와 차원별 비교 (README 6.3, 친구 비교 화면). 친구만 조회할 수 있다."""
    if user_id not in store.follows.get(store.ME_ID, set()):
        raise HTTPException(403, "친구의 입맛만 비교할 수 있습니다")
    me_u, them = store.users[store.ME_ID], store.users[user_id]
    me_v, them_v = me_u.taste.as_list(), them.taste.as_list()

    visible = store.visible_records(store.ME_ID)
    my_ratings = _avg_ratings([r for r in visible if r.user_id == store.ME_ID])
    their_ratings = _avg_ratings([r for r in visible if r.user_id == user_id])
    shared = sorted(my_ratings.keys() & their_ratings.keys())
    percent = taste.couple_percent_with_ratings(
        me_v, them_v, [my_ratings[p] for p in shared], [their_ratings[p] for p in shared]
    )

    dimensions = [
        DimensionDiff(dimension=d, label=taste.DIMENSION_NAMES[d], me=round(a, 2), them=round(b, 2),
                      diff=round(abs(a - b), 2))
        for d, a, b in zip(taste.DIMENSIONS, me_v, them_v)
    ]

    # 친구가 만족한(평점 4 이상) 곳 중 내가 안 가 본 곳을 나와의 적합도 순으로
    suggestions = [
        ScoredPlace(
            place=store.places[pid],
            score=taste.cosine(me_v, store.places[pid].taste.as_list()),
            reason=f"{them.nickname}님 평점 {rating:.1f}",
        )
        for pid, rating in their_ratings.items()
        if pid not in my_ratings and rating >= 4
    ]
    suggestions.sort(key=lambda s: s.score, reverse=True)

    return Coupling(user=them, percent=percent, dimensions=dimensions,
                    shared_place_count=len(shared), suggestions=suggestions[:3])


def _avg_ratings(records: list[Record]) -> dict[str, float]:
    by_place: dict[str, list[float]] = {}
    for r in records:
        by_place.setdefault(r.place_id, []).append(r.rating)
    return {pid: sum(v) / len(v) for pid, v in by_place.items()}
