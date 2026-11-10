from typing import Literal

from fastapi import APIRouter

from .. import store
from ..schemas import PublicUser, RankingEntry

from ..auth import CurrentUser

router = APIRouter(prefix="/ranking", tags=["ranking"])


@router.get("")
def ranking(me_id: CurrentUser, scope: Literal["friends", "all"] = "friends", limit: int = 20) -> list[RankingEntry]:
    """미식가 랭킹 (README 7.3). friends는 나와 내 친구, all은 전체 사용자를 신뢰 온도 순으로.

    전체 랭킹에는 친구가 아닌 사람도 나오므로 취향 벡터를 뺀 PublicUser로 응답한다.

    TODO(ranking): 지역·카테고리별 랭킹은 긍정 평가가 몰린 지역 기준으로 집계.
    """
    if scope == "friends":
        pool = [store.users[me_id], *store.friends_of(me_id)]
    else:
        pool = list(store.users.values())
    ordered = sorted(pool, key=lambda u: u.trust_temp, reverse=True)[: max(1, min(limit, 100))]
    return [RankingEntry(rank=i + 1, user=PublicUser.model_validate(u.model_dump())) for i, u in enumerate(ordered)]
