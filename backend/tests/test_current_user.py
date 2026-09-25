"""Every user-scoped route resolves the user through get_current_user,
so replacing that one dependency (e.g. with real auth) re-scopes the API."""

from datetime import date

import pytest
from fastapi import Depends
from sqlalchemy import func, select

import app as app_module
from database import SessionLocal
from dependencies import get_current_user, get_db, get_or_create_default_user
from models import Meal, User


@pytest.fixture
def as_user_2(client):
    with SessionLocal() as db:
        db.add_all(
            [
                User(id=1, daily_calorie_goal=2200),
                User(id=2, daily_calorie_goal=1800),
            ]
        )
        db.commit()

    def current_user_2(db=Depends(get_db)):
        return db.get(User, 2)

    app_module.app.dependency_overrides[get_current_user] = current_user_2
    yield client
    app_module.app.dependency_overrides.pop(get_current_user, None)


def add_meal(user_id, meal_name, calories=100):
    with SessionLocal() as db:
        meal = Meal(
            user_id=user_id,
            meal_name=meal_name,
            calories=calories,
            protein_g=1,
            carbohydrates_g=1,
            fat_g=1,
            confidence=0.5,
            calorie_low=calories,
            calorie_high=calories,
        )
        db.add(meal)
        db.commit()
        return meal.id


def meal_owners():
    with SessionLocal() as db:
        return sorted(db.scalars(select(Meal.user_id)))


def test_estimate_saves_the_meal_for_the_current_user(as_user_2):
    response = as_user_2.post("/meals/estimate", data={"message": "soup"})

    assert response.status_code == 200
    assert meal_owners() == [2]


@pytest.mark.parametrize(
    "path", ["/meals/today", f"/meals/date/{date.today().isoformat()}"]
)
def test_meal_lists_show_only_the_current_users_meals(as_user_2, path):
    add_meal(1, "User 1 lunch")
    add_meal(2, "User 2 lunch")

    names = [meal["meal_name"] for meal in as_user_2.get(path).json()]

    assert names == ["User 2 lunch"]


def test_summary_uses_the_current_users_meals_and_goal(as_user_2):
    add_meal(1, "User 1 lunch", calories=500)
    add_meal(2, "User 2 lunch", calories=300)

    summary = as_user_2.get("/summary/daily").json()

    assert summary["daily_goal"] == 1800
    assert summary["calories_consumed"] == 300


def test_delete_only_reaches_the_current_users_meals(as_user_2):
    other_users_meal = add_meal(1, "User 1 lunch")
    own_meal = add_meal(2, "User 2 lunch")

    assert as_user_2.delete(f"/meals/{other_users_meal}").status_code == 404
    assert as_user_2.delete(f"/meals/{own_meal}").status_code == 200
    assert meal_owners() == [1]


def test_clear_today_only_clears_the_current_users_meals(as_user_2):
    add_meal(1, "User 1 lunch")
    add_meal(2, "User 2 lunch")

    response = as_user_2.delete("/meals/today")

    assert response.json()["deleted_meals"] == 1
    assert meal_owners() == [1]


def test_profile_is_the_current_users(as_user_2):
    profile = as_user_2.get("/users/profile").json()

    assert profile["id"] == 2
    assert profile["daily_calorie_goal"] == 1800


def test_onboarding_updates_only_the_current_user(as_user_2):
    response = as_user_2.post(
        "/users/onboarding",
        json={
            "age": 30,
            "sex": "male",
            "height_cm": 175,
            "weight_kg": 70,
            "activity_level": "moderately_active",
            "goal": "maintain",
        },
    )

    assert response.status_code == 200
    with SessionLocal() as db:
        assert db.get(User, 2).daily_calorie_goal == 2556
        assert db.get(User, 1).age is None
        assert db.get(User, 1).daily_calorie_goal == 2200


def test_first_user_creation_race_returns_the_existing_user(monkeypatch):
    with SessionLocal() as db:
        real_get = db.get
        missed = []

        def stale_get(*args, **kwargs):
            if not missed:
                missed.append(True)
                # Another request creates user 1 between our read and our insert.
                with SessionLocal() as other:
                    other.add(User(id=1, daily_calorie_goal=2200))
                    other.commit()
                return None
            return real_get(*args, **kwargs)

        monkeypatch.setattr(db, "get", stale_get)

        user = get_or_create_default_user(db)

        assert user.id == 1

    with SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(User)) == 1
