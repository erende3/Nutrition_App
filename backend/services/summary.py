from datetime import date

from sqlalchemy.orm import Session

from crud import get_meals_by_date
from models import User


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

    calories_consumed = sum(
        meal.calories
        for meal in meals
    )

    daily_goal = user.daily_calorie_goal

    calories_remaining = max(
        daily_goal - calories_consumed,
        0,
    )

    percentage = min(
        (calories_consumed / daily_goal) * 100,
        100,
    )

    return {
        "date": day.isoformat(),
        "daily_goal": daily_goal,
        "calories_consumed": calories_consumed,
        "calories_remaining": calories_remaining,
        "percentage": round(percentage, 1),
    }
