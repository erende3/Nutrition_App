"""API v1, mounted at /v1 (app.py).

A separate FastAPI app, so its errors use the v1 envelope
{"error": {"code": ..., "message": ...}} while the unversioned routes keep
{"detail": ...}. Its schema is at /v1/openapi.json.
"""

import re
from datetime import date
from typing import Annotated, Optional
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, File, Form, Path, Request, Response, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BeforeValidator
from sqlalchemy.orm import Session
from starlette.exceptions import HTTPException

from crud import delete_meal, update_meal
from dependencies import get_current_user, get_db, get_request_timezone
from errors import ApiError
from models import Meal, User
from routes import users
from routes.meals import save_estimated_meal
from schemas import DayResponse, ErrorResponse, MealResource, MealSource, MealUpdate
from services import clock
from services.summary import get_day

app = FastAPI(
    title="MyNutritionPal API",
    version="1",
    description="Errors are {\"error\": {\"code\", \"message\"}}, plus "
    "\"fields\" for validation_failed.",
)
# Documents the error envelope on every operation, in place of FastAPI's
# own 422 schema (the unversioned {"detail": [...]}).
ERROR_RESPONSES = {
    status: {"model": ErrorResponse, "description": description}
    for status, description in [
        ("422", "Validation failed (code validation_failed, with fields)"),
        ("4XX", "Client error"),
        ("5XX", "Server or AI provider error"),
    ]
}

# Profile and onboarding are unchanged in v1.
app.include_router(users.router, responses=ERROR_RESPONSES)

# Codes for the errors FastAPI and Starlette raise themselves.
HTTP_ERROR_CODES = {
    400: "bad_request",
    404: "not_found",
    405: "method_not_allowed",
}


def error_response(
    status_code: int,
    code: str,
    message: str,
    fields: list[dict] | None = None,
    headers: dict | None = None,
) -> JSONResponse:
    error = {"code": code, "message": message}
    if fields is not None:
        error["fields"] = fields
    return JSONResponse({"error": error}, status_code=status_code, headers=headers)


@app.exception_handler(HTTPException)
async def http_error(request: Request, exc: HTTPException) -> JSONResponse:
    code = exc.code if isinstance(exc, ApiError) else HTTP_ERROR_CODES.get(exc.status_code, "http_error")
    return error_response(exc.status_code, code, str(exc.detail), headers=exc.headers)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    # Location and message only: the submitted input is never echoed back.
    fields = [
        {"field": ".".join(str(part) for part in error["loc"]), "message": error["msg"]}
        for error in exc.errors()
    ]
    return error_response(422, "validation_failed", "Some of the information sent wasn't valid.", fields)


@app.exception_handler(Exception)
async def unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    # Starlette re-raises the exception after this response is sent, and the
    # server (uvicorn) logs it.
    return error_response(500, "internal_error", "Something went wrong. Please try again.")


def _yyyy_mm_dd(value):
    if not (isinstance(value, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", value)):
        raise ValueError("Use a date in YYYY-MM-DD format.")
    return value


# A meal id SQLite can hold; a larger one is a validation error, not a crash.
MealId = Annotated[int, Path(ge=-(2**63), le=2**63 - 1)]

# A calendar date written exactly YYYY-MM-DD (plain date also takes datetimes).
IsoDate = Annotated[date, BeforeValidator(_yyyy_mm_dd)]


# The text old app builds sent (and stored as the description) for a photo
# with no words. Copied, not imported: it must stay this exact historical
# string even if the estimator's prompt changes (Milestone 0.10, D6).
OLD_PHOTO_PLACEHOLDER = "Estimate this meal from the image."


def public_description(meal: Meal) -> str | None:
    """The user's own text: never the old placeholder. Stored data is never
    rewritten; the unversioned routes don't expose descriptions."""

    if meal.source == MealSource.photo and meal.description == OLD_PHOTO_PLACEHOLDER:
        return None
    return meal.description


def meal_resource(meal: Meal) -> MealResource:
    return MealResource(
        id=meal.id,
        meal_name=meal.meal_name,
        calories=meal.calories,
        protein_g=meal.protein_g,
        carbohydrates_g=meal.carbohydrates_g,
        fat_g=meal.fat_g,
        confidence=meal.confidence,
        calorie_low=meal.calorie_low,
        calorie_high=meal.calorie_high,
        assumptions=(meal.ai_payload or {}).get("assumptions"),
        source=meal.source,
        description=public_description(meal),
        local_date=meal.local_date,
        created_at=meal.created_at,
        edited_at=meal.edited_at,
    )


@app.post("/meals/estimate", status_code=201, tags=["meals"], responses=ERROR_RESPONSES)
async def estimate_meal(
    message: Optional[str] = Form(default=None),
    image: Optional[UploadFile] = File(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    tz: ZoneInfo = Depends(get_request_timezone),
) -> MealResource:
    """Estimate a meal from its description, a photo, or both, and save it.
    Returns the saved meal."""

    if message is not None and not message.strip():
        message = None

    if message is None and image is None:
        raise RequestValidationError([{
            "type": "missing",
            "loc": ("body", "message"),
            "msg": "Describe the meal or add a photo.",
        }])

    meal = await save_estimated_meal(db, user, tz, message, image)

    return meal_resource(meal)


@app.delete("/meals/{meal_id}", status_code=204, tags=["meals"], responses=ERROR_RESPONSES)
def remove_meal(
    meal_id: MealId,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Response:
    if not delete_meal(db=db, user=user, meal_id=meal_id):
        raise ApiError(404, "meal_not_found", "Meal not found.")

    return Response(status_code=204)


@app.patch("/meals/{meal_id}", tags=["meals"], responses=ERROR_RESPONSES)
def edit_meal(
    meal_id: MealId,
    changes: MealUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MealResource:
    """Edit a meal's name, calories or macros. Only the fields sent change,
    exactly as sent; its day, time, text and the AI's original estimate
    stay. Sending the values it already has changes nothing, edited_at
    included. Last write wins."""

    meal = update_meal(
        db=db,
        user=user,
        meal_id=meal_id,
        changes=changes.model_dump(exclude_unset=True),
        now=clock.utc_now(),
    )

    if meal is None:
        raise ApiError(404, "meal_not_found", "Meal not found.")

    return meal_resource(meal)


@app.get("/days/{day}", tags=["days"], responses=ERROR_RESPONSES)
def read_day(
    day: IsoDate,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> DayResponse:
    """The meals logged on one of the user's calendar dates (the date in
    their timezone when each meal was logged), newest first, with their
    totals and the goal in effect that day. The date is never converted:
    X-Timezone plays no part."""

    result = get_day(db, user, day)

    return DayResponse(
        **{**result, "meals": [meal_resource(meal) for meal in result["meals"]]}
    )

