"""Pin the public API contract: field sets, JSON types, datetime format,
the fields the iOS Swift models decode, and newest-first ordering.

JSON object key order is deliberately not part of the contract.
"""

import re
from datetime import date, datetime, time

from database import SessionLocal
from models import Meal

INT = "int"
NUMBER = "number"
STR = "str"
BOOL = "bool"
LIST_OF_STR = "list[str]"


def nullable(kind):
    return (kind, None)


def matches(value, kind):
    if isinstance(kind, tuple):
        return any(
            value is None if option is None else matches(value, option)
            for option in kind
        )
    if kind == BOOL:
        return isinstance(value, bool)
    if isinstance(value, bool):
        return False
    if kind == INT:
        return isinstance(value, int)
    if kind == NUMBER:
        return isinstance(value, (int, float))
    if kind == STR:
        return isinstance(value, str)
    if kind == LIST_OF_STR:
        return isinstance(value, list) and all(isinstance(item, str) for item in value)
    raise ValueError(kind)


def assert_shape(obj, spec):
    assert set(obj) == set(spec)
    wrong = {key: obj[key] for key, kind in spec.items() if not matches(obj[key], kind)}
    assert wrong == {}


def assert_has_fields(obj, spec):
    """The response carries at least these fields, with these types."""
    assert set(spec) <= set(obj)
    wrong = {key: obj[key] for key, kind in spec.items() if not matches(obj[key], kind)}
    assert wrong == {}


ESTIMATE = {
    "meal_name": STR,
    "calories": INT,
    "protein_g": NUMBER,
    "carbohydrates_g": NUMBER,
    "fat_g": NUMBER,
    "confidence": NUMBER,
    "calorie_low": INT,
    "calorie_high": INT,
    "assumptions": LIST_OF_STR,
}

# Shared by /meals/today and /meals/date/{d} (decision D3; no user_id).
MEAL = {
    "id": INT,
    "meal_name": STR,
    "calories": INT,
    "protein_g": NUMBER,
    "carbohydrates_g": NUMBER,
    "fat_g": NUMBER,
    "confidence": NUMBER,
    "calorie_low": INT,
    "calorie_high": INT,
    "created_at": STR,
}

SUMMARY = {
    "date": STR,
    "daily_goal": INT,
    "calories_consumed": INT,
    "calories_remaining": INT,
    "percentage": NUMBER,
}

PROFILE_BEFORE_ONBOARDING = {
    "id": INT,
    "age": nullable(INT),
    "sex": nullable(STR),
    "height_cm": nullable(NUMBER),
    "weight_kg": nullable(NUMBER),
    "activity_level": nullable(STR),
    "goal": nullable(STR),
    "daily_calorie_goal": INT,
    "onboarding_complete": BOOL,
}

PROFILE_AFTER_ONBOARDING = {
    **PROFILE_BEFORE_ONBOARDING,
    "age": INT,
    "sex": STR,
    "height_cm": NUMBER,
    "weight_kg": NUMBER,
    "activity_level": STR,
    "goal": STR,
}

ONBOARDING = {"bmr": INT, "tdee": INT, "daily_calorie_goal": INT, "goal_adjusted": BOOL}

PROFILE_INPUT = {
    "age": 30,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 70,
    "activity_level": "moderately_active",
    "goal": "maintain",
}

# Field names and types the iOS app decodes (frontend/.../*.swift).
SWIFT_MEAL = {
    "id": INT,
    "meal_name": STR,
    "calories": INT,
    "protein_g": NUMBER,
    "carbohydrates_g": NUMBER,
    "fat_g": NUMBER,
    "created_at": STR,
}
SWIFT_DAILY_SUMMARY = SUMMARY
SWIFT_NUTRITION_ESTIMATE = ESTIMATE
SWIFT_USER_PROFILE = PROFILE_BEFORE_ONBOARDING
SWIFT_ONBOARDING_RESULT = {"bmr": INT, "tdee": INT, "daily_calorie_goal": INT}

NAIVE_ISO_DATETIME = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{6})?$")


def log_meal(client):
    return client.post("/meals/estimate", data={"message": "chicken and rice"})


def insert_meal_today(at, meal_name):
    with SessionLocal() as db:
        db.add(
            Meal(
                user_id=1,
                meal_name=meal_name,
                calories=100,
                protein_g=1,
                carbohydrates_g=1,
                fat_g=1,
                confidence=0.5,
                calorie_low=90,
                calorie_high=110,
                created_at=datetime.combine(date.today(), at),
            )
        )
        db.commit()


def stored_created_at(meal_id):
    with SessionLocal() as db:
        return db.get(Meal, meal_id).created_at


def test_home_shape(client):
    assert_shape(client.get("/").json(), {"message": STR, "documentation": STR})


def test_estimate_shape(client):
    response = log_meal(client)

    assert response.status_code == 200
    assert_shape(response.json(), ESTIMATE)


def test_meals_today_shape(client):
    log_meal(client)

    meals = client.get("/meals/today").json()

    assert len(meals) == 1
    assert_shape(meals[0], MEAL)


def test_meals_by_date_shape(client):
    log_meal(client)

    meals = client.get(f"/meals/date/{date.today().isoformat()}").json()

    assert len(meals) == 1
    assert_shape(meals[0], MEAL)


def test_created_at_is_naive_iso_of_stored_value(client):
    log_meal(client)

    for path in ("/meals/today", f"/meals/date/{date.today().isoformat()}"):
        meal = client.get(path).json()[0]
        assert NAIVE_ISO_DATETIME.match(meal["created_at"])
        assert meal["created_at"] == stored_created_at(meal["id"]).isoformat()


def test_created_at_without_microseconds_has_no_fraction(client):
    client.get("/users/profile")  # creates user 1
    insert_meal_today(time(10, 0), "Whole second")

    for path in ("/meals/today", f"/meals/date/{date.today().isoformat()}"):
        meal = client.get(path).json()[0]
        assert meal["created_at"] == f"{date.today().isoformat()}T10:00:00"


def test_meal_lists_are_newest_first(client):
    client.get("/users/profile")  # creates user 1
    insert_meal_today(time(10, 0), "Breakfast")
    insert_meal_today(time(11, 0), "Brunch")

    for path in ("/meals/today", f"/meals/date/{date.today().isoformat()}"):
        names = [meal["meal_name"] for meal in client.get(path).json()]
        assert names == ["Brunch", "Breakfast"]


def test_delete_meal_shapes(client):
    log_meal(client)
    meal_id = client.get("/meals/today").json()[0]["id"]

    deleted = client.delete(f"/meals/{meal_id}")
    missing = client.delete(f"/meals/{meal_id}")

    assert deleted.status_code == 200
    assert_shape(deleted.json(), {"message": STR, "meal_id": INT})
    assert deleted.json()["meal_id"] == meal_id
    assert missing.status_code == 404
    assert_shape(missing.json(), {"detail": STR})


def test_clear_today_shape(client):
    log_meal(client)

    response = client.delete("/meals/today")

    assert response.status_code == 200
    assert_shape(response.json(), {"message": STR, "deleted_meals": INT})


def test_summary_shape(client):
    log_meal(client)

    summary = client.get("/summary/daily").json()

    assert_shape(summary, SUMMARY)
    assert summary["date"] == date.today().isoformat()


def test_profile_shape_before_and_after_onboarding(client):
    before = client.get("/users/profile").json()
    client.post("/users/onboarding", json=PROFILE_INPUT)
    after = client.get("/users/profile").json()

    assert_shape(before, PROFILE_BEFORE_ONBOARDING)
    assert_shape(after, PROFILE_AFTER_ONBOARDING)


def test_onboarding_shape(client):
    response = client.post("/users/onboarding", json=PROFILE_INPUT)

    assert response.status_code == 200
    assert_shape(response.json(), ONBOARDING)


def test_invalid_date_is_rejected(client):
    assert client.get("/meals/date/not-a-date").status_code == 422


def test_responses_carry_every_field_the_ios_app_decodes(client):
    estimate = log_meal(client).json()
    client.post("/users/onboarding", json=PROFILE_INPUT)

    assert_has_fields(estimate, SWIFT_NUTRITION_ESTIMATE)
    assert_has_fields(client.get("/meals/today").json()[0], SWIFT_MEAL)
    assert_has_fields(client.get("/summary/daily").json(), SWIFT_DAILY_SUMMARY)
    assert_has_fields(client.get("/users/profile").json(), SWIFT_USER_PROFILE)
    assert_has_fields(
        client.post("/users/onboarding", json=PROFILE_INPUT).json(),
        SWIFT_ONBOARDING_RESULT,
    )


# Every operation's 200 response, as a named schema ("list[X]" for arrays).
EXPECTED_RESPONSE_MODELS = {
    ("get", "/"): "HomeResponse",
    ("get", "/meals/today"): "list[MealResponse]",
    ("delete", "/meals/today"): "ClearMealsResponse",
    ("post", "/meals/estimate"): "NutritionEstimate",
    ("delete", "/meals/{meal_id}"): "DeleteMealResponse",
    ("get", "/meals/date/{meal_date}"): "list[MealResponse]",
    ("get", "/summary/daily"): "DailySummaryResponse",
    ("post", "/users/onboarding"): "UserOnboardingResponse",
    ("get", "/users/profile"): "UserProfileResponse",
}


def schema_name(schema):
    if "$ref" in schema:
        return schema["$ref"].rsplit("/", 1)[-1]
    if schema.get("type") == "array" and "$ref" in schema.get("items", {}):
        return f"list[{schema_name(schema['items'])}]"
    return None


def test_every_operation_declares_its_response_model(client):
    paths = client.get("/openapi.json").json()["paths"]

    declared = {
        (method, path): schema_name(
            operation["responses"]["200"]["content"]["application/json"]["schema"]
        )
        for path, operations in paths.items()
        for method, operation in operations.items()
    }

    assert declared == EXPECTED_RESPONSE_MODELS
