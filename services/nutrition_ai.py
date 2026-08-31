import base64
import os

from openai import OpenAI

from schemas import NutritionEstimate


client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY")
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
) -> NutritionEstimate:
    """Estimate nutrition from meal text and an optional image."""

    content: list[dict] = [
        {
            "type": "input_text",
            "text": (
                "Estimate the nutrition of the meal described below. "
                "Use the image when one is provided. "
                "Account for visible portion sizes, sauces, oils, "
                "drinks, and side dishes. Give a realistic range "
                "rather than pretending the estimate is exact.\n\n"
                f"User description: {message}"
            ),
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

    response = client.responses.parse(
        model="gpt-4.1-mini",
        instructions=(
            "You are a careful nutrition-estimation assistant. "
            "Provide approximate calorie and macronutrient estimates. "
            "Do not present estimates as exact measurements. "
            "List important assumptions, especially uncertain "
            "portion sizes."
        ),
        input=[
            {
                "role": "user",
                "content": content,
            }
        ],
        text_format=NutritionEstimate,
    )

    estimate = response.output_parsed

    if estimate is None:
        raise RuntimeError(
            "The model did not return a nutrition estimate."
        )

    return estimate