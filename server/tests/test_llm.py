import httpx

from app import llm

SCHEMA = {"type": "object"}


class _Res:
    def __init__(self, body):
        self._body = body

    def raise_for_status(self):
        pass

    def json(self):
        return self._body


def test_off_by_default(monkeypatch):
    monkeypatch.delenv("MUKLOG_LLM", raising=False)
    assert llm.complete_json("s", "u", SCHEMA) is None


def test_ollama_parses_json(monkeypatch):
    monkeypatch.setenv("MUKLOG_LLM", "ollama")
    sent = {}

    def fake_post(url, json, timeout):
        sent.update(url=url, body=json)
        return _Res({"message": {"content": '{"saltiness": -0.5}'}})

    monkeypatch.setattr(httpx, "post", fake_post)
    assert llm.complete_json("s", "u", SCHEMA) == {"saltiness": -0.5}
    assert sent["url"].endswith("/api/chat")
    assert sent["body"]["model"] == "qwen3:8b"
    assert sent["body"]["format"] == SCHEMA


def test_ollama_down_returns_none(monkeypatch):
    monkeypatch.setenv("MUKLOG_LLM", "ollama")

    def fail(*a, **k):
        raise httpx.ConnectError("refused")

    monkeypatch.setattr(httpx, "post", fail)
    assert llm.complete_json("s", "u", SCHEMA) is None


def test_ollama_bad_json_returns_none(monkeypatch):
    monkeypatch.setenv("MUKLOG_LLM", "ollama")
    monkeypatch.setattr(httpx, "post", lambda *a, **k: _Res({"message": {"content": "not json"}}))
    assert llm.complete_json("s", "u", SCHEMA) is None
