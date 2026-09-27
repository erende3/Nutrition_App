from datetime import date, datetime, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from database import SessionLocal
from models import DailyGoal, User
from services import clock

TYPICAL_PROFILE = {
    "age": 30,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 70,
    "activity_level": "moderately_active",
    "goal": "maintain",
}  # goal 2556

GAINING_PROFILE = {**TYPICAL_PROFILE, "goal": "gain_weight"}  # goal 2856

# Inputs the app accepts whose formula goal is 0 or below.
EXTREME_PROFILE = {"age": 120, "sex": "female", "height_cm": 91.44, "weight_kg": 31.75,
                   "activity_level": "sedentary", "goal": "lose_weight"}

UTC = {"X-Timezone": "UTC"}


def freeze_clock(monkeypatch, utc_moment):
    monkeypatch.setattr(clock, "utc_now", lambda: utc_moment)


def stored_goals():
    with SessionLocal() as db:
        return [
            (goal.user_id, goal.effective_date, goal.calories, goal.source)
            for goal in db.query(DailyGoal).order_by(DailyGoal.effective_date)
        ]


def test_profile_before_onboarding_is_incomplete_with_default_goal(client):
    response = client.get("/users/profile")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == 1
    assert body["onboarding_complete"] is False
    assert body["daily_calorie_goal"] == 2200


def test_onboarding_returns_calculated_goal_and_completes_profile(client):
    response = client.post("/users/onboarding", json=TYPICAL_PROFILE)

    assert response.status_code == 200
    assert response.json() == {
        "bmr": 1649,
        "tdee": 2556,
        "daily_calorie_goal": 2556,
        "goal_adjusted": False,
    }

    profile = client.get("/users/profile").json()
    assert profile["onboarding_complete"] is True
    assert profile["daily_calorie_goal"] == 2556
    assert profile["activity_level"] == "moderately_active"


def test_onboarding_rejects_age_below_minimum(client):
    response = client.post("/users/onboarding", json={**TYPICAL_PROFILE, "age": 12})

    assert response.status_code == 422


@pytest.mark.parametrize(
    "profile",
    [
        # Most extreme input the backend accepts today.
        {"age": 120, "sex": "female", "height_cm": 51, "weight_kg": 21,
         "activity_level": "sedentary", "goal": "lose_weight"},
        # Most extreme input the iOS onboarding screens allow (3 ft 0 in, 70 lb).
        {"age": 120, "sex": "female", "height_cm": 91.44, "weight_kg": 31.75,
         "activity_level": "sedentary", "goal": "lose_weight"},
    ],
    ids=["backend-limits", "ios-limits"],
)
def test_accepted_onboarding_input_never_produces_non_positive_goal(client, profile):
    response = client.post("/users/onboarding", json=profile)

    assert response.status_code == 200
    assert response.json()["daily_calorie_goal"] > 0


def test_onboarding_with_non_positive_formula_goal_stores_the_default(client):
    response = client.post("/users/onboarding", json=EXTREME_PROFILE)

    assert response.json()["daily_calorie_goal"] == 2200
    assert response.json()["goal_adjusted"] is True
    assert client.get("/users/profile").json()["daily_calorie_goal"] == 2200


@pytest.mark.parametrize("goal", [0, -1])
def test_database_rejects_a_non_positive_goal(goal):
    with SessionLocal() as db:
        db.add(User(id=5))
        db.flush()
        db.add(DailyGoal(user_id=5, effective_date=date(2026, 9, 26), calories=goal,
                         source="calculated"))
        with pytest.raises(IntegrityError):
            db.commit()


def test_onboarding_records_a_calculated_goal_for_today(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 12, tzinfo=timezone.utc))

    client.post("/users/onboarding", json=TYPICAL_PROFILE, headers=UTC)

    assert stored_goals() == [(1, date(2026, 9, 26), 2556, "calculated")]


def test_onboarding_that_falls_back_to_the_default_records_it(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 12, tzinfo=timezone.utc))

    client.post("/users/onboarding", json=EXTREME_PROFILE, headers=UTC)

    assert stored_goals() == [(1, date(2026, 9, 26), 2200, "default")]


def test_onboarding_again_the_same_day_replaces_that_days_goal(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 12, tzinfo=timezone.utc))

    client.post("/users/onboarding", json=TYPICAL_PROFILE, headers=UTC)
    client.post("/users/onboarding", json=GAINING_PROFILE, headers=UTC)

    assert stored_goals() == [(1, date(2026, 9, 26), 2856, "calculated")]
    assert client.get("/users/profile").json()["daily_calorie_goal"] == 2856


def test_onboarding_on_a_later_day_keeps_the_earlier_goal(client, monkeypatch):
    freeze_clock(monkeypatch, datetime(2026, 9, 25, 12, tzinfo=timezone.utc))
    client.post("/users/onboarding", json=TYPICAL_PROFILE, headers=UTC)

    freeze_clock(monkeypatch, datetime(2026, 9, 26, 12, tzinfo=timezone.utc))
    client.post("/users/onboarding", json=GAINING_PROFILE, headers=UTC)

    assert stored_goals() == [
        (1, date(2026, 9, 25), 2556, "calculated"),
        (1, date(2026, 9, 26), 2856, "calculated"),
    ]
    assert client.get("/users/profile").json()["daily_calorie_goal"] == 2856


def test_late_evening_onboarding_is_dated_in_the_users_timezone(client, monkeypatch):
    # 23:30 in New York is 03:30 UTC the next day.
    freeze_clock(monkeypatch, datetime(2026, 9, 26, 3, 30, tzinfo=timezone.utc))

    client.post(
        "/users/onboarding",
        json=TYPICAL_PROFILE,
        headers={"X-Timezone": "America/New_York"},
    )

    assert stored_goals() == [(1, date(2026, 9, 25), 2556, "calculated")]


def test_a_goal_source_the_app_does_not_define_is_rejected():
    with pytest.raises(ValueError):
        DailyGoal(user_id=1, effective_date=date(2026, 9, 26), calories=2000, source="guessed")
