from datetime import date, datetime, time, timedelta

from datetime import timezone

import services.summary
from database import SessionLocal
from dependencies import get_or_create_default_user
from models import DailyGoal, Meal, User
from schemas import GoalSource
from services import clock
from services.summary import get_daily_summary

DAY = date(2026, 3, 14)


def summary_for(goal, meals, day=DAY):
    """meals: (calories, created_at) pairs. The goal takes effect on day."""
    with SessionLocal() as db:
        user = get_or_create_default_user(db)
        db.add(
            DailyGoal(
                user_id=user.id,
                effective_date=day,
                calories=goal,
                source=GoalSource.calculated,
            )
        )
        for calories, created_at in meals:
            db.add(
                Meal(
                    user_id=user.id,
                    meal_name="Meal",
                    calories=calories,
                    protein_g=1,
                    carbohydrates_g=1,
                    fat_g=1,
                    confidence=0.5,
                    calorie_low=calories,
                    calorie_high=calories,
                    created_at=created_at,
                    local_date=created_at.date(),
                )
            )
        db.commit()
        return get_daily_summary(db, user, day)


def at(day, hour):
    return datetime.combine(day, time(hour))


def test_summary_counts_only_meals_from_the_given_day():
    summary = summary_for(
        2000,
        [
            (500, at(DAY, 8)),
            (300, at(DAY, 19)),
            (900, at(DAY - timedelta(days=1), 12)),
        ],
    )

    assert summary == {
        "date": "2026-03-14",
        "daily_goal": 2000,
        "calories_consumed": 800,
        "calories_remaining": 1200,
        "percentage": 40.0,
    }


def test_summary_over_goal_caps_percentage_and_floors_remaining():
    summary = summary_for(1000, [(1500, at(DAY, 12))])

    assert summary["calories_remaining"] == 0
    assert summary["percentage"] == 100


def test_summary_rounds_percentage_to_one_decimal():
    summary = summary_for(3000, [(1000, at(DAY, 12))])

    assert summary["percentage"] == 33.3


def test_summary_survives_a_non_positive_goal(monkeypatch):
    # The database forbids this goal; the summary must not fail if one appears.
    monkeypatch.setattr(services.summary, "goal_for", lambda db, user, day: 0)
    with SessionLocal() as db:
        summary = get_daily_summary(db, User(id=1), DAY)

    assert summary["percentage"] == 0.0
    assert summary["calories_remaining"] == 0


def summary_goals(days):
    with SessionLocal() as db:
        user = get_or_create_default_user(db)
        return [get_daily_summary(db, user, day)["daily_goal"] for day in days]


def test_changing_the_goal_today_leaves_yesterday_unchanged(client, monkeypatch):
    profile = {"age": 30, "sex": "male", "height_cm": 175, "weight_kg": 70,
               "activity_level": "moderately_active", "goal": "maintain"}
    yesterday, today = date(2026, 9, 25), date(2026, 9, 26)

    monkeypatch.setattr(clock, "utc_now", lambda: datetime(2026, 9, 25, 12, tzinfo=timezone.utc))
    client.post("/users/onboarding", json=profile, headers={"X-Timezone": "UTC"})
    monkeypatch.setattr(clock, "utc_now", lambda: datetime(2026, 9, 26, 12, tzinfo=timezone.utc))
    client.post(
        "/users/onboarding",
        json={**profile, "goal": "gain_weight"},
        headers={"X-Timezone": "UTC"},
    )

    assert summary_goals([yesterday, today]) == [2556, 2856]
    assert client.get("/summary/daily", headers={"X-Timezone": "UTC"}).json()["daily_goal"] == 2856


def test_each_day_uses_the_latest_goal_on_or_before_it():
    with SessionLocal() as db:
        user = get_or_create_default_user(db)
        for effective_date, calories in [(DAY, 2000), (DAY + timedelta(days=10), 2400)]:
            db.add(
                DailyGoal(
                    user_id=user.id,
                    effective_date=effective_date,
                    calories=calories,
                    source=GoalSource.calculated,
                )
            )
        db.commit()

    assert summary_goals(
        [
            DAY - timedelta(days=1),  # before any goal: the default
            DAY,
            DAY + timedelta(days=9),
            DAY + timedelta(days=10),
            DAY + timedelta(days=400),
        ]
    ) == [2200, 2000, 2000, 2400, 2400]
