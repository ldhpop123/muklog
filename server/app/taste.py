"""미식 취향 벡터 연산 (README 6장).

벡터는 5대 미식 차원 [간의 세기, 매운맛, 분위기, 가성비, 메뉴 지향성], 각 값 -1 ~ +1.
앱의 `TasteVector`(app/lib/models/taste_vector.dart)와 같은 식을 쓴다.
"""

import math
from collections.abc import Sequence

Vector = Sequence[float]
DIMENSIONS = ("saltiness", "spiciness", "ambience", "value", "cuisine")


def cosine(a: Vector, b: Vector) -> float:
    """코사인 유사도 (-1 ~ 1). 영벡터가 끼면 0."""
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na = math.sqrt(sum(x * x for x in a))
    nb = math.sqrt(sum(y * y for y in b))
    if na == 0 or nb == 0:
        return 0.0
    return dot / (na * nb)


def couple_percent(a: Vector, b: Vector) -> int:
    """입맛 커플링 지수 (0 ~ 100%). README 6.3."""
    return round(50 * (1 + cosine(a, b)))


def normalize_trust(temp: float) -> float:
    """맛 신뢰 온도(℃)를 0 ~ 1로 정규화. 30℃ 이하 0, 50℃ 이상 1."""
    return min(1.0, max(0.0, (temp - 30) / 20))


def score(
    user: Vector,
    place: Vector,
    friend_signals: Sequence[tuple[Vector, float, int]],
    context: float = 1.0,
) -> float:
    """하이브리드 추천 점수 Score(u, i). README 6.4.

    friend_signals: (친구 벡터, 친구 신뢰 온도 ℃, 친구의 해당 식당 방문 횟수) 목록.
    입맛이 반대인 친구(유사도 < 0)의 방문은 가산하지 않는다.
    """
    signal = sum(
        max(0.0, cosine(user, fv)) * normalize_trust(temp) * visits
        for fv, temp, visits in friend_signals
    )
    return cosine(user, place) * (1 + math.log(1 + signal)) * context


def party_score(members: Sequence[Vector], place: Vector) -> float:
    """파티 모드 점수 = 0.7 × 평균 만족 + 0.3 × 최소 만족. README 6.5."""
    sats = [cosine(m, place) for m in members]
    return 0.7 * (sum(sats) / len(sats)) + 0.3 * min(sats)


def onboarding_weight(record_count: int) -> float:
    """사용자 벡터에서 온보딩(밸런스 게임) 결과가 차지하는 비중 α. 기록 5개면 0.5."""
    return 1 / (1 + record_count / 5)


def trust_agreement(recommender_rating: float, visitor_rating: float) -> float:
    """추천자와 방문자의 평점 일치도 (0 ~ 1). README 7.2."""
    return 1 - abs(recommender_rating - visitor_rating) / 4


DIMENSION_LABELS = {
    "saltiness": ("슴슴한 맛", "자극적인 맛"),
    "spiciness": ("순한 맛", "매운맛"),
    "ambience": ("노포", "감성 공간"),
    "value": ("분위기·품질", "가성비"),
    "cuisine": ("한식", "양식·이국 요리"),
}
DIMENSION_NAMES = {
    "saltiness": "간의 세기", "spiciness": "매운맛", "ambience": "분위기",
    "value": "가성비", "cuisine": "메뉴 지향성",
}


def user_vector(
    onboarding: Vector,
    rated_places: Sequence[tuple[Vector, float, int]],
) -> list[float]:
    """사용자 취향 벡터 V_u (README 6.2).

    rated_places: (식당 벡터, 평균 평점, 방문 횟수) 목록. 식당마다 한 번씩.
    w_i = (평점 − 3) × (1 + log(1 + 재방문수)). 평점이 3 미만이면 그 식당 반대쪽으로 민다.
    가중 평균은 Σ|w_i|로 나눠 값이 -1 ~ 1을 벗어나지 않게 한다.
    """
    alpha = onboarding_weight(len(rated_places))
    weights = [(rating - 3) * (1 + math.log(1 + max(0, visits - 1))) for _, rating, visits in rated_places]
    total = sum(abs(w) for w in weights)
    if total == 0:
        return list(onboarding)
    learned = [
        sum(w * pv[d] for w, (pv, _, _) in zip(weights, rated_places)) / total
        for d in range(len(onboarding))
    ]
    return [alpha * o + (1 - alpha) * x for o, x in zip(onboarding, learned)]


def place_vector(prior: Vector, samples: Sequence[Sequence[float | None]]) -> list[float]:
    """식당 벡터 V_i = 리뷰 추출값의 차원별 평균 (README 6.2).

    시드·외부 데이터로 정한 사전값(prior)을 표본 1개로 섞어, 리뷰가 적을 때 크게 흔들리지 않게 한다.
    리뷰에서 null인 차원은 평균에서 뺀다.
    """
    result = []
    for d, p in enumerate(prior):
        values = [v for s in samples if (v := s[d]) is not None]
        result.append((p + sum(values)) / (1 + len(values)))
    return result


def pearson(xs: Sequence[float], ys: Sequence[float]) -> float | None:
    """피어슨 상관계수. 표본이 3개 미만이거나 분산이 0이면 None."""
    n = len(xs)
    if n < 3:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    cov = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    vx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    vy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if vx == 0 or vy == 0:
        return None
    return cov / (vx * vy)


def couple_percent_with_ratings(a: Vector, b: Vector, ratings_a: Sequence[float], ratings_b: Sequence[float]) -> int:
    """커플링 지수에 같은 식당 평점 상관(3곳 이상일 때)을 30% 반영한다. README 6.3."""
    base = 50 * (1 + cosine(a, b))
    r = pearson(ratings_a, ratings_b)
    if r is None:
        return round(base)
    return round(0.7 * base + 0.3 * 50 * (1 + r))


def distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 사이 거리(km). 하버사인."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def distance_decay(km: float, half_km: float = 1.5) -> float:
    """Context 보정 C(i)의 거리 감쇠 (README 6.4). half_km에서 0.5."""
    return 1 / (1 + km / half_km)


# 맛 신뢰 온도 (README 7.2)
BASE_TEMP = 36.5
TRUST_K = 40.0  # 온도 민감도
TRUST_PRIOR_N = 10  # 베이지안 사전 표본 수 m
TRUST_NEUTRAL = 0.625  # 긍정(0.75)과 부정(0.5) 기준의 중간


def trust_event_score(agreement: float, couple_pct: int) -> float:
    """평가 한 건의 점수. 입맛이 먼(커플링 50% 미만) 사람까지 만족시켰으면 가산한다."""
    if agreement >= 0.75 and couple_pct < 50:
        return agreement + 0.2 * (50 - couple_pct) / 50
    return agreement


def trust_temperature(base: float, scores: Sequence[tuple[float, float]]) -> float:
    """온도 = 기준 + k × Σ w·(점수 − 중립) / (Σw + m).

    scores: (평가 점수, 가중치). 가중치는 같은 두 사람 사이 반복 평가를 줄이는 데 쓴다.
    표본이 적을수록 기준 온도에 가깝다.
    """
    total_w = sum(w for _, w in scores)
    lift = sum(w * (s - TRUST_NEUTRAL) for s, w in scores)
    return round(base + TRUST_K * lift / (total_w + TRUST_PRIOR_N), 1)


def trust_level(temp: float) -> str:
    """온도 구간별 레벨 (README 7.3)."""
    if temp >= 45:
        return "먹로그 마스터"
    if temp >= 40:
        return "지역 감별사"
    if temp >= 36.5:
        return "동네 맛잘알"
    return "새내기 먹로거"
