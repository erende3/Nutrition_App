"""Pin the /v1 response contract: field sets, JSON types, the created_at
format, and what stays internal. JSON key order is not part of the contract.
"""

import re
from datetime import date

from database import SessionLocal
from models import Meal
from test_contract import (
    INT,
    LIST_OF_STR,
    NUMBER,
    ONBOARDING,
    PROFILE_AFTER_ONBOARDING,
    PROFILE_BEFORE_ONBOARDING,
    PROFILE_INPUT,
    STR,
    assert_shape,
    nullable,
)

JPEG_BYTES = b"\xff\xd8\xff\xe0jpeg-bytes"

MEAL = {
    "id": INT,
    "meal_name": STR,
    "calories": INT,
    "protein_g": NUMBER,
    "carbohydrates_g": NUMBER,
    "fat_g": NUMBER,
    "confidence": NUMBER,
    "calorie_low": INT,
    "calorie_high": INT,
    "assumptions": nullable(LIST_OF_STR),
    "source": nullable(STR),
    "description": nullable(STR),
    "local_date": STR,
    "created_at": STR,
}

INTERNAL_MEAL_FIELDS = {"user_id", "ai_provider", "ai_model", "prompt_version", "ai_payload"}

UTC_SECONDS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def log_meal(client, message: str | None = "chicken and rice", files=None):
    data = {} if message is None else {"message": message}
    return client.post("/v1/meals/estimate", data=data, files=files)


def stored(meal_id):
    with SessionLocal() as db:
        return db.get(Meal, meal_id)


def test_estimate_returns_201_and_the_saved_meal(client, fake_estimate):
    response = log_meal(client)

    assert response.status_code == 201
    meal = response.json()
    assert_shape(meal, MEAL)
    assert meal["meal_name"] == fake_estimate.meal_name
    assert meal["assumptions"] == fake_estimate.assumptions
    assert meal["source"] == "text"
    assert meal["description"] == "chicken and rice"
    assert meal["local_date"] == date.today().isoformat()
    assert stored(meal["id"]) is not None


def test_meal_never_exposes_internal_fields(client):
    meal = log_meal(client).json()

    assert INTERNAL_MEAL_FIELDS.isdisjoint(meal)


def test_created_at_is_utc_with_z_to_the_second(client):
    meal = log_meal(client).json()

    assert UTC_SECONDS.match(meal["created_at"])
    saved = stored(meal["id"]).created_at
    assert meal["created_at"] == saved.strftime("%Y-%m-%dT%H:%M:%SZ")


def test_photo_meal_without_text_has_no_description(client, fake_estimator):
    for message in (None, "", "   "):
        response = log_meal(client, message, {"image": ("meal.jpg", JPEG_BYTES, "image/jpeg")})

        assert response.status_code == 201
        meal = response.json()
        assert meal["source"] == "photo"
        assert meal["description"] is None
        assert stored(meal["id"]).description is None

    assert {call["message"] for call in fake_estimator} == {"Estimate this meal from the image."}


def test_photo_meal_with_text_keeps_it(client):
    response = log_meal(client, "  soup  ", {"image": ("meal.jpg", JPEG_BYTES, "image/jpeg")})

    assert response.json()["description"] == "  soup  "


def test_delete_returns_204_with_no_body(client):
    meal_id = log_meal(client).json()["id"]

    response = client.delete(f"/v1/meals/{meal_id}")

    assert response.status_code == 204
    assert response.content == b""
    assert stored(meal_id) is None


def test_profile_and_onboarding_keep_their_shapes(client):
    before = client.get("/v1/users/profile")
    onboarding = client.post("/v1/users/onboarding", json=PROFILE_INPUT)
    after = client.get("/v1/users/profile")

    assert before.status_code == onboarding.status_code == after.status_code == 200
    assert_shape(before.json(), PROFILE_BEFORE_ONBOARDING)
    assert_shape(onboarding.json(), ONBOARDING)
    assert_shape(after.json(), PROFILE_AFTER_ONBOARDING)


# Every v1 operation's success response, as a named schema (None: no body).
# Paths are relative to the /v1 mount.
EXPECTED_V1_OPERATIONS = {
    ("post", "/meals/estimate"): ("201", "MealResource"),
    ("delete", "/meals/{meal_id}"): ("204", None),
    ("get", "/users/profile"): ("200", "UserProfileResponse"),
    ("post", "/users/onboarding"): ("200", "UserOnboardingResponse"),
}


def success(operation):
    status = next(code for code in operation["responses"] if code.startswith("2"))
    content = operation["responses"][status].get("content")
    if content is None:
        return status, None
    return status, content["application/json"]["schema"]["$ref"].rsplit("/", 1)[-1]


def test_every_v1_operation_declares_its_success_response(client):
    openapi = client.get("/v1/openapi.json").json()

    declared = {
        (method, path): success(operation)
        for path, operations in openapi["paths"].items()
        for method, operation in operations.items()
    }

    assert declared == EXPECTED_V1_OPERATIONS
