import atexit
import copy
import os
import shutil
import tempfile

# app을 import하기 전에 정해야 하는 값. 업로드는 임시 폴더에 쓰고, .env 설정과 상관없이 LLM은 끈다.
os.environ["MUKLOG_UPLOAD_DIR"] = tempfile.mkdtemp(prefix="muklog-uploads-")
atexit.register(shutil.rmtree, os.environ["MUKLOG_UPLOAD_DIR"], ignore_errors=True)
os.environ["MUKLOG_LLM"] = "off"

import pytest  # noqa: E402

from app import store  # noqa: E402

_STATE = ["users", "onboarding", "base_temps", "follows", "dislikes", "places", "place_priors", "records",
          "record_attrs", "trust_events"]


@pytest.fixture(autouse=True)
def no_external_keys(monkeypatch):
    """server/.env의 실제 네이버 키로 테스트가 외부 API를 부르지 않게 한다. 필요한 테스트는 직접 setenv."""
    for name in ("NAVER_SEARCH_CLIENT_ID", "NAVER_SEARCH_CLIENT_SECRET", "NAVER_MAP_CLIENT_ID", "NAVER_MAP_CLIENT_SECRET"):
        monkeypatch.delenv(name, raising=False)


@pytest.fixture(autouse=True)
def reset_store():
    """테스트마다 인메모리 저장소를 시드 상태로 되돌린다. 기록 처리가 벡터·온도를 바꾸기 때문."""
    saved = {name: copy.deepcopy(getattr(store, name)) for name in _STATE}
    yield
    for name, value in saved.items():
        setattr(store, name, value)
