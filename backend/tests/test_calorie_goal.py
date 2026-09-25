from itertools import product

import pytest

from models import DEFAULT_DAILY_CALORIE_GOAL
from schemas import ActivityLevel, Goal, Sex
from services.calorie_goal import calculate_bmr, calculate_daily_calorie_goal


def test_bmr_male_uses_mifflin_st_jeor():
    # 10*70 + 6.25*175 - 5*30 + 5
    assert calculate_bmr(Sex.male, age=30, weight_kg=70, height_cm=175) == 1648.75


def test_bmr_female_uses_mifflin_st_jeor():
    # 10*60 + 6.25*165 - 5*30 - 161
    assert calculate_bmr(Sex.female, age=30, weight_kg=60, height_cm=165) == 1320.25


def test_daily_goal_applies_activity_factor_and_goal_adjustment():
    result = calculate_daily_calorie_goal(
        sex=Sex.male,
        age=30,
        weight_kg=70,
        height_cm=175,
        activity_level=ActivityLevel.moderately_active,
        goal=Goal.lose_weight,
    )

    # BMR 1648.75 * 1.55 = 2555.56 -> 2556; minus 500 for lose_weight -> 2056
    assert result == {
        "bmr": 1649,
        "tdee": 2556,
        "daily_calorie_goal": 2056,
        "goal_adjusted": False,
    }


EXTREME_FEMALE = dict(sex=Sex.female, age=120, activity_level=ActivityLevel.sedentary)


@pytest.mark.parametrize(
    "height_cm, weight_kg, formula_goal",
    [(51, 21, -779), (91.44, 31.75, -346)],
    ids=["backend-limits", "ios-limits"],
)
def test_non_positive_goal_falls_back_to_the_default(height_cm, weight_kg, formula_goal):
    result = calculate_daily_calorie_goal(
        height_cm=height_cm, weight_kg=weight_kg, goal=Goal.lose_weight, **EXTREME_FEMALE
    )

    assert DEFAULT_DAILY_CALORIE_GOAL == 2200
    assert result["daily_calorie_goal"] == DEFAULT_DAILY_CALORIE_GOAL
    assert result["goal_adjusted"] is True
    # bmr and tdee stay as calculated, so the adjustment is visible.
    assert result["tdee"] + (-500) == formula_goal


def test_positive_goals_are_kept_even_when_unrealistic():
    # No nutrition-policy bounds yet (Milestone 0.4, D4): a positive result is
    # stored as calculated. A later policy decision changes this on purpose.
    result = calculate_daily_calorie_goal(
        height_cm=91.44, weight_kg=31.75, goal=Goal.maintain, **EXTREME_FEMALE
    )

    assert result["daily_calorie_goal"] == 154
    assert result["goal_adjusted"] is False


ACCEPTED_INPUT_CORNERS = product(
    [13, 120],  # age
    list(Sex),
    [50.01, 299.99],  # height_cm (exclusive limits 50 and 300)
    [20.01, 499.99],  # weight_kg (exclusive limits 20 and 500)
    list(ActivityLevel),
    list(Goal),
)


@pytest.mark.parametrize(
    "age, sex, height_cm, weight_kg, activity_level, goal", list(ACCEPTED_INPUT_CORNERS)
)
def test_every_accepted_input_yields_a_positive_goal(
    age, sex, height_cm, weight_kg, activity_level, goal
):
    result = calculate_daily_calorie_goal(
        sex=sex,
        age=age,
        weight_kg=weight_kg,
        height_cm=height_cm,
        activity_level=activity_level,
        goal=goal,
    )

    assert result["daily_calorie_goal"] > 0
