from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from crud import get_meals_by_date
from dependencies import get_db, get_or_create_default_user
from models import User


router = APIRouter(
    prefix="/summary",
    tags=["summary"],
)

def get_daily_summary_from_db(
    db: Session,
    user: User,
) -> dict:
    today = date.today()

    todays_meals = get_meals_by_date(
        db=db,
        user=user,
        target_date=today,
    )

    calories_consumed = sum(
        meal.calories
        for meal in todays_meals
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
        "date": today.isoformat(),
        "daily_goal": daily_goal,
        "calories_consumed": calories_consumed,
        "calories_remaining": calories_remaining,
        "percentage": round(percentage, 1),
    }


@router.get("/daily")
def daily_summary(
    db: Session = Depends(get_db),
) -> dict:
    user = get_or_create_default_user(db)

    return get_daily_summary_from_db(
        db,
        user,
    )