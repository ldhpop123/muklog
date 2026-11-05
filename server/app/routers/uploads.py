"""사진 업로드. MVP라 로컬 폴더에 저장하고 /uploads/{파일명}으로 정적 서빙한다.

TODO(storage): S3 호환 오브젝트 스토리지로 이전 (README 9.1).
주의: 파일명이 무작위라 추측은 어렵지만, URL을 아는 사람은 누구나 볼 수 있다. 비공개 기록 사진도 마찬가지다.
"""

import os
import uuid
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile

from ..schemas import UploadOut

router = APIRouter(prefix="/uploads", tags=["uploads"])

UPLOAD_DIR = Path(os.getenv("MUKLOG_UPLOAD_DIR", Path(__file__).resolve().parents[2] / "uploads"))
MAX_BYTES = 10 * 1024 * 1024
_CHUNK = 1024 * 1024


def detect_image(head: bytes) -> str | None:
    """파일 앞부분(매직 바이트)으로 이미지 형식을 판별한다. 확장자·Content-Type은 믿지 않는다."""
    if head.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    if head[4:8] == b"ftyp" and head[8:12] in (b"heic", b"heix", b"mif1", b"msf1"):
        return "heic"
    return None


def uploaded_exists(url: str) -> bool:
    """'/uploads/파일명'이 실제로 저장된 파일인지."""
    return (UPLOAD_DIR / url.removeprefix("/uploads/")).is_file()


@router.post("", status_code=201)
async def upload(file: UploadFile) -> UploadOut:
    """이미지 1장을 받아 저장하고 URL을 돌려준다. jpg·png·webp·heic, 10MB 이하."""
    head = await file.read(16)
    kind = detect_image(head)
    if kind is None:
        raise HTTPException(415, "jpg, png, webp, heic 사진만 올릴 수 있어요")

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    name = f"{uuid.uuid4().hex}.{kind}"
    path = UPLOAD_DIR / name
    size = len(head)
    try:
        with path.open("wb") as out:
            out.write(head)
            while chunk := await file.read(_CHUNK):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise HTTPException(413, "사진은 10MB까지 올릴 수 있어요")
                out.write(chunk)
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return UploadOut(url=f"/uploads/{name}")
