import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

import config
import services.meals
import services.nutrition_ai
from database import SessionLocal
from models import Meal
from services import clock
from services.nutrition_ai import EstimatorFailed, EstimatorNotConfigured, EstimatorTimeout


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


SENTINEL = "internal-detail-sentinel-7f3a"


def logged_exception_mentions(caplog, text):
    return any(
        record.exc_info and text in str(record.exc_info[1])
        for record in caplog.records
    )


@pytest.mark.parametrize(
    "error, status",
    [
        (EstimatorNotConfigured(SENTINEL), 503),
        (EstimatorTimeout(SENTINEL), 504),
        (EstimatorFailed(SENTINEL), 502),
        (RuntimeError(SENTINEL), 500),
    ],
    ids=["not-configured", "timeout", "ai-failure", "unexpected"],
)
def test_estimate_failure_maps_status_hides_details_and_saves_nothing(
    client, monkeypatch, caplog, error, status
):
    def failing_estimate(**kwargs):
        raise error

    monkeypatch.setattr(services.meals, "estimate_nutrition", failing_estimate)

    response = log_meal(client)

    assert response.status_code == status
    assert set(response.json()) == {"detail"}
    assert isinstance(response.json()["detail"], str)
    assert SENTINEL not in response.text
    assert logged_exception_mentions(caplog, SENTINEL)
    assert client.get("/meals/today").json() == []


def test_meal_save_failure_returns_generic_500_and_saves_nothing(
    client, monkeypatch, caplog
):
    def failing_create_meal(**kwargs):
        raise RuntimeError(SENTINEL)

    monkeypatch.setattr(services.meals, "create_meal", failing_create_meal)

    response = log_meal(client)

    assert response.status_code == 500
    assert SENTINEL not in response.text
    assert logged_exception_mentions(caplog, SENTINEL)
    assert client.get("/meals/today").json() == []


def test_estimate_without_api_key_returns_503_and_saves_nothing(client, monkeypatch):
    # Use the real estimator so its own key check runs; it fails before any client.
    monkeypatch.setattr(
        services.meals, "estimate_nutrition", services.nutrition_ai.estimate_nutrition
    )
    monkeypatch.delenv("OPENAI_API_KEY")

    response = log_meal(client)

    assert response.status_code == 503
    assert "OPENAI_API_KEY" not in response.text
    assert client.get("/meals/today").json() == []


def test_slow_estimate_does_not_block_other_requests(client, monkeypatch, fake_estimate):
    estimate_started = threading.Event()
    release_estimate = threading.Event()

    def slow_estimate(message, image_bytes=None, image_content_type=None):
        estimate_started.set()
        release_estimate.wait(timeout=10)
        return fake_estimate

    monkeypatch.setattr(services.meals, "estimate_nutrition", slow_estimate)

    with ThreadPoolExecutor(max_workers=2) as pool:
        estimate = pool.submit(log_meal, client)
        try:
            assert estimate_started.wait(timeout=10)
            summary = pool.submit(client.get, "/summary/daily")
            # Must answer while the estimate is still in progress.
            summary_response = summary.result(timeout=5)
            estimate_finished_first = estimate.done()
        finally:
            release_estimate.set()

        assert summary_response.status_code == 200
        assert estimate_finished_first is False
        assert estimate.result(timeout=10).status_code == 200


def test_slow_meal_save_does_not_block_other_requests(client, monkeypatch):
    save_started = threading.Event()
    release_save = threading.Event()
    real_create_meal = services.meals.create_meal

    def slow_create_meal(**kwargs):
        save_started.set()
        release_save.wait(timeout=10)
        return real_create_meal(**kwargs)

    monkeypatch.setattr(services.meals, "create_meal", slow_create_meal)

    with ThreadPoolExecutor(max_workers=2) as pool:
        estimate = pool.submit(log_meal, client)
        try:
            assert save_started.wait(timeout=10)
            summary = pool.submit(client.get, "/summary/daily")
            # Must answer while the meal save is still in progress.
            summary_response = summary.result(timeout=5)
            estimate_finished_first = estimate.done()
        finally:
            release_save.set()

        assert summary_response.status_code == 200
        assert estimate_finished_first is False
        assert estimate.result(timeout=10).status_code == 200


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


def insert_meal_at(created_at, meal_name="Yesterday's dinner", calories=400):
    with SessionLocal() as db:
        db.add(
            Meal(
                user_id=1,
                meal_name=meal_name,
                calories=calories,
                protein_g=20,
                carbohydrates_g=40,
                fat_g=15,
                confidence=0.7,
                calorie_low=350,
                calorie_high=450,
                created_at=created_at,
                local_date=created_at.date(),
            )
        )
        db.commit()


def yesterday_at_noon():
    return datetime.combine(date.today() - timedelta(days=1), time(12, 0))


def test_todays_meals_exclude_meals_from_other_days(client):
    client.get("/users/profile")  # creates user 1
    insert_meal_at(yesterday_at_noon())
    log_meal(client)

    meals = client.get("/meals/today").json()

    assert [meal["meal_name"] for meal in meals] == ["Chicken and rice"]


def test_summary_excludes_meals_from_other_days(client):
    client.get("/users/profile")  # creates user 1
    insert_meal_at(yesterday_at_noon())
    log_meal(client)

    summary = client.get("/summary/daily").json()

    assert summary["calories_consumed"] == 650


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


def freeze_clock(monkeypatch, utc_moment):
    monkeypatch.setattr(clock, "utc_now", lambda: utc_moment)


def stored_meal_times():
    with SessionLocal() as db:
        return [(meal.created_at, meal.local_date) for meal in db.query(Meal)]


def test_logged_meal_stores_the_local_date_from_the_timezone_header(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 25, 20, 0, tzinfo=timezone.utc))

    client.post(
        "/meals/estimate",
        data={"message": "ramen"},
        headers={"X-Timezone": "Asia/Tokyo"},
    )

    # 20:00 UTC is 05:00 the next morning in Tokyo.
    assert stored_meal_times() == [(datetime(2026, 9, 25, 20, 0), date(2026, 9, 26))]


def test_logged_meal_without_header_uses_the_server_default_zone(client, monkeypatch):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "America/New_York")
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 3, 30, tzinfo=timezone.utc))

    log_meal(client)

    assert stored_meal_times() == [(datetime(2026, 9, 26, 3, 30), date(2026, 9, 25))]
