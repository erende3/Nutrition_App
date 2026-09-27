"""Pin GET /v1/days/{date}: one user's meals, totals and goal for one stored
local date, with calories_remaining and percentage exactly as the
unversioned /summary/daily computes them.
"""

from datetime import date, datetime, time, timedelta, timezone

import pytest

from database import SessionLocal
from dependencies import get_or_create_default_user
from models import DailyGoal, Meal, User
from schemas import GoalSource
from services import clock
from test_contract import INT, NUMBER, STR, assert_shape
from test_v1_contract import MEAL
from test_v1_errors import assert_validation

DAY = date(2026, 3, 14)

DAY_SCALARS = {"date": STR, "calories_remaining": INT, "percentage": NUMBER}
GOAL = {"calories": INT}
TOTALS = {"calories": INT, "protein_g": NUMBER, "carbohydrates_g": NUMBER, "fat_g": NUMBER}


def add_goal(effective_date, calories):
    with SessionLocal() as db:
        user = get_or_create_default_user(db)
        db.add(DailyGoal(
            user_id=user.id,
            effective_date=effective_date,
            calories=calories,
            source=GoalSource.calculated,
        ))
        db.commit()


def add_meal(local_date, calories=100, hour=12, macros=(1, 1, 1), user_id=1, name="Meal", **fields):
    with SessionLocal() as db:
        if db.get(User, user_id) is None:
            db.add(User(id=user_id))
            db.flush()
        protein, carbs, fat = macros
        db.add(Meal(
            user_id=user_id,
            meal_name=name,
            calories=calories,
            protein_g=protein,
            carbohydrates_g=carbs,
            fat_g=fat,
            confidence=0.5,
            calorie_low=calories,
            calorie_high=calories,
            created_at=datetime.combine(local_date, time(hour)),
            local_date=local_date,
            **fields,
        ))
        db.commit()


def day(client, value=DAY, **kwargs):
    response = client.get(f"/v1/days/{value.isoformat() if isinstance(value, date) else value}", **kwargs)
    assert response.status_code == 200
    return response.json()


def test_day_shape(client):
    add_goal(DAY, 2000)
    add_meal(DAY)

    body = day(client)

    assert set(body) == set(DAY_SCALARS) | {"goal", "totals", "meals"}
    assert_shape({key: body[key] for key in DAY_SCALARS}, DAY_SCALARS)
    assert_shape(body["goal"], GOAL)  # exactly {"calories"}: no goal source
    assert_shape(body["totals"], TOTALS)
    assert_shape(body["meals"][0], MEAL)
    assert body["date"] == DAY.isoformat()


def test_day_totals_sum_that_days_meals_only(client):
    add_meal(DAY, 300, 8, (10.1, 20.2, 5.3))
    add_meal(DAY, 450, 13, (20.2, 30.1, 10.1))
    add_meal(DAY + timedelta(days=1), 999)
    add_meal(DAY, 5000, user_id=2)

    body = day(client)

    assert body["totals"] == {"calories": 750, "protein_g": 30.3, "carbohydrates_g": 50.3, "fat_g": 15.4}
    assert len(body["meals"]) == 2


def test_day_meals_are_newest_first(client):
    add_meal(DAY, hour=8, name="Breakfast")
    add_meal(DAY, hour=19, name="Dinner")
    add_meal(DAY, hour=12, name="Lunch")

    assert [meal["meal_name"] for meal in day(client)["meals"]] == ["Dinner", "Lunch", "Breakfast"]


def test_empty_day(client):
    client.get("/v1/users/profile")  # creates user 1

    body = day(client)

    assert body["meals"] == []
    assert body["totals"] == {"calories": 0, "protein_g": 0, "carbohydrates_g": 0, "fat_g": 0}
    assert body["goal"] == {"calories": 2200}  # no goal history: the default
    assert (body["calories_remaining"], body["percentage"]) == (2200, 0)


def test_each_day_uses_the_goal_effective_on_it(client):
    add_goal(DAY, 2000)
    add_goal(DAY + timedelta(days=10), 2400)

    goals = [
        day(client, DAY + timedelta(days=offset))["goal"]["calories"]
        for offset in (-1, 0, 9, 10, 400)
    ]

    assert goals == [2200, 2000, 2000, 2400, 2400]


def test_changing_the_goal_today_leaves_yesterday_unchanged(client, monkeypatch):
    profile = {"age": 30, "sex": "male", "height_cm": 175, "weight_kg": 70,
               "activity_level": "moderately_active", "goal": "maintain"}
    yesterday, today = date(2026, 9, 25), date(2026, 9, 26)
    add_meal(yesterday, 1278)

    monkeypatch.setattr(clock, "utc_now", lambda: datetime(2026, 9, 25, 12, tzinfo=timezone.utc))
    client.post("/v1/users/onboarding", json=profile, headers={"X-Timezone": "UTC"})
    monkeypatch.setattr(clock, "utc_now", lambda: datetime(2026, 9, 26, 12, tzinfo=timezone.utc))
    client.post("/v1/users/onboarding", json={**profile, "goal": "gain_weight"}, headers={"X-Timezone": "UTC"})

    before = day(client, yesterday)
    assert before["goal"] == {"calories": 2556}
    assert (before["calories_remaining"], before["percentage"]) == (1278, 50.0)
    assert day(client, today)["goal"] == {"calories": 2856}


@pytest.mark.parametrize(
    "goal, meal_calories",
    [
        (2000, []),  # no meals
        (2000, [500, 250]),  # part of the goal
        (2000, [1500, 900]),  # over the goal: 100 cap, remaining 0
        (3000, [1000]),  # 33.333… rounds to 33.3
        (2633, [1]),  # 0.0379… rounds to 0.0
    ],
)
def test_day_matches_the_unversioned_summary(client, monkeypatch, goal, meal_calories):
    add_goal(DAY, goal)
    for calories in meal_calories:
        add_meal(DAY, calories)
    monkeypatch.setattr(clock, "utc_now", lambda: datetime.combine(DAY, time(12), timezone.utc))

    summary = client.get("/summary/daily", headers={"X-Timezone": "UTC"}).json()
    body = day(client)

    assert body["goal"]["calories"] == summary["daily_goal"]
    assert body["totals"]["calories"] == summary["calories_consumed"]
    assert body["calories_remaining"] == summary["calories_remaining"]
    assert body["percentage"] == summary["percentage"]


def test_day_is_the_stored_local_date_whatever_the_viewers_timezone(client):
    add_meal(DAY, hour=23)

    bodies = [
        day(client, headers=headers)
        for headers in ({}, {"X-Timezone": "Asia/Tokyo"}, {"X-Timezone": "America/Los_Angeles"},
                        {"X-Timezone": "Not/AZone"})
    ]

    assert all(body == bodies[0] for body in bodies)
    assert len(bodies[0]["meals"]) == 1


def test_meal_logged_before_provenance_has_nulls(client):
    add_meal(DAY)

    meal = day(client)["meals"][0]

    assert (meal["assumptions"], meal["source"], meal["description"]) == (None, None, None)
    assert meal["local_date"] == DAY.isoformat()


def test_logged_meal_appears_on_its_day_as_returned(client):
    logged = client.post("/v1/meals/estimate", data={"message": "chicken and rice"}).json()

    assert day(client, logged["local_date"])["meals"] == [logged]


@pytest.mark.parametrize(
    "value",
    ["not-a-date", "2026-02-30", "2026-9-7", "20260927", "2026-09-27T00:00:00"],
)
def test_day_must_be_a_real_yyyy_mm_dd_date(client, value):
    assert_validation(client.get(f"/v1/days/{value}"), "path.day")
