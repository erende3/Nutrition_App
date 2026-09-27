from datetime import date, datetime

from sqlalchemy.orm import Session

from models import DEFAULT_DAILY_CALORIE_GOAL, DailyGoal, Meal, User
from schemas import GoalSource, MealSource, UserOnboardingRequest
from services.nutrition_ai import EstimateResult


def create_meal(
    db: Session,
    user: User,
    result: EstimateResult,
    source: MealSource,
    description: str,
    created_at: datetime,
    local_date: date,
) -> Meal:
    estimate = result.estimate
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
        created_at=created_at,
        local_date=local_date,
        source=source,
        description=description,
        ai_provider=result.provider,
        ai_model=result.model,
        prompt_version=result.prompt_version,
        ai_payload=estimate.model_dump(),
    )

    db.add(meal)
    db.commit()
    db.refresh(meal)

    return meal


def get_meals_by_date(
    db: Session,
    user: User,
    target_date: date,
) -> list[Meal]:
    """The user's meals on one local calendar date, newest first."""

    return (
        db.query(Meal)
        .filter(
            Meal.user_id == user.id,
            Meal.local_date == target_date,
        )
        .order_by(Meal.created_at.desc())
        .all()
    )

def delete_todays_meals(
    db: Session,
    user: User,
    today: date,
) -> int:
    todays_meals = get_meals_by_date(
        db=db,
        user=user,
        target_date=today,
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

def goal_for(
    db: Session,
    user: User,
    day: date,
) -> int:
    """The user's calorie goal on a day: their latest goal effective on or
    before it, else the default."""

    calories = (
        db.query(DailyGoal.calories)
        .filter(
            DailyGoal.user_id == user.id,
            DailyGoal.effective_date <= day,
        )
        .order_by(DailyGoal.effective_date.desc())
        .limit(1)
        .scalar()
    )

    return DEFAULT_DAILY_CALORIE_GOAL if calories is None else calories


def current_goal(
    db: Session,
    user: User,
) -> int:
    """The user's most recent goal, else the default."""

    calories = (
        db.query(DailyGoal.calories)
        .filter(DailyGoal.user_id == user.id)
        .order_by(DailyGoal.effective_date.desc())
        .limit(1)
        .scalar()
    )

    return DEFAULT_DAILY_CALORIE_GOAL if calories is None else calories


def update_user_from_onboarding(
    db: Session,
    user: User,
    data: UserOnboardingRequest,
    daily_calorie_goal: int,
    goal_source: GoalSource,
    effective_date: date,
) -> User:
    """Saves the profile and sets the goal from effective_date on, in one
    commit. A second goal on the same day replaces that day's goal."""

    user.age = data.age
    user.sex = data.sex.value
    user.height_cm = data.height_cm
    user.weight_kg = data.weight_kg
    user.activity_level = data.activity_level.value
    user.goal = data.goal.value

    # ponytail: read-then-write; two onboardings in the same instant for the
    # same day would hit the unique constraint (a 500). Single user today;
    # use INSERT ... ON CONFLICT if concurrent writers appear.
    goal = (
        db.query(DailyGoal)
        .filter(
            DailyGoal.user_id == user.id,
            DailyGoal.effective_date == effective_date,
        )
        .one_or_none()
    )

    if goal is None:
        goal = DailyGoal(user_id=user.id, effective_date=effective_date)
        db.add(goal)

    goal.calories = daily_calorie_goal
    goal.source = goal_source

    db.commit()
    db.refresh(user)

    return user

def get_user_profile(
    db: Session,
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
        "daily_calorie_goal": current_goal(db, user),
        "onboarding_complete": onboarding_complete,
    }