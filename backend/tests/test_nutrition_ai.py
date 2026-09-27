import base64
import hashlib
import json
from types import SimpleNamespace

import httpx
import openai
import pytest
from pydantic import ValidationError

import config
from schemas import NutritionEstimate
from services.nutrition_ai import (
    INSTRUCTIONS,
    PROMPT,
    PROMPT_VERSION,
    EstimatorFailed,
    EstimatorNotConfigured,
    EstimatorTimeout,
    estimate_nutrition,
)

REQUEST = httpx.Request("POST", "https://api.openai.com/v1/responses")


@pytest.fixture
def fake_openai(monkeypatch, fake_estimate):
    """Stand in for openai.OpenAI; records constructor and parse() kwargs."""
    state = SimpleNamespace(clients=[], calls=[], result=fake_estimate, error=None)

    class FakeResponses:
        def parse(self, **kwargs):
            state.calls.append(kwargs)
            if state.error is not None:
                raise state.error
            return SimpleNamespace(output_parsed=state.result)

    class FakeOpenAI:
        def __init__(self, **kwargs):
            state.clients.append(kwargs)
            self.responses = FakeResponses()

    monkeypatch.setattr(openai, "OpenAI", FakeOpenAI)
    return state


def content_parts(call):
    return call["input"][0]["content"]


def validation_error():
    try:
        NutritionEstimate.model_validate({})
    except ValidationError as exc:
        return exc


def test_returns_the_parsed_estimate(fake_openai, fake_estimate):
    assert estimate_nutrition("two eggs").estimate == fake_estimate


def test_result_records_provider_model_and_prompt_version(fake_openai):
    result = estimate_nutrition("two eggs")

    assert result.provider == "openai"
    assert result.model == config.OPENAI_MODEL
    assert result.prompt_version == PROMPT_VERSION


def test_client_uses_configured_timeout_retries_and_model(fake_openai):
    estimate_nutrition("two eggs")

    assert fake_openai.clients == [
        {
            "api_key": "test-key-not-used",
            "timeout": config.OPENAI_TIMEOUT_SECONDS,
            "max_retries": config.OPENAI_MAX_RETRIES,
        }
    ]
    assert fake_openai.calls[0]["model"] == config.OPENAI_MODEL


def test_model_follows_config(fake_openai, monkeypatch):
    monkeypatch.setattr(config, "OPENAI_MODEL", "some-other-model")

    estimate_nutrition("two eggs")

    assert fake_openai.calls[0]["model"] == "some-other-model"


def test_recorded_model_follows_config(fake_openai, monkeypatch):
    monkeypatch.setattr(config, "OPENAI_MODEL", "some-other-model")

    assert estimate_nutrition("two eggs").model == "some-other-model"


# The prompt, instructions and output schema each prompt version was made of.
# Changing any of them changes the hash: bump PROMPT_VERSION in
# services/nutrition_ai.py, then add the new version and hash here.
PROMPT_HASHES = {
    "1": "ac64dc3a2289e768575966c1bcfebc08c85d4daf0fc1e493dc2c0750219e70f9",
}


def test_prompt_is_pinned_to_its_version():
    prompt = json.dumps(
        [INSTRUCTIONS, PROMPT, NutritionEstimate.model_json_schema()],
        sort_keys=True,
    )

    assert hashlib.sha256(prompt.encode()).hexdigest() == PROMPT_HASHES[PROMPT_VERSION]


def test_prompt_contains_message_and_no_image_part(fake_openai):
    estimate_nutrition("two eggs and toast")

    parts = content_parts(fake_openai.calls[0])
    assert [part["type"] for part in parts] == ["input_text"]
    assert "two eggs and toast" in parts[0]["text"]


def test_image_is_sent_as_data_url(fake_openai):
    estimate_nutrition("lunch", image_bytes=b"png-bytes", image_content_type="image/png")

    parts = content_parts(fake_openai.calls[0])
    assert parts[1] == {
        "type": "input_image",
        "image_url": "data:image/png;base64," + base64.b64encode(b"png-bytes").decode(),
    }


def test_client_is_built_once(fake_openai):
    estimate_nutrition("breakfast")
    estimate_nutrition("lunch")

    assert len(fake_openai.clients) == 1
    assert len(fake_openai.calls) == 2


def test_missing_parse_result_is_a_failure(fake_openai):
    fake_openai.result = None

    with pytest.raises(EstimatorFailed):
        estimate_nutrition("mystery meal")


def test_sdk_timeout_is_a_timeout(fake_openai):
    fake_openai.error = openai.APITimeoutError(request=REQUEST)

    with pytest.raises(EstimatorTimeout):
        estimate_nutrition("slow meal")


@pytest.mark.parametrize(
    "error",
    [
        openai.APIConnectionError(request=REQUEST),
        openai.RateLimitError(
            "rate limited", response=httpx.Response(429, request=REQUEST), body=None
        ),
        openai.APIStatusError(
            "server error", response=httpx.Response(500, request=REQUEST), body=None
        ),
        validation_error(),
    ],
    ids=["connection", "rate-limit", "status-500", "invalid-output"],
)
def test_sdk_and_parse_errors_are_failures(fake_openai, error):
    fake_openai.error = error

    with pytest.raises(EstimatorFailed):
        estimate_nutrition("meal")


def test_missing_api_key_is_not_configured(fake_openai, monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY")

    with pytest.raises(EstimatorNotConfigured):
        estimate_nutrition("meal")

    assert fake_openai.clients == []
