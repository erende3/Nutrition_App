from datetime import date, datetime, time, timedelta

from database import SessionLocal
from dependencies import get_or_create_default_user
from models import Meal, User
from services.summary import get_daily_summary

DAY = date(2026, 3, 14)


def summary_for(goal, meals, day=DAY):
    """meals: (calories, created_at) pairs."""
    with SessionLocal() as db:
        user = get_or_create_default_user(db)
        user.daily_calorie_goal = goal
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


def test_summary_survives_a_non_positive_goal():
    # The database forbids this goal; the summary must not fail if one appears.
    with SessionLocal() as db:
        summary = get_daily_summary(db, User(daily_calorie_goal=0), DAY)

    assert summary["percentage"] == 0.0
    assert summary["calories_remaining"] == 0
