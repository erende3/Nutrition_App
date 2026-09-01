from datetime import date

from sqlalchemy.orm import Session

from models import Meal, User
from schemas import NutritionEstimate


def create_meal(
    db: Session,
    user: User,
    estimate: NutritionEstimate,
) -> Meal:
    meal = Meal(
        user_id=user.id,
        meal_name=estimate.meal_name,
        calories=estimate.calories,
        protein_g=estimate.protein_g,
        carbohydrates_g=estimate.carbohydrates_g,
        fat_g=estimate.fat_g,
        confidence=estimate.confidence,
        calorie_low=estimate.calorie_low,
        calorie_high=estimate.calorie_high,
    )

    db.add(meal)
    db.commit()
    db.refresh(meal)

    return meal


def get_todays_meals(
    db: Session,
    user: User,
) -> list[Meal]:
    today = date.today()

    meals = (
        db.query(Meal)
        .filter(Meal.user_id == user.id)
        .order_by(Meal.created_at.desc())
        .all()
    )

    return [
        meal
        for meal in meals
        if meal.created_at.date() == today
    ]

def delete_todays_meals(
    db: Session,
    user: User,
) -> int:
    todays_meals = get_todays_meals(
        db=db,
        user=user,
    )

    deleted_count = len(todays_meals)

    for meal in todays_meals:
        db.delete(meal)

    db.commit()

    return deleted_count