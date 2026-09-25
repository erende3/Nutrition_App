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
    assert result == {"bmr": 1649, "tdee": 2556, "daily_calorie_goal": 2056}
