import base64
import os
from dataclasses import dataclass
from functools import lru_cache

from pydantic import ValidationError

import config
from schemas import NutritionEstimate


class EstimatorError(Exception):
    """Base class for nutrition estimation failures."""


class EstimatorNotConfigured(EstimatorError):
    """The estimator cannot run, e.g. no API key is set."""


class EstimatorTimeout(EstimatorError):
    """The AI provider did not answer in time."""


class EstimatorFailed(EstimatorError):
    """The AI provider failed or returned no usable estimate."""


PROVIDER = "openai"

# Bump when INSTRUCTIONS, PROMPT or the NutritionEstimate schema changes, so
# each saved meal records which prompt produced it. A test pins the hash.
PROMPT_VERSION = "1"

INSTRUCTIONS = (
    "You are a careful nutrition-estimation assistant. "
    "Provide approximate calorie and macronutrient estimates. "
    "Do not present estimates as exact measurements. "
    "List important assumptions, especially uncertain "
    "portion sizes."
)

PROMPT = (
    "Estimate the nutrition of the meal described below. "
    "Use the image when one is provided. "
    "Account for visible portion sizes, sauces, oils, "
    "drinks, and side dishes. Give a realistic range "
    "rather than pretending the estimate is exact.\n\n"
    "User description: {message}"
)


@dataclass(frozen=True)
class EstimateResult:
    """An estimate and what produced it."""

    estimate: NutritionEstimate
    provider: str
    model: str
    prompt_version: str


@lru_cache(maxsize=1)
def _client():
    # Imported lazily: the SDK is slow to import and only needed here.
    from openai import OpenAI

    return OpenAI(
        api_key=os.environ["OPENAI_API_KEY"],
        timeout=config.OPENAI_TIMEOUT_SECONDS,
        max_retries=config.OPENAI_MAX_RETRIES,
    )


def encode_image(
    image_bytes: bytes,
    content_type: str,
) -> str:
    """Convert image bytes into a base64 data URL."""

    encoded = base64.b64encode(
        image_bytes
    ).decode("utf-8")

    return (
        f"data:{content_type};base64,{encoded}"
    )


def estimate_nutrition(
    message: str,
    image_bytes: bytes | None = None,
    image_content_type: str | None = None,
) -> EstimateResult:
    """Estimate nutrition from meal text and an optional image."""

    if not os.environ.get("OPENAI_API_KEY"):
        raise EstimatorNotConfigured(
            "The OPENAI_API_KEY environment variable is not set."
        )

    import openai

    content: list[dict] = [
        {
            "type": "input_text",
            "text": PROMPT.format(message=message),
        }
    ]

    if (
        image_bytes is not None
        and image_content_type is not None
    ):
        content.append(
            {
                "type": "input_image",
                "image_url": encode_image(
                    image_bytes,
                    image_content_type,
                ),
            }
        )

    # Read once, so the model recorded is the model asked.
    model = config.OPENAI_MODEL

    try:
        response = _client().responses.parse(
            model=model,
            instructions=INSTRUCTIONS,
            input=[
                {
                    "role": "user",
                    "content": content,
                }
            ],
            text_format=NutritionEstimate,
        )
    # APITimeoutError subclasses OpenAIError, so it must come first.
    except openai.APITimeoutError as exc:
        raise EstimatorTimeout("The AI provider timed out.") from exc
    except (openai.OpenAIError, ValidationError) as exc:
        raise EstimatorFailed(f"The AI provider request failed: {exc}") from exc

    estimate = response.output_parsed

    if estimate is None:
        raise EstimatorFailed(
            "The model did not return a nutrition estimate."
        )

    return EstimateResult(
        estimate=estimate,
        provider=PROVIDER,
        model=model,
        prompt_version=PROMPT_VERSION,
    )
