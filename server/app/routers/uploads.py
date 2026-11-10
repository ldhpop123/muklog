"""사진 업로드. MVP라 로컬 폴더에 저장하고 /uploads/{파일명}으로 정적 서빙한다.

TODO(storage): S3 호환 오브젝트 스토리지로 이전 (README 9.1).
주의: 파일명이 무작위라 추측은 어렵지만, URL을 아는 사람은 누구나 볼 수 있다. 비공개 기록 사진도 마찬가지다.
"""

import os
import uuid
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from ..schemas import UploadOut

from ..auth import CurrentUser

router = APIRouter(prefix="/uploads", tags=["uploads"])

UPLOAD_DIR = Path(os.getenv("MUKLOG_UPLOAD_DIR", Path(__file__).resolve().parents[2] / "uploads"))
MAX_BYTES = 10 * 1024 * 1024
_CHUNK = 1024 * 1024


# multipart 경계·헤더 몫으로 본문에 더 허용하는 여유분
_BODY_OVERHEAD = 64 * 1024


class _TooLarge(Exception):
    pass


class UploadSizeLimit:
    """POST /uploads 요청 본문을 받는 도중에 크기를 센다.

    FastAPI는 핸들러를 부르기 전에 multipart 본문 전체를 임시 파일로 받아 두므로, 핸들러 안의 검사만으로는
    큰 요청이 디스크를 다 쓴 뒤에야 막힌다. Content-Length가 크면 바로 413을 주고,
    Content-Length가 없거나 거짓이어도 실제로 받은 바이트가 한도를 넘는 순간 끊는다.
    TODO(deploy): 리버스 프록시에서도 본문 크기를 제한한다.
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] != "POST" or scope["path"].rstrip("/") != "/uploads":
            await self.app(scope, receive, send)
            return

        limit = MAX_BYTES + _BODY_OVERHEAD
        length = dict(scope["headers"]).get(b"content-length")
        if length is not None and length.isdigit() and int(length) > limit:
            await _reject(scope, receive, send)
            return

        received = 0
        started = False
        rejected = False

        async def counting_receive() -> Message:
            # 한도를 넘으면 그 자리에서 413을 보낸다. FastAPI는 본문 파싱 중 예외를 400으로 바꾸므로
            # 예외만 던져서는 413이 나가지 않는다. 그 뒤 앱이 보내는 응답은 tracking_send가 버린다.
            nonlocal received, rejected
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    if not started and not rejected:
                        rejected = True
                        await _reject(scope, receive, send)
                    raise _TooLarge
            return message

        async def tracking_send(message: Message) -> None:
            nonlocal started
            if rejected:
                return
            started = started or message["type"] == "http.response.start"
            await send(message)

        try:
            await self.app(scope, counting_receive, tracking_send)
        except _TooLarge:
            pass


async def _reject(scope: Scope, receive: Receive, send: Send) -> None:
    await JSONResponse({"detail": "사진은 10MB까지 올릴 수 있어요"}, status_code=413)(scope, receive, send)


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
async def upload(me_id: CurrentUser, file: UploadFile) -> UploadOut:
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
