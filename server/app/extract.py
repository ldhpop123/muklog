"""리뷰·메모 → 5대 미식 속성 추출 (README 6.1).

LLM이 켜져 있으면 구조화 출력으로 추출하고, 아니면 키워드 규칙으로 추출한다.
규칙 기반은 시연·테스트용 대체 경로라 정밀하지 않다. 못 찾은 차원은 null로 둔다.
"""

from . import llm
from .schemas import Attributes
from .taste import DIMENSIONS

# (키워드, 차원, 값). 앞쪽이 더 구체적인 표현이 되도록 둔다. 한 차원에 여러 키워드가 걸리면 평균.
_RULES: list[tuple[str, str, float]] = [
    # 간의 세기
    ("슴슴", "saltiness", -0.7), ("심심", "saltiness", -0.6), ("담백", "saltiness", -0.5),
    ("싱거", "saltiness", -0.6), ("짜다", "saltiness", 0.7), ("짭짤", "saltiness", 0.5), ("자극적", "saltiness", 0.8),
    ("간이 세", "saltiness", 0.7), ("간이 강", "saltiness", 0.7),
    # 매운맛
    ("맵부심", "spiciness", 0.8), ("얼얼", "spiciness", 0.8), ("마라", "spiciness", 0.7),
    ("매콤", "spiciness", 0.5), ("매워", "spiciness", 0.7), ("매운", "spiciness", 0.6),
    ("안 매", "spiciness", -0.6), ("맵지 않", "spiciness", -0.6),
    # 분위기
    ("노포", "ambience", -0.9), ("오래된", "ambience", -0.6), ("허름", "ambience", -0.7),
    ("서민", "ambience", -0.6), ("감성", "ambience", 0.8), ("인스타", "ambience", 0.8),
    ("모던", "ambience", 0.7), ("세련", "ambience", 0.7), ("분위기 좋", "ambience", 0.3),
    # 가성비
    ("가성비", "value", 0.8), ("이 가격", "value", 0.6), ("양이 많", "value", 0.6),
    ("저렴", "value", 0.6), ("비싸", "value", -0.5), ("가격 생각 안", "value", -0.7),
    # 메뉴 지향성
    ("집밥", "cuisine", -0.8), ("한식", "cuisine", -0.7), ("국밥", "cuisine", -0.8),
    ("순댓국", "cuisine", -0.8), ("파스타", "cuisine", 0.8), ("양식", "cuisine", 0.7),
    ("이국", "cuisine", 0.8), ("마라", "cuisine", 0.5), ("스시", "cuisine", 0.5),
]

_TAG_KEYWORDS = {
    "노포": "노포", "가성비": "가성비", "혼밥": "혼밥", "안주": "안주맛집", "데이트": "데이트",
    "아재": "아재입맛", "매운": "매운맛", "맵부심": "매운맛", "감성": "감성",
}

_SYSTEM = """너는 맛집 리뷰에서 미식 속성을 뽑는 분석기다.
리뷰를 읽고 5개 차원을 각각 -1~+1 실수로 평가한다.
- saltiness 간의 세기: -1 슴슴함 ~ +1 자극적
- spiciness 매운맛: -1 안 매움 ~ +1 아주 매움
- ambience 분위기: -1 노포·서민 ~ +1 모던·감성
- value 가성비: -1 가격 무관 ~ +1 가성비 중시
- cuisine 메뉴 지향성: -1 한식·토속 ~ +1 양식·이국
리뷰에 근거가 없는 차원은 반드시 null로 둔다. 추측하지 않는다.
tags에는 다음 중 리뷰가 뒷받침하는 것만 넣는다: 노포, 아재입맛, 혼밥, 안주맛집, 데이트, 가성비, 매운맛, 감성.
evidence에는 판단 근거가 된 리뷰 문구를 원문 그대로 넣는다."""

_NULLABLE_SCORE = {"anyOf": [{"type": "number"}, {"type": "null"}]}
_SCHEMA = {
    "type": "object",
    "properties": {
        **{d: _NULLABLE_SCORE for d in DIMENSIONS},
        "tags": {"type": "array", "items": {"type": "string"}},
        "evidence": {"type": "array", "items": {"type": "string"}},
    },
    "required": [*DIMENSIONS, "tags", "evidence"],
    "additionalProperties": False,
}


def extract_by_rules(memo: str, tags: list[str]) -> Attributes:
    text = " ".join([memo, *tags])
    hits: dict[str, list[float]] = {}
    evidence: list[str] = []
    for keyword, dim, value in _RULES:
        if keyword in text:
            hits.setdefault(dim, []).append(value)
            evidence.append(keyword)
    found_tags = sorted({tag for kw, tag in _TAG_KEYWORDS.items() if kw in text})
    return Attributes(
        **{dim: sum(vs) / len(vs) for dim, vs in hits.items()},
        tags=found_tags,
        evidence=evidence,
    )


def _clamp(v: float | None) -> float | None:
    return None if v is None else min(1.0, max(-1.0, float(v)))


def extract(memo: str, tags: list[str]) -> Attributes:
    if not memo.strip() and not tags:
        return Attributes()
    data = llm.complete_json(_SYSTEM, f"리뷰: {memo}\n작성자가 고른 태그: {', '.join(tags) or '없음'}", _SCHEMA)
    if data is None:
        return extract_by_rules(memo, tags)
    return Attributes(
        **{d: _clamp(data.get(d)) for d in DIMENSIONS},
        tags=data.get("tags", []),
        evidence=data.get("evidence", []),
    )
