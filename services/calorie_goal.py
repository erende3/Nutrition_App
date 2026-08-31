# services/calorie_goal.py

def calculate_daily_calorie_goal(
    sex: str,
    age: int,
    weight_kg: float,
    height_cm: float,
    activity_factor: float,
    goal_adjustment: int = 0,
) -> int:

    if sex.lower() == "male":
        bmr = (
            10 * weight_kg
            + 6.25 * height_cm
            - 5 * age
            + 5
        )

    elif sex.lower() == "female":
        bmr = (
            10 * weight_kg
            + 6.25 * height_cm
            - 5 * age
            - 161
        )

    else:
        raise ValueError("sex must be 'male' or 'female'")

    tdee = bmr * activity_factor

    calorie_goal = tdee + goal_adjustment

    return round(calorie_goal)