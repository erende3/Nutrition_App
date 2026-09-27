"""Pin the /v1 error envelope: every failure is
{"error": {"code": <stable code>, "message": <text to show>}}, plus "fields"
for validation_failed. The unversioned routes keep {"detail": ...}
(test_error_contract.py).
"""

from datetime import date

import pytest
from fastapi.testclient import TestClient

import app as app_module
import config
import services.meals
import routes.users
from database import SessionLocal
from models import Meal, User
from services.nutrition_ai import (
    EstimatorFailed,
    EstimatorNotConfigured,
    EstimatorTimeout,
)

JPEG_BYTES = b"\xff\xd8\xff\xe0jpeg-bytes"

PROFILE_INPUT = {
    "age": 30,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 70,
    "activity_level": "moderately_active",
    "goal": "maintain",
}


def assert_error(response, status, code):
    assert response.status_code == status
    assert response.headers["content-type"] == "application/json"
    body = response.json()
    assert set(body) == {"error"}
    error = body["error"]
    expected_keys = {"code", "message", "fields"} if code == "validation_failed" else {"code", "message"}
    assert set(error) == expected_keys
    assert error["code"] == code
    assert isinstance(error["message"], str) and error["message"].strip()
    return error


def assert_validation(response, *fields):
    error = assert_error(response, 422, "validation_failed")
    assert error["fields"]
    for item in error["fields"]:
        assert set(item) == {"field", "message"}
        assert isinstance(item["field"], str)
        assert isinstance(item["message"], str) and item["message"]
    assert {item["field"] for item in error["fields"]} >= set(fields)
    return error


def estimate(client, data=None, files=None, headers=None):
    return client.post("/v1/meals/estimate", data=data, files=files, headers=headers)


@pytest.mark.parametrize(
    "files, status, code",
    [
        ({"image": ("meal.gif", b"GIF89a", "image/gif")}, 400, "unsupported_image_type"),
        ({"image": ("meal.jpg", b"", "image/jpeg")}, 400, "empty_image"),
        ({"image": ("meal.jpg", b"not an image", "image/jpeg")}, 400, "invalid_image"),
    ],
)
def test_bad_images(client, files, status, code):
    assert_error(estimate(client, {"message": "lunch"}, files), status, code)
    assert client.get("/meals/today").json() == []


def test_image_too_large(client, monkeypatch):
    monkeypatch.setattr(config, "MAX_IMAGE_BYTES", 8)

    response = estimate(
        client,
        {"message": "lunch"},
        {"image": ("meal.jpg", b"\xff\xd8\xff" + b"\x00" * 6, "image/jpeg")},
    )

    assert_error(response, 413, "image_too_large")


@pytest.mark.parametrize(
    "method, path, kwargs",
    [
        ("POST", "/v1/meals/estimate", {"data": {"message": "lunch"}}),
        ("POST", "/v1/users/onboarding", {"json": PROFILE_INPUT}),
    ],
)
def test_invalid_timezone(client, method, path, kwargs):
    response = client.request(method, path, headers={"X-Timezone": "Not/AZone"}, **kwargs)

    assert_error(response, 400, "invalid_timezone")


@pytest.mark.parametrize(
    "error, status, code",
    [
        (EstimatorFailed("secret provider text"), 502, "estimation_failed"),
        (EstimatorNotConfigured("secret provider text"), 503, "estimation_unavailable"),
        (EstimatorTimeout("secret provider text"), 504, "estimation_timeout"),
        (RuntimeError("secret provider text"), 500, "internal_error"),
    ],
)
def test_estimate_failures(client, monkeypatch, error, status, code):
    def failing_estimate(**kwargs):
        raise error

    monkeypatch.setattr(services.meals, "estimate_nutrition", failing_estimate)

    response = estimate(client, {"message": "lunch"})

    assert_error(response, status, code)
    assert "secret" not in response.text


def test_missing_meal(client):
    assert_error(client.delete("/v1/meals/999"), 404, "meal_not_found")


def test_another_users_meal_is_not_found_and_kept(client):
    client.get("/v1/users/profile")  # creates user 1
    with SessionLocal() as db:
        db.add(User(id=2))
        db.flush()
        meal = Meal(
            user_id=2, meal_name="Theirs", calories=1, protein_g=0,
            carbohydrates_g=0, fat_g=0, confidence=1, calorie_low=1,
            calorie_high=1, local_date=date.today(),
        )
        db.add(meal)
        db.commit()
        meal_id = meal.id

    assert_error(client.delete(f"/v1/meals/{meal_id}"), 404, "meal_not_found")
    with SessionLocal() as db:
        assert db.get(Meal, meal_id) is not None


def test_unknown_v1_path(client):
    assert_error(client.get("/v1/nope"), 404, "not_found")


def test_wrong_method(client):
    response = client.put("/v1/meals/1")

    assert_error(response, 405, "method_not_allowed")
    assert "DELETE" in response.headers["allow"]


def test_invalid_onboarding_body(client):
    assert_validation(
        client.post("/v1/users/onboarding", json={**PROFILE_INPUT, "age": 5}),
        "body.age",
    )


def test_malformed_json(client):
    response = client.post(
        "/v1/users/onboarding",
        content=b"not json",
        headers={"Content-Type": "application/json"},
    )

    assert_validation(response)


def test_validation_errors_never_echo_the_input(client):
    response = client.post(
        "/v1/users/onboarding",
        json={**PROFILE_INPUT, "sex": "SECRET-VALUE"},
    )

    assert_validation(response, "body.sex")
    assert "SECRET-VALUE" not in response.text


def test_non_integer_meal_id(client):
    assert_validation(client.delete("/v1/meals/abc"), "path.meal_id")


@pytest.mark.parametrize(
    "data",
    [{}, {"message": ""}, {"message": "   "}],
)
def test_estimate_needs_text_or_a_photo(client, data, fake_estimator):
    assert_validation(estimate(client, data), "body.message")
    assert fake_estimator == []


def test_unexpected_error_outside_the_estimate_is_a_json_envelope(monkeypatch):
    def broken(*args, **kwargs):
        raise RuntimeError("secret database text")

    monkeypatch.setattr(routes.users, "get_user_profile", broken)

    with TestClient(app_module.app, raise_server_exceptions=False) as client:
        response = client.get("/v1/users/profile")

    assert_error(response, 500, "internal_error")
    assert "secret" not in response.text


def test_unversioned_routes_keep_the_detail_shape(client):
    """The same failure, unversioned: {"detail": ...} with no code."""
    response = client.delete("/meals/999")

    assert response.status_code == 404
    assert response.json() == {"detail": "Meal not found."}
