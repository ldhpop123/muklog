from datetime import datetime
from typing import Literal

import re

from pydantic import BaseModel, Field, field_validator

Score = float  # -1 ~ +1


class TasteVector(BaseModel):
    saltiness: Score = Field(ge=-1, le=1)
    spiciness: Score = Field(ge=-1, le=1)
    ambience: Score = Field(ge=-1, le=1)
    value: Score = Field(ge=-1, le=1)
    cuisine: Score = Field(ge=-1, le=1)

    def as_list(self) -> list[float]:
        return [self.saltiness, self.spiciness, self.ambience, self.value, self.cuisine]

    @classmethod
    def from_list(cls, v: list[float]) -> "TasteVector":
        clamp = [min(1.0, max(-1.0, x)) for x in v]
        return cls(saltiness=clamp[0], spiciness=clamp[1], ambience=clamp[2], value=clamp[3], cuisine=clamp[4])


class Attributes(BaseModel):
    """리뷰 한 건에서 추출한 미식 속성 (README 6.1). 판단이 어려운 차원은 null."""

    saltiness: Score | None = Field(default=None, ge=-1, le=1)
    spiciness: Score | None = Field(default=None, ge=-1, le=1)
    ambience: Score | None = Field(default=None, ge=-1, le=1)
    value: Score | None = Field(default=None, ge=-1, le=1)
    cuisine: Score | None = Field(default=None, ge=-1, le=1)
    tags: list[str] = []
    evidence: list[str] = []

    def as_list(self) -> list[float | None]:
        return [self.saltiness, self.spiciness, self.ambience, self.value, self.cuisine]


class User(BaseModel):
    id: str
    nickname: str
    avatar_url: str
    taste: TasteVector
    trust_temp: float = 36.5
    title: str | None = None
    level: str = "새내기 먹로거"


class Place(BaseModel):
    id: str
    name: str
    lat: float
    lng: float
    area: str
    category: str
    taste: TasteVector
    tags: list[str] = []
    revisit_total: int = 0
    address: str | None = None
    external_id: str | None = None


class PlaceIn(BaseModel):
    """식당 검색 후보를 먹로그 식당으로 등록할 때 보내는 값."""

    external_id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=100)
    category: str = Field(min_length=1, max_length=50)
    address: str = Field(default="", max_length=200)
    lat: float = Field(ge=33, le=39)
    lng: float = Field(ge=124, le=132)


class PlaceCandidate(PlaceIn):
    # 이미 먹로그에 등록된 식당이면 그 id
    place_id: str | None = None


class UploadOut(BaseModel):
    url: str


# 업로드 API가 만든 경로만 허용한다. 외부 URL이나 다른 경로를 기록에 넣지 못하게.
UPLOAD_URL_PATTERN = re.compile(r"^/uploads/[0-9a-f]{32}\.(jpg|png|webp|heic)$")
MAX_PHOTOS = 4


Visibility = Literal["private", "friends", "public"]


class RecordIn(BaseModel):
    place_id: str
    rating: float = Field(ge=1, le=5)
    memo: str = ""
    tags: list[str] = []
    visibility: Visibility = "friends"
    inspired_by_record_id: str | None = None
    photo_urls: list[str] = Field(default=[], max_length=MAX_PHOTOS)

    @field_validator("photo_urls")
    @classmethod
    def _only_uploaded(cls, urls: list[str]) -> list[str]:
        for url in urls:
            if not UPLOAD_URL_PATTERN.match(url):
                raise ValueError("사진은 /uploads 로 올린 것만 첨부할 수 있어요")
        return list(dict.fromkeys(urls))


class Record(RecordIn):
    id: str
    user_id: str
    visit_no: int
    visited_at: datetime


class ScoredPlace(BaseModel):
    place: Place
    score: float
    reason: str | None = None


class PartyRequest(BaseModel):
    member_ids: list[str]


DislikeKind = Literal["불호", "알레르기"]


class Dislike(BaseModel):
    target: str = Field(min_length=1, description="메뉴·태그·카테고리 이름. 예: 마라, 노포, 갑각류")
    kind: DislikeKind = "불호"


class DimensionDiff(BaseModel):
    dimension: str
    label: str
    me: float
    them: float
    diff: float


class Coupling(BaseModel):
    user: User
    percent: int
    dimensions: list[DimensionDiff]
    shared_place_count: int
    # 상대는 가 봤고 나는 안 가 본 곳 중 나에게 맞는 순
    suggestions: list[ScoredPlace]


class BriefingSentence(BaseModel):
    text: str
    record_ids: list[str]


class Briefing(BaseModel):
    area: str
    sentences: list[BriefingSentence]
    places: list[ScoredPlace]
    generated_by: Literal["llm", "template"]


class PublicUser(BaseModel):
    """친구가 아닌 사람에게도 보여도 되는 프로필. 취향 벡터는 빼고 담는다."""

    id: str
    nickname: str
    avatar_url: str
    trust_temp: float
    level: str
    title: str | None = None


class RankingEntry(BaseModel):
    rank: int
    user: PublicUser
