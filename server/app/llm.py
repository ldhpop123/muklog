"""LLM 호출 공통부. 속성 추출(6.1)과 지역 브리핑(6.6)이 쓴다.

`MUKLOG_LLM`으로 제공자를 고른다.
- off (기본): 호출하지 않는다. 테스트와 키 없는 시연용.
- ollama: 로컬 Ollama 서버(`OLLAMA_URL`, 기본 http://localhost:11434)의 `MUKLOG_LLM_MODEL`(기본 qwen3:8b).
- claude: Claude API의 `MUKLOG_LLM_MODEL`(기본 claude-haiku-5-5). 인증은 SDK 기본 순서
  (ANTHROPIC_API_KEY → `ant auth login` 프로필 등)를 따른다.

꺼져 있거나 호출이 실패하면 None을 돌려주고, 호출하는 쪽은 규칙 기반 결과로 대신한다.
"""

import json
import logging
import os
from typing import Any

import anthropic
import httpx

log = logging.getLogger(__name__)

DEFAULT_MODELS = {"ollama": "qwen3:8b", "claude": "claude-haiku-5-5"}

_claude: anthropic.Anthropic | None = None


def provider() -> str:
    return os.getenv("MUKLOG_LLM", "off").lower()


def enabled() -> bool:
    return provider() in DEFAULT_MODELS


def _model() -> str:
    return os.getenv("MUKLOG_LLM_MODEL", DEFAULT_MODELS[provider()])


def complete_json(system: str, user: str, schema: dict[str, Any], max_tokens: int = 4000) -> dict[str, Any] | None:
    """구조화 출력(JSON 스키마)으로 한 번 호출한다. 실패하면 None."""
    if provider() == "ollama":
        text = _ollama(system, user, schema)
    elif provider() == "claude":
        text = _claude_text(system, user, schema, max_tokens)
    else:
        return None
    if text is None:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        log.warning("LLM 응답 JSON 파싱 실패")
        return None


def _ollama(system: str, user: str, schema: dict[str, Any]) -> str | None:
    url = os.getenv("OLLAMA_URL", "http://localhost:11434")
    try:
        res = httpx.post(
            f"{url}/api/chat",
            json={
                "model": _model(),
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
                "format": schema,
                "stream": False,
                # 추론 모드를 끄고 바로 JSON을 쓰게 한다. 짧은 추출·요약에는 추론이 필요 없고 지연만 늘어난다.
                "think": False,
                "options": {"temperature": 0},
            },
            timeout=120.0,
        )
        res.raise_for_status()
    except httpx.HTTPStatusError as e:
        log.warning("Ollama 호출 실패 (%s): %s", e.response.status_code, e.response.text[:200])
        return None
    except httpx.HTTPError as e:
        log.warning("Ollama 연결 실패, 규칙 기반으로 대체: %s", e)
        return None
    return res.json().get("message", {}).get("content")


def _get_claude() -> anthropic.Anthropic:
    global _claude
    if _claude is None:
        _claude = anthropic.Anthropic(timeout=30.0)
    return _claude


def _claude_text(system: str, user: str, schema: dict[str, Any], max_tokens: int) -> str | None:
    try:
        response = _get_claude().messages.create(
            model=_model(),
            max_tokens=max_tokens,
            output_config={"effort": "low", "format": {"type": "json_schema", "schema": schema}},
            system=system,
            messages=[{"role": "user", "content": user}],
        )
    except anthropic.RateLimitError:
        log.warning("LLM 호출 한도 초과, 규칙 기반으로 대체")
        return None
    except anthropic.APIStatusError as e:
        log.warning("LLM 호출 실패 (%s): %s", e.status_code, e.message)
        return None
    except anthropic.APIConnectionError:
        log.warning("LLM 연결 실패, 규칙 기반으로 대체")
        return None

    if response.stop_reason != "end_turn":
        log.warning("LLM 응답이 완료되지 않음: %s", response.stop_reason)
        return None
    return next((b.text for b in response.content if b.type == "text"), None)
