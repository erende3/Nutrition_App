"""Pin the error body shapes the iOS APIClient parses (APIError.swift).

Every error is {"detail": <message>}. The message is a string, except for
FastAPI's request validation errors (422), where it is a list of objects that
each carry "msg". The iOS app shows a string detail to the user as is and
replaces a list detail with its own generic message, so changing either shape
must fail here first.
"""

import pytest

import services.meals
from services.nutrition_ai import (
    EstimatorFailed,
    EstimatorNotConfigured,
    EstimatorTimeout,
)

TYPICAL_PROFILE = {
    "age": 30,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 70,
    "activity_level": "moderately_active",
    "goal": "maintain",
}


def assert_string_detail(response, status):
    assert response.status_code == status
    body = response.json()
    assert set(body) == {"detail"}
    assert isinstance(body["detail"], str)
    assert body["detail"]


def assert_validation_detail(response):
    assert response.status_code == 422
    body = response.json()
    assert set(body) == {"detail"}
    assert isinstance(body["detail"], list)
    assert body["detail"]
    assert all(isinstance(item.get("msg"), str) for item in body["detail"])


def test_unsupported_image_type_is_a_string_detail(client):
    response = client.post(
        "/meals/estimate",
        data={"message": "lunch"},
        files={"image": ("meal.gif", b"GIF89a", "image/gif")},
    )

    assert_string_detail(response, 400)


@pytest.mark.parametrize(
    "method, path",
    [
        ("GET", "/meals/today"),
        ("DELETE", "/meals/today"),
        ("GET", "/summary/daily"),
    ],
)
def test_invalid_timezone_header_is_a_string_detail(client, method, path):
    response = client.request(method, path, headers={"X-Timezone": "Not/AZone"})

    assert_string_detail(response, 400)


def test_invalid_timezone_header_on_estimate_is_a_string_detail(client):
    response = client.post(
        "/meals/estimate",
        data={"message": "lunch"},
        headers={"X-Timezone": "Not/AZone"},
    )

    assert_string_detail(response, 400)


def test_missing_meal_is_a_string_detail(client):
    assert_string_detail(client.delete("/meals/999"), 404)


@pytest.mark.parametrize(
    "error, status",
    [
        (RuntimeError("boom"), 500),
        (EstimatorFailed("boom"), 502),
        (EstimatorNotConfigured("boom"), 503),
        (EstimatorTimeout("boom"), 504),
    ],
)
def test_estimate_failures_are_string_details(client, monkeypatch, error, status):
    def failing_estimate(**kwargs):
        raise error

    monkeypatch.setattr(services.meals, "estimate_nutrition", failing_estimate)

    response = client.post("/meals/estimate", data={"message": "lunch"})

    assert_string_detail(response, status)


def test_invalid_date_is_a_validation_list(client):
    assert_validation_detail(client.get("/meals/date/not-a-date"))


def test_invalid_onboarding_is_a_validation_list(client):
    response = client.post("/users/onboarding", json={**TYPICAL_PROFILE, "age": 5})

    assert_validation_detail(response)
