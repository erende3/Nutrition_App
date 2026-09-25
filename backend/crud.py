from datetime import date

from sqlalchemy.orm import Session

from models import Meal, User
from schemas import NutritionEstimate, UserOnboardingRequest


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
    return get_meals_by_date(
        db=db,
        user=user,
        target_date=date.today(),
    )

def get_meals_by_date(
    db: Session,
    user: User,
    target_date: date,
):
    meals = (
        db.query(Meal)
        .filter(Meal.user_id == user.id)
        .order_by(Meal.created_at.desc())
        .all()
    )

    return [
        meal
        for meal in meals
        if meal.created_at.date() == target_date
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

def delete_meal(
    db: Session,
    user: User,
    meal_id: int,
) -> bool:
    meal = (
        db.query(Meal)
        .filter(
            Meal.id == meal_id,
            Meal.user_id == user.id,
        )
        .first()
    )

    if meal is None:
        return False

    db.delete(meal)
    db.commit()

    return True

def update_user_from_onboarding(
    db: Session,
    user: User,
    data: UserOnboardingRequest,
    daily_calorie_goal: int,
) -> User:
    user.age = data.age
    user.sex = data.sex.value
    user.height_cm = data.height_cm
    user.weight_kg = data.weight_kg
    user.activity_level = data.activity_level.value
    user.goal = data.goal.value
    user.daily_calorie_goal = daily_calorie_goal

    db.commit()
    db.refresh(user)

    return user

def get_user_profile(
    user: User,
) -> dict:
    onboarding_complete = all(
        value is not None
        for value in [
            user.age,
            user.sex,
            user.height_cm,
            user.weight_kg,
            user.activity_level,
            user.goal,
        ]
    )

    return {
        "id": user.id,
        "age": user.age,
        "sex": user.sex,
        "height_cm": user.height_cm,
        "weight_kg": user.weight_kg,
        "activity_level": user.activity_level,
        "goal": user.goal,
        "daily_calorie_goal": user.daily_calorie_goal,
        "onboarding_complete": onboarding_complete,
    }