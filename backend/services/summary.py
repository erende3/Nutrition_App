from datetime import date

from sqlalchemy.orm import Session

from crud import get_meals_by_date, goal_for
from models import Meal, User


def get_daily_summary(
    db: Session,
    user: User,
    day: date,
) -> dict:
    """Calories consumed against the user's goal for one day."""

    meals = get_meals_by_date(
        db=db,
        user=user,
        target_date=day,
    )

    return summarize(meals, goal_for(db, user, day), day)


def summarize(
    meals: list[Meal],
    daily_goal: int,
    day: date,
) -> dict:
    """A day's calories against its goal: the /summary/daily numbers."""

    calories_consumed = sum(
        meal.calories
        for meal in meals
    )

    calories_remaining = max(
        daily_goal - calories_consumed,
        0,
    )

    # The database forbids a goal of 0 or below; guard anyway so a bad
    # stored value cannot break the summary.
    percentage = (
        min((calories_consumed / daily_goal) * 100, 100)
        if daily_goal > 0
        else 0.0
    )

    return {
        "date": day.isoformat(),
        "daily_goal": daily_goal,
        "calories_consumed": calories_consumed,
        "calories_remaining": calories_remaining,
        "percentage": round(percentage, 1),
    }


def get_day(
    db: Session,
    user: User,
    day: date,
) -> dict:
    """The user's meals on one local date, newest first, with their totals
    and the goal in effect that day (GET /v1/days/{date})."""

    meals = get_meals_by_date(
        db=db,
        user=user,
        target_date=day,
    )
    summary = summarize(meals, goal_for(db, user, day), day)

    return {
        "date": day,
        "goal": {"calories": summary["daily_goal"]},
        "totals": {
            "calories": summary["calories_consumed"],
            **{
                field: round(sum(getattr(meal, field) for meal in meals), 1)
                for field in ("protein_g", "carbohydrates_g", "fat_g")
            },
        },
        "calories_remaining": summary["calories_remaining"],
        "percentage": summary["percentage"],
        "meals": meals,
    }

