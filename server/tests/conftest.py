import copy
import os
import tempfile

# app을 import하기 전에 정해야 하는 값. 업로드는 임시 폴더에 쓰고, .env 설정과 상관없이 LLM은 끈다.
os.environ["MUKLOG_UPLOAD_DIR"] = tempfile.mkdtemp(prefix="muklog-uploads-")
os.environ["MUKLOG_LLM"] = "off"

import pytest  # noqa: E402

from app import store  # noqa: E402

_STATE = ["users", "onboarding", "base_temps", "follows", "dislikes", "places", "place_priors", "records",
          "record_attrs", "trust_events"]


@pytest.fixture(autouse=True)
def reset_store():
    """테스트마다 인메모리 저장소를 시드 상태로 되돌린다. 기록 처리가 벡터·온도를 바꾸기 때문."""
    saved = {name: copy.deepcopy(getattr(store, name)) for name in _STATE}
    yield
    for name, value in saved.items():
        setattr(store, name, value)
