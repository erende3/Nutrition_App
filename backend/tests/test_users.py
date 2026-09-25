import pytest
from sqlalchemy.exc import IntegrityError

from database import SessionLocal
from models import User

TYPICAL_PROFILE = {
    "age": 30,
    "sex": "male",
    "height_cm": 175,
    "weight_kg": 70,
    "activity_level": "moderately_active",
    "goal": "maintain",
}


def test_profile_before_onboarding_is_incomplete_with_default_goal(client):
    response = client.get("/users/profile")

    assert response.status_code == 200
    body = response.json()
    assert body["id"] == 1
    assert body["onboarding_complete"] is False
    assert body["daily_calorie_goal"] == 2200


def test_onboarding_returns_calculated_goal_and_completes_profile(client):
    response = client.post("/users/onboarding", json=TYPICAL_PROFILE)

    assert response.status_code == 200
    assert response.json() == {
        "bmr": 1649,
        "tdee": 2556,
        "daily_calorie_goal": 2556,
        "goal_adjusted": False,
    }

    profile = client.get("/users/profile").json()
    assert profile["onboarding_complete"] is True
    assert profile["daily_calorie_goal"] == 2556
    assert profile["activity_level"] == "moderately_active"


def test_onboarding_rejects_age_below_minimum(client):
    response = client.post("/users/onboarding", json={**TYPICAL_PROFILE, "age": 12})

    assert response.status_code == 422


@pytest.mark.parametrize(
    "profile",
    [
        # Most extreme input the backend accepts today.
        {"age": 120, "sex": "female", "height_cm": 51, "weight_kg": 21,
         "activity_level": "sedentary", "goal": "lose_weight"},
        # Most extreme input the iOS onboarding screens allow (3 ft 0 in, 70 lb).
        {"age": 120, "sex": "female", "height_cm": 91.44, "weight_kg": 31.75,
         "activity_level": "sedentary", "goal": "lose_weight"},
    ],
    ids=["backend-limits", "ios-limits"],
)
def test_accepted_onboarding_input_never_produces_non_positive_goal(client, profile):
    response = client.post("/users/onboarding", json=profile)

    assert response.status_code == 200
    assert response.json()["daily_calorie_goal"] > 0


def test_onboarding_with_non_positive_formula_goal_stores_the_default(client):
    response = client.post(
        "/users/onboarding",
        json={"age": 120, "sex": "female", "height_cm": 91.44, "weight_kg": 31.75,
              "activity_level": "sedentary", "goal": "lose_weight"},
    )

    assert response.json()["daily_calorie_goal"] == 2200
    assert response.json()["goal_adjusted"] is True
    assert client.get("/users/profile").json()["daily_calorie_goal"] == 2200


@pytest.mark.parametrize("goal", [0, -1])
def test_database_rejects_a_non_positive_goal(goal):
    with SessionLocal() as db:
        db.add(User(id=5, daily_calorie_goal=goal))
        with pytest.raises(IntegrityError):
            db.commit()
