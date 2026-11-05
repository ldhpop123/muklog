"""AI 지역 브리핑 (README 6.6)."""

import json
import re

from fastapi import APIRouter, HTTPException

from .. import llm, store
from ..schemas import Briefing, BriefingSentence, Record, ScoredPlace
from .recommend import scored_for

router = APIRouter(prefix="/briefing", tags=["briefing"])

TOP_PLACES = 3

# LLM 입력이 같으면 같은 브리핑을 돌려준다. 로컬 LLM은 한 번에 10~20초 걸려서 시연·반복 조회에 필요하다.
# 입력(지역·식당·친구 기록)이 바뀌면 키가 달라져 자연히 새로 만든다.
_cache: dict[str, list[BriefingSentence]] = {}
_CACHE_MAX = 256

_SYSTEM = """너는 친구 기반 맛집 앱 '먹로그'의 지역 브리핑 작성자다.
주어진 JSON 데이터만 근거로 한국어 3~5문장 브리핑을 쓴다. 데이터에 없는 사실, 메뉴, 평가는 절대 지어내지 않는다.
읽는 사람은 앱 사용자 본인이다. 친구에게 말을 거는 투로 쓰지 말고, 친구는 '민수님이 ~했어요'처럼 3인칭으로 쓴다.
친근한 해요체로 쓰고, 첫 문장은 '{지역}에서는'으로 시작한다. 식당 이름은 작은따옴표로 감싼다.
각 문장마다 근거가 된 기록 id(record_id)를 record_ids에 넣는다. 근거 기록이 없는 문장은 쓰지 않는다.
text에는 record_id나 'record_ids' 같은 내부 값을 쓰지 않는다.
모든 문장은 '~했어요', '~예요'로 끝나는 해요체다. '~이다', '~된다'로 끝내지 않는다.
태그 이름이나 점수를 나열하지 말고, 메모에 적힌 내용을 자연스럽게 옮긴다.

문장 예시(형식만 참고하고 내용은 데이터에서 가져온다):
홍대에서는 민수님이 '○○포차'를 분위기 좋은 안주 맛집으로 꼽았어요.
민수님은 이곳에 4번이나 다녀왔고, 계란말이는 꼭 시키라고 했어요."""

_SCHEMA = {
    "type": "object",
    "properties": {
        "sentences": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "record_ids": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["text", "record_ids"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["sentences"],
    "additionalProperties": False,
}


@router.get("")
def briefing(area: str) -> Briefing:
    """지역 안 친구 기록을 모아 점수 상위 식당을 자연어로 요약한다."""
    areas = {p.area for p in store.places.values()}
    if area not in areas:
        raise HTTPException(404, f"지원하지 않는 지역입니다. 가능한 지역: {sorted(areas)}")

    me = store.users[store.ME_ID]
    friend_ids = store.follows.get(me.id, set())
    friend_records = [
        r for r in store.visible_records(me.id)
        if r.user_id in friend_ids and store.places[r.place_id].area == area
    ]
    with_friends = {r.place_id for r in friend_records}
    top = [s for s in scored_for(me) if s.place.area == area and s.place.id in with_friends][:TOP_PLACES]
    if not top:
        return Briefing(area=area, sentences=[BriefingSentence(
            text=f"아직 {area}에 친구 기록이 없어요. 먼저 다녀온 곳을 기록해 보세요.", record_ids=[])],
            places=[], generated_by="template")

    by_place = {s.place.id: [r for r in friend_records if r.place_id == s.place.id] for s in top}
    sentences = _llm_sentences(area, top, by_place)
    if sentences:
        return Briefing(area=area, sentences=sentences, places=top, generated_by="llm")
    return Briefing(area=area, sentences=_template_sentences(area, top, by_place), places=top,
                    generated_by="template")


def _facts(area: str, top: list[ScoredPlace], by_place: dict[str, list[Record]]) -> dict:
    return {
        "area": area,
        "places": [
            {
                "name": s.place.name,
                "category": s.place.category,
                "tags": s.place.tags,
                "friend_records": [
                    {
                        "record_id": r.id,
                        "friend": store.users[r.user_id].nickname,
                        "rating": r.rating,
                        "visit_count": r.visit_no,
                        "memo": r.memo,
                        "tags": r.tags,
                    }
                    for r in by_place[s.place.id]
                ],
            }
            for s in top
        ],
    }


def _llm_sentences(area: str, top: list[ScoredPlace], by_place: dict[str, list[Record]]) -> list[BriefingSentence]:
    prompt = json.dumps(_facts(area, top, by_place), ensure_ascii=False)
    if prompt in _cache:
        return _cache[prompt]
    data = llm.complete_json(_SYSTEM, prompt, _SCHEMA)
    if data is None:
        return []
    place_of = {r.id: pid for pid, rs in by_place.items() for r in rs}
    # 환각 방지: 실제로 넘긴 기록을 근거로 달지 않은 문장은 버린다.
    result = []
    for s in data.get("sentences", []):
        ids = [i for i in s.get("record_ids", []) if i in place_of]
        # 한 문장이 여러 식당의 기록을 근거로 달면 내용이 뒤섞였을 가능성이 커서 버린다.
        if len({place_of[i] for i in ids}) > 1:
            continue
        # 작은 모델이 문장 끝에 "record_ids: [...]"를 섞어 쓰는 경우가 있어 지운다.
        text = _ID_LEAK.sub("", s.get("text", "")).strip()
        if ids and text:
            result.append(BriefingSentence(text=text, record_ids=ids))
    if result:
        if len(_cache) >= _CACHE_MAX:
            _cache.clear()
        _cache[prompt] = result
    return result


_ID_LEAK = re.compile(r"\s*\(?\s*record_ids?\s*[:=].*$", re.IGNORECASE)


def _template_sentences(area: str, top: list[ScoredPlace], by_place: dict[str, list[Record]]) -> list[BriefingSentence]:
    sentences = []
    for i, s in enumerate(top):
        rs = by_place[s.place.id]
        names = list(dict.fromkeys(store.users[r.user_id].nickname for r in rs))
        tags = list(dict.fromkeys(t for r in rs for t in r.tags)) or s.place.tags
        head = f"{area}에서는 " if i == 0 else ""
        who = f"친구 {len(names)}명({', '.join(names)})이" if len(names) > 1 else f"{names[0]}님이"
        phrase = "·".join(tags[:2])
        what = phrase if phrase.endswith("맛집") else f"{phrase} 맛집".strip()
        text = f"{head}{who} '{s.place.name}'{_eul(s.place.name)} {what}으로 꼽았어요."
        regular = max(rs, key=lambda r: r.visit_no)
        if regular.visit_no >= 3:
            text += f" {store.users[regular.user_id].nickname}님은 {regular.visit_no}번이나 다녀왔어요."
        sentences.append(BriefingSentence(text=text, record_ids=[r.id for r in rs]))
    return sentences


def _eul(word: str) -> str:
    """목적격 조사. 마지막 글자에 받침이 있으면 '을', 없으면(또는 한글이 아니면) '를'."""
    last = word[-1]
    if "가" <= last <= "힣" and (ord(last) - ord("가")) % 28:
        return "을"
    return "를"
