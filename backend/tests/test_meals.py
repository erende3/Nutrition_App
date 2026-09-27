import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, time, timedelta, timezone

import pytest
from starlette.datastructures import UploadFile

import config
import services.meals
import services.nutrition_ai
from database import SessionLocal
from models import Meal
from services import clock
from services.nutrition_ai import EstimatorFailed, EstimatorNotConfigured, EstimatorTimeout


# The start of a real file of each accepted type, which the upload check reads.
JPEG_BYTES = b"\xff\xd8\xff\xe0jpeg-bytes"
PNG_BYTES = b"\x89PNG\r\n\x1a\npng-bytes"
WEBP_BYTES = b"RIFF\x10\x00\x00\x00WEBPVP8 webp-bytes"


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
    response = log_meal(client, files={"image": ("meal.jpg", JPEG_BYTES, "image/jpeg")})

    assert response.status_code == 200
    assert fake_estimator[0]["image_bytes"] == JPEG_BYTES
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


def jpeg_of_size(size):
    """Bytes of the given length that start like a JPEG."""
    return b"\xff\xd8\xff" + b"\x00" * (size - 3)


def test_image_at_the_size_limit_is_accepted(client, monkeypatch, fake_estimator):
    monkeypatch.setattr(config, "MAX_IMAGE_BYTES", 64)
    image = jpeg_of_size(64)

    response = log_meal(client, files={"image": ("meal.jpg", image, "image/jpeg")})

    assert response.status_code == 200
    assert fake_estimator[0]["image_bytes"] == image


def test_image_over_the_size_limit_is_rejected_and_nothing_saved(
    client, monkeypatch, fake_estimator
):
    monkeypatch.setattr(config, "MAX_IMAGE_BYTES", 64)

    response = log_meal(
        client, files={"image": ("meal.jpg", jpeg_of_size(65), "image/jpeg")}
    )

    assert response.status_code == 413
    assert response.json() == {
        "detail": "The photo is too large. Please choose a smaller photo."
    }
    assert fake_estimator == []
    assert client.get("/meals/today").json() == []
    assert client.get("/summary/daily").json()["calories_consumed"] == 0


@pytest.mark.parametrize(
    "content_type, image",
    [("image/jpeg", JPEG_BYTES), ("image/png", PNG_BYTES), ("image/webp", WEBP_BYTES)],
)
def test_image_of_the_declared_type_is_accepted(client, fake_estimator, content_type, image):
    response = log_meal(client, files={"image": ("meal", image, content_type)})

    assert response.status_code == 200
    assert fake_estimator[0]["image_bytes"] == image


@pytest.mark.parametrize(
    "content_type, image",
    [
        ("image/jpeg", b"not an image at all"),
        ("image/jpeg", PNG_BYTES),
        ("image/webp", b"RIFF\x10\x00\x00\x00AVI LIST"),
    ],
    ids=["garbage", "png-declared-as-jpeg", "riff-but-not-webp"],
)
def test_image_that_is_not_its_declared_type_is_rejected_and_nothing_saved(
    client, fake_estimator, content_type, image
):
    response = log_meal(client, files={"image": ("meal", image, content_type)})

    assert response.status_code == 400
    assert response.json() == {
        "detail": "The image isn't a valid JPEG, PNG, or WebP file."
    }
    assert fake_estimator == []
    assert client.get("/meals/today").json() == []


def test_oversized_image_is_never_read_whole(client, monkeypatch, fake_estimator):
    monkeypatch.setattr(config, "MAX_IMAGE_BYTES", 64)
    read_sizes = []
    original_read = UploadFile.read

    async def read(self, size=-1):
        read_sizes.append(size)
        return await original_read(self, size)

    monkeypatch.setattr(UploadFile, "read", read)

    response = log_meal(
        client, files={"image": ("meal.jpg", jpeg_of_size(10_000), "image/jpeg")}
    )

    assert response.status_code == 413
    assert read_sizes == [65]


def test_default_size_limit_rejects_an_image_just_over_10_mib(client, fake_estimator):
    response = log_meal(
        client,
        files={"image": ("meal.jpg", jpeg_of_size(10 * 1024 * 1024 + 1), "image/jpeg")},
    )

    assert response.status_code == 413
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


def test_slow_estimate_does_not_block_other_requests(
    client, monkeypatch, fake_estimate, fake_result
):
    estimate_started = threading.Event()
    release_estimate = threading.Event()

    def slow_estimate(message, image_bytes=None, image_content_type=None):
        estimate_started.set()
        release_estimate.wait(timeout=10)
        return fake_result(fake_estimate)

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


def test_late_evening_meal_counts_toward_that_local_day(
    client, monkeypatch, fake_estimate, fake_result
):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "America/New_York")
    # 23:30 in New York is 03:30 UTC the next day.
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 3, 30, tzinfo=timezone.utc))
    late_snack = fake_estimate.model_copy(update={"meal_name": "Late snack", "calories": 300})
    monkeypatch.setattr(
        services.meals, "estimate_nutrition", lambda **kwargs: fake_result(late_snack)
    )

    client.post("/meals/estimate", data={"message": "late snack"})
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


def insert_meal_on(local_date, meal_name, created_at=None):
    with SessionLocal() as db:
        db.add(
            Meal(
                user_id=1,
                meal_name=meal_name,
                calories=400,
                protein_g=20,
                carbohydrates_g=40,
                fat_g=15,
                confidence=0.7,
                calorie_low=350,
                calorie_high=450,
                created_at=created_at or datetime.combine(local_date, time(12, 0)),
                local_date=local_date,
            )
        )
        db.commit()


TOKYO = {"X-Timezone": "Asia/Tokyo"}


def test_today_endpoints_follow_the_timezone_header(client, monkeypatch):
    # 20:00 UTC on Sep 25 is already Sep 26 in Tokyo.
    freeze_clock(monkeypatch, datetime(2026, 9, 25, 20, 0, tzinfo=timezone.utc))
    client.post("/meals/estimate", data={"message": "ramen"}, headers=TOKYO)
    insert_meal_on(date(2026, 9, 25), "UTC-day lunch")

    tokyo_meals = [meal["meal_name"] for meal in client.get("/meals/today", headers=TOKYO).json()]
    utc_meals = [meal["meal_name"] for meal in client.get("/meals/today").json()]
    tokyo_summary = client.get("/summary/daily", headers=TOKYO).json()

    assert tokyo_meals == ["Chicken and rice"]
    assert utc_meals == ["UTC-day lunch"]
    assert tokyo_summary["date"] == "2026-09-26"
    assert tokyo_summary["calories_consumed"] == 650


def test_clear_today_only_clears_the_header_timezones_day(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 25, 20, 0, tzinfo=timezone.utc))
    client.post("/meals/estimate", data={"message": "ramen"}, headers=TOKYO)
    insert_meal_on(date(2026, 9, 25), "UTC-day lunch")

    response = client.delete("/meals/today", headers=TOKYO)

    assert response.json()["deleted_meals"] == 1
    assert [meal["meal_name"] for meal in client.get("/meals/today").json()] == ["UTC-day lunch"]


def test_meals_for_date_use_the_local_date_not_the_utc_date(client):
    client.get("/users/profile")  # creates user 1
    # Logged at 21:30 in New York on Sep 25, which is Sep 26 in UTC.
    insert_meal_on(date(2026, 9, 25), "Evening meal", created_at=datetime(2026, 9, 26, 1, 30))

    on_local_day = client.get("/meals/date/2026-09-25").json()
    on_utc_day = client.get("/meals/date/2026-09-26").json()

    assert [meal["meal_name"] for meal in on_local_day] == ["Evening meal"]
    assert on_utc_day == []


@pytest.mark.parametrize(
    "method, path",
    [("get", "/meals/today"), ("delete", "/meals/today"), ("get", "/summary/daily")],
)
def test_unknown_timezone_header_is_rejected(client, method, path):
    response = client.request(method, path, headers={"X-Timezone": "Mars/Olympus_Mons"})

    assert response.status_code == 400
    assert set(response.json()) == {"detail"}


def test_meal_keeps_the_day_it_was_submitted_when_estimation_crosses_midnight(
    client, monkeypatch, fake_estimate, fake_result
):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "America/New_York")
    # 23:59:30 in New York when the request starts ...
    submitted = datetime(2026, 9, 26, 3, 59, 30, tzinfo=timezone.utc)
    now = [submitted]
    monkeypatch.setattr(clock, "utc_now", lambda: now[0])

    def slow_estimate(**kwargs):
        # ... and 00:00:30 the next day when the AI answers.
        now[0] = datetime(2026, 9, 26, 4, 0, 30, tzinfo=timezone.utc)
        return fake_result(fake_estimate)

    monkeypatch.setattr(services.meals, "estimate_nutrition", slow_estimate)

    log_meal(client)

    assert stored_meal_times() == [(datetime(2026, 9, 26, 3, 59, 30), date(2026, 9, 25))]
