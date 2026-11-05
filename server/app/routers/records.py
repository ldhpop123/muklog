from fastapi import APIRouter, BackgroundTasks, HTTPException

from .. import store
from ..schemas import Attributes, Record, RecordIn
from .uploads import uploaded_exists

router = APIRouter(prefix="/records", tags=["records"])


@router.post("", status_code=201)
def create_record(data: RecordIn, background: BackgroundTasks) -> Record:
    if data.place_id not in store.places:
        raise HTTPException(404, "식당을 찾을 수 없습니다")
    if data.inspired_by_record_id is not None:
        source = store.find_record(data.inspired_by_record_id)
        # 볼 수 없는 기록은 없는 기록과 같은 응답을 준다(존재 여부 노출 방지).
        if source is None or not store.can_see(store.ME_ID, source):
            raise HTTPException(400, "보고 온 기록을 찾을 수 없습니다")
        if source.user_id == store.ME_ID:
            raise HTTPException(400, "내 기록을 보고 왔다고 표시할 수 없습니다")
        if source.place_id != data.place_id:
            raise HTTPException(400, "보고 온 기록과 다른 식당입니다")

    missing = [u for u in data.photo_urls if not uploaded_exists(u)]
    if missing:
        raise HTTPException(400, "올라가지 않은 사진이 있어요. 사진을 다시 올려 주세요")

    record = store.add_record(store.ME_ID, data)
    # 사용자는 추출·벡터 갱신을 기다리지 않는다 (README 9.1).
    background.add_task(store.process_record, record.id)
    return record


@router.get("/{record_id}/attributes")
def record_attributes(record_id: str) -> Attributes:
    """기록에서 추출한 미식 속성. 처리 전이면 404."""
    record = store.find_record(record_id)
    if record is None or not store.can_see(store.ME_ID, record) or record_id not in store.record_attrs:
        raise HTTPException(404, "추출된 속성이 없습니다")
    return store.record_attrs[record_id]
