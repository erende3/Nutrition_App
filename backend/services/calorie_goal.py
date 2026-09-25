from models import DEFAULT_DAILY_CALORIE_GOAL
from schemas import ActivityLevel, Goal, Sex


ACTIVITY_FACTORS = {
    ActivityLevel.sedentary: 1.2,
    ActivityLevel.lightly_active: 1.375,
    ActivityLevel.moderately_active: 1.55,
    ActivityLevel.very_active: 1.725,
    ActivityLevel.extremely_active: 1.9,
}


GOAL_ADJUSTMENTS = {
    Goal.lose_weight: -500,
    Goal.maintain: 0,
    Goal.gain_weight: 300,
}


def calculate_bmr(
    sex: Sex,
    age: int,
    weight_kg: float,
    height_cm: float,
) -> float:
    """
    Calculate basal metabolic rate using the
    Mifflin-St Jeor equation.
    """

    base = (
        10 * weight_kg
        + 6.25 * height_cm
        - 5 * age
    )

    if sex == Sex.male:
        return base + 5

    return base - 161


def calculate_daily_calorie_goal(
    sex: Sex,
    age: int,
    weight_kg: float,
    height_cm: float,
    activity_level: ActivityLevel,
    goal: Goal,
) -> dict:
    """
    Calculate BMR, estimated TDEE, and a daily calorie target.

    A target of 0 or below (possible for extreme inputs) is replaced by the
    default goal, and goal_adjusted reports it. Positive targets are kept as
    calculated: there are no nutrition-policy bounds yet.
    """

    bmr = calculate_bmr(
        sex=sex,
        age=age,
        weight_kg=weight_kg,
        height_cm=height_cm,
    )

    activity_factor = ACTIVITY_FACTORS[activity_level]

    tdee = bmr * activity_factor

    calorie_goal = round(
        tdee
        + GOAL_ADJUSTMENTS[goal]
    )

    goal_adjusted = calorie_goal <= 0

    if goal_adjusted:
        calorie_goal = DEFAULT_DAILY_CALORIE_GOAL

    return {
        "bmr": round(bmr),
        "tdee": round(tdee),
        "daily_calorie_goal": calorie_goal,
        "goal_adjusted": goal_adjusted,
    }