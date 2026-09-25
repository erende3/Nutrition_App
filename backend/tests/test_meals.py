from datetime import date, datetime, time, timezone
from zoneinfo import ZoneInfo

import pytest

import routes.meals
from database import SessionLocal
from models import Meal


def log_meal(client, message="chicken and rice", files=None):
    return client.post("/meals/estimate", data={"message": message}, files=files)


def test_estimate_returns_estimate_and_passes_text_to_estimator(
    client, fake_estimator, fake_estimate
):
    response = log_meal(client, message="two eggs and toast")

    assert response.status_code == 200
    assert response.json() == fake_estimate.model_dump()
    assert fake_estimator == [
        {"message": "two eggs and toast", "image_bytes": None, "image_content_type": None}
    ]


def test_estimate_passes_image_to_estimator(client, fake_estimator):
    response = log_meal(client, files={"image": ("meal.jpg", b"jpeg-bytes", "image/jpeg")})

    assert response.status_code == 200
    assert fake_estimator[0]["image_bytes"] == b"jpeg-bytes"
    assert fake_estimator[0]["image_content_type"] == "image/jpeg"


def test_estimate_saves_meal_to_todays_list(client):
    log_meal(client)

    meals = client.get("/meals/today").json()

    assert len(meals) == 1
    assert meals[0]["meal_name"] == "Chicken and rice"
    assert meals[0]["calories"] == 650
    assert meals[0]["protein_g"] == 45.0


def test_saved_meal_counts_toward_daily_summary(client):
    log_meal(client)

    summary = client.get("/summary/daily").json()

    assert summary["date"] == date.today().isoformat()
    assert summary["daily_goal"] == 2200
    assert summary["calories_consumed"] == 650
    assert summary["calories_remaining"] == 1550
    assert summary["percentage"] == 29.5


def test_estimate_rejects_unsupported_image_type(client, fake_estimator):
    response = log_meal(client, files={"image": ("meal.gif", b"gif-bytes", "image/gif")})

    assert response.status_code == 400
    assert fake_estimator == []
    assert client.get("/meals/today").json() == []


def test_estimate_rejects_empty_image(client, fake_estimator):
    response = log_meal(client, files={"image": ("meal.jpg", b"", "image/jpeg")})

    assert response.status_code == 400
    assert fake_estimator == []


def test_estimate_without_api_key_returns_500_and_saves_nothing(client, monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY")

    response = log_meal(client)

    assert response.status_code == 500
    assert client.get("/meals/today").json() == []


def test_estimator_failure_returns_500_and_saves_nothing(client, monkeypatch):
    def failing_estimate(**kwargs):
        raise RuntimeError("model unavailable")

    monkeypatch.setattr(routes.meals, "estimate_nutrition", failing_estimate)

    response = log_meal(client)

    assert response.status_code == 500
    assert client.get("/meals/today").json() == []


def test_delete_meal_removes_it_and_updates_summary(client):
    log_meal(client)
    meal_id = client.get("/meals/today").json()[0]["id"]

    response = client.delete(f"/meals/{meal_id}")

    assert response.status_code == 200
    assert client.get("/meals/today").json() == []
    assert client.get("/summary/daily").json()["calories_consumed"] == 0


def test_delete_missing_meal_returns_404(client):
    response = client.delete("/meals/999")

    assert response.status_code == 404


def test_clear_today_deletes_all_of_todays_meals(client):
    log_meal(client)
    log_meal(client)

    response = client.delete("/meals/today")

    assert response.status_code == 200
    assert response.json()["deleted_meals"] == 2
    assert client.get("/meals/today").json() == []


def test_meals_for_date_returns_meals_logged_that_day(client):
    log_meal(client)

    meals = client.get(f"/meals/date/{date.today().isoformat()}").json()

    assert [meal["meal_name"] for meal in meals] == ["Chicken and rice"]


@pytest.mark.xfail(
    strict=True,
    reason="Known bug (Phase 1): created_at is UTC but 'today' is the server's local date",
)
def test_late_evening_meal_counts_toward_that_local_day(client, server_timezone):
    server_timezone("America/New_York")
    today = date.today()
    # 23:30 in New York is 03:30 UTC the next day. Store the meal exactly
    # as the current code would if it were logged at that moment.
    eaten_at = datetime.combine(today, time(23, 30), tzinfo=ZoneInfo("America/New_York"))
    client.get("/users/profile")  # creates user 1
    with SessionLocal() as db:
        db.add(
            Meal(
                user_id=1,
                meal_name="Late snack",
                calories=300,
                protein_g=10,
                carbohydrates_g=30,
                fat_g=12,
                confidence=0.7,
                calorie_low=250,
                calorie_high=350,
                created_at=eaten_at.astimezone(timezone.utc).replace(tzinfo=None),
            )
        )
        db.commit()

    summary = client.get("/summary/daily").json()

    assert summary["calories_consumed"] == 300
