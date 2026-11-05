import copy

import pytest

from app import store

_STATE = ["users", "onboarding", "base_temps", "follows", "dislikes", "places", "records",
          "record_attrs", "trust_events"]


@pytest.fixture(autouse=True)
def reset_store():
    """테스트마다 인메모리 저장소를 시드 상태로 되돌린다. 기록 처리가 벡터·온도를 바꾸기 때문."""
    saved = {name: copy.deepcopy(getattr(store, name)) for name in _STATE}
    yield
    for name, value in saved.items():
        setattr(store, name, value)
