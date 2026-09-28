"""Pin PATCH /v1/meals/{id}: direct edits of a meal's name, calories and
macros. Only the fields sent change, exactly as sent; everything else about
the meal (its day, time, text, source and the AI's original estimate) stays.
edited_at records the last real change. Also pins the v1 mapping of the old
photo placeholder description to null.
"""

import math
from datetime import date, datetime, timedelta, timezone

import pytest

from database import SessionLocal
from models import Meal, User
from services import clock
from test_contract import assert_shape
from test_v1_contract import MEAL, UTC_SECONDS
from test_v1_days import DAY, add_goal, add_meal, day
from test_v1_errors import assert_error, assert_validation

EDITED_AT = datetime(2026, 9, 28, 14, 5, 7, tzinfo=timezone.utc)

PAYLOAD = {
    "meal_name": "Banana",
    "calories": 105,
    "protein_g": 1.3,
    "carbohydrates_g": 27.0,
    "fat_g": 0.3,
    "confidence": 0.9,
    "calorie_low": 90,
    "calorie_high": 120,
    "assumptions": ["one medium banana"],
}

EDITABLE = ["meal_name", "calories", "protein_g", "carbohydrates_g", "fat_g"]
NOT_EDITABLE = [
    "id", "user_id", "description", "local_date", "created_at", "edited_at",
    "source", "confidence", "calorie_low", "calorie_high", "assumptions",
    "ai_provider", "ai_model", "prompt_version", "ai_payload", "mystery",
]


@pytest.fixture(autouse=True)
def frozen_clock(monkeypatch):
    monkeypatch.setattr(clock, "utc_now", lambda: EDITED_AT)


def add_banana(local_date=DAY, user_id=1, **fields):
    defaults = dict(
        name="Banana", calories=105, macros=(1.3, 27.0, 0.3),
        source="text", description="a banana", ai_provider="openai",
        ai_model="gpt-4.1-mini", prompt_version="v1", ai_payload=PAYLOAD,
    )
    add_meal(local_date, user_id=user_id, **{**defaults, **fields})
    with SessionLocal() as db:
        return db.query(Meal).order_by(Meal.id.desc()).first().id


def stored(meal_id):
    with SessionLocal() as db:
        return db.get(Meal, meal_id)


def snapshot(meal_id):
    meal = stored(meal_id)
    return {column: getattr(meal, column) for column in Meal.__table__.columns.keys()}


def patch(client, meal_id, body):
    return client.patch(f"/v1/meals/{meal_id}", json=body)


@pytest.mark.parametrize(
    "field, value",
    [("meal_name", "Big banana"), ("calories", 0), ("protein_g", 1.5),
     ("carbohydrates_g", 30), ("fat_g", 0.25)],
)
def test_each_field_can_be_edited_on_its_own(client, field, value):
    meal_id = add_banana()
    before = snapshot(meal_id)

    response = patch(client, meal_id, {field: value})

    assert response.status_code == 200
    meal = response.json()
    assert_shape(meal, MEAL)
    assert meal[field] == value
    after = snapshot(meal_id)
    assert after[field] == value
    assert after["edited_at"] == EDITED_AT.replace(tzinfo=None)
    # Nothing else changed: no rescaling, no recalculation.
    assert {k: v for k, v in after.items() if k not in (field, "edited_at")} == {
        k: v for k, v in before.items() if k not in (field, "edited_at")
    }


def test_several_fields_at_once_are_saved_exactly(client):
    meal_id = add_banana()

    meal = patch(client, meal_id, {
        "meal_name": "  Two bananas  ", "calories": 210,
        "protein_g": 2.6, "carbohydrates_g": 54.05, "fat_g": 0.123456,
    }).json()

    assert (meal["meal_name"], meal["calories"], meal["protein_g"], meal["carbohydrates_g"], meal["fat_g"]) == (
        "Two bananas", 210, 2.6, 54.05, 0.123456,
    )
    assert meal["edited_at"] == "2026-09-28T14:05:07Z"
    assert UTC_SECONDS.match(meal["edited_at"])


def test_immutable_fields_and_the_ai_estimate_are_kept(client):
    meal_id = add_banana(DAY - timedelta(days=3))
    before = snapshot(meal_id)

    meal = patch(client, meal_id, {"calories": 150, "protein_g": 9}).json()

    after = snapshot(meal_id)
    for column in ["id", "user_id", "local_date", "created_at", "source", "description",
                   "confidence", "calorie_low", "calorie_high", "ai_provider",
                   "ai_model", "prompt_version", "ai_payload"]:
        assert after[column] == before[column], column
    assert meal["local_date"] == (DAY - timedelta(days=3)).isoformat()
    assert meal["assumptions"] == ["one medium banana"]
    assert (meal["confidence"], meal["calorie_low"], meal["calorie_high"]) == (0.5, 105, 105)


def test_new_meals_are_not_edited(client):
    meal_id = add_banana()

    assert day(client)["meals"][0]["edited_at"] is None
    assert stored(meal_id).edited_at is None


def test_same_values_leave_edited_at_alone(client, monkeypatch):
    meal_id = add_banana()

    same = patch(client, meal_id, {"meal_name": "Banana", "calories": 105, "protein_g": 1.3,
                                    "carbohydrates_g": 27, "fat_g": 0.3})

    assert same.status_code == 200
    assert same.json()["edited_at"] is None
    assert stored(meal_id).edited_at is None

    patch(client, meal_id, {"calories": 110})
    later = datetime(2026, 9, 29, 9, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(clock, "utc_now", lambda: later)
    assert patch(client, meal_id, {"calories": 110}).json()["edited_at"] == "2026-09-28T14:05:07Z"

    assert patch(client, meal_id, {"calories": 111}).json()["edited_at"] == "2026-09-29T09:00:00Z"


def test_a_name_that_only_differs_by_surrounding_spaces_is_no_change(client):
    meal_id = add_banana()

    assert patch(client, meal_id, {"meal_name": " Banana "}).json()["edited_at"] is None


def test_an_edit_changes_only_that_days_totals(client):
    add_goal(DAY - timedelta(days=10), 2000)
    meal_id = add_banana(DAY, calories=300, macros=(10, 20, 5))
    add_banana(DAY, calories=200, macros=(1, 2, 3))
    add_banana(DAY + timedelta(days=1), calories=400, macros=(4, 4, 4))
    other_day = day(client, DAY + timedelta(days=1))

    patch(client, meal_id, {"calories": 350, "fat_g": 7.5})

    edited = day(client)
    assert edited["totals"] == {"calories": 550, "protein_g": 11.0, "carbohydrates_g": 22.0, "fat_g": 10.5}
    assert edited["calories_remaining"] == 1450
    assert edited["goal"] == {"calories": 2000}
    assert day(client, DAY + timedelta(days=1)) == other_day


def test_an_edit_keeps_the_goal_in_effect_that_day(client):
    add_goal(DAY - timedelta(days=5), 1800)
    add_goal(DAY + timedelta(days=1), 2500)
    meal_id = add_banana(DAY)

    patch(client, meal_id, {"calories": 900})

    assert day(client)["goal"] == {"calories": 1800}
    assert day(client, DAY + timedelta(days=1))["goal"] == {"calories": 2500}


def test_missing_meal_is_not_found(client):
    client.get("/v1/users/profile")

    assert_error(patch(client, 999, {"calories": 1}), 404, "meal_not_found")


def test_another_users_meal_is_not_found_and_unchanged(client):
    client.get("/v1/users/profile")  # creates user 1
    meal_id = add_banana(user_id=2)
    before = snapshot(meal_id)

    assert_error(patch(client, meal_id, {"calories": 1}), 404, "meal_not_found")

    assert snapshot(meal_id) == before


def test_empty_body_is_rejected(client):
    meal_id = add_banana()

    assert_validation(patch(client, meal_id, {}))
    assert_validation(client.patch(f"/v1/meals/{meal_id}"))
    assert stored(meal_id).edited_at is None


@pytest.mark.parametrize("field", EDITABLE)
def test_null_is_rejected(client, field):
    meal_id = add_banana()

    assert_validation(patch(client, meal_id, {field: None}), f"body.{field}")


@pytest.mark.parametrize("field", NOT_EDITABLE)
def test_other_fields_are_rejected_and_nothing_changes(client, field):
    meal_id = add_banana()
    before = snapshot(meal_id)

    assert_validation(patch(client, meal_id, {"calories": 1, field: "2026-01-01"}), f"body.{field}")

    assert snapshot(meal_id) == before


@pytest.mark.parametrize(
    "body, field",
    [
        ({"meal_name": ""}, "meal_name"),
        ({"meal_name": "    "}, "meal_name"),
        ({"meal_name": "x" * 81}, "meal_name"),
        ({"meal_name": 12}, "meal_name"),
        ({"calories": -1}, "calories"),
        ({"calories": 10001}, "calories"),
        ({"calories": 280.5}, "calories"),
        ({"calories": "280"}, "calories"),
        ({"calories": True}, "calories"),
        ({"protein_g": -0.1}, "protein_g"),
        ({"carbohydrates_g": 1000.01}, "carbohydrates_g"),
        ({"fat_g": "12"}, "fat_g"),
        ({"fat_g": False}, "fat_g"),
    ],
)
def test_out_of_range_or_wrong_type_is_rejected(client, body, field):
    meal_id = add_banana()
    before = snapshot(meal_id)

    assert_validation(patch(client, meal_id, body), f"body.{field}")

    assert snapshot(meal_id) == before


def test_limits_themselves_are_accepted(client):
    meal_id = add_banana()

    meal = patch(client, meal_id, {"meal_name": "x" * 80, "calories": 10000,
                                   "protein_g": 1000, "carbohydrates_g": 0, "fat_g": 0}).json()

    assert (meal["meal_name"], meal["calories"], meal["protein_g"]) == ("x" * 80, 10000, 1000)


@pytest.mark.parametrize("literal", [b"NaN", b"Infinity", b"-Infinity", b"1e400"])
def test_non_finite_numbers_are_rejected(client, literal):
    meal_id = add_banana()

    response = client.patch(
        f"/v1/meals/{meal_id}",
        content=b'{"protein_g": ' + literal + b"}",
        headers={"Content-Type": "application/json"},
    )

    assert_validation(response, "body.protein_g")
    assert math.isclose(stored(meal_id).protein_g, 1.3)


def test_rejected_values_are_never_echoed(client):
    meal_id = add_banana()

    response = patch(client, meal_id, {"meal_name": "SECRET-" + "x" * 90, "calories": "SECRET-NUMBER"})

    assert_validation(response, "body.meal_name", "body.calories")
    assert "SECRET" not in response.text


def test_non_integer_meal_id(client):
    assert_validation(patch(client, "abc", {"calories": 1}), "path.meal_id")


def test_unversioned_routes_have_no_patch_and_keep_their_shape(client):
    meal_id = add_banana(date.today())
    legacy_before = client.get("/meals/today").json()[0]

    assert client.patch(f"/meals/{meal_id}", json={"calories": 1}).status_code == 405
    patch(client, meal_id, {"calories": 150})

    legacy_after = client.get("/meals/today").json()[0]
    assert set(legacy_after) == set(legacy_before)
    assert legacy_after == {**legacy_before, "calories": 150}


# The old photo placeholder (0.10 D6).

PLACEHOLDER = "Estimate this meal from the image."


def test_the_old_photo_placeholder_is_served_as_null_and_kept_in_storage(client):
    meal_id = add_banana(source="photo", description=PLACEHOLDER)

    assert day(client)["meals"][0]["description"] is None
    assert patch(client, meal_id, {"calories": 120}).json()["description"] is None
    assert stored(meal_id).description == PLACEHOLDER


@pytest.mark.parametrize(
    "source, description",
    [
        ("text", PLACEHOLDER),
        (None, PLACEHOLDER),
        ("photo", "Estimate this meal from the image"),
        ("photo", " Estimate this meal from the image."),
        ("photo", "estimate this meal from the image."),
        ("photo", PLACEHOLDER + " Two slices."),
    ],
)
def test_only_the_exact_placeholder_on_photo_meals_is_mapped(client, source, description):
    add_banana(source=source, description=description)

    assert day(client)["meals"][0]["description"] == description


def test_the_placeholder_mapping_survives_a_change_to_the_prompt_text(client, monkeypatch):
    import services.meals

    monkeypatch.setattr(services.meals, "PHOTO_ONLY_MESSAGE", "Something new.")
    add_banana(source="photo", description=PLACEHOLDER)

    assert day(client)["meals"][0]["description"] is None


def test_openapi_documents_edited_at_and_the_patch_body(client):
    openapi = client.get("/v1/openapi.json").json()
    schemas = openapi["components"]["schemas"]

    edited_at = schemas["MealResource"]["properties"]["edited_at"]
    assert {"type": "string", "format": "date-time"} in edited_at["anyOf"]
    assert {"type": "null"} in edited_at["anyOf"]
    body = openapi["paths"]["/meals/{meal_id}"]["patch"]["requestBody"]["content"]["application/json"]["schema"]
    update = schemas[body["$ref"].rsplit("/", 1)[-1]]
    assert set(update["properties"]) == set(EDITABLE)
    assert update["additionalProperties"] is False
