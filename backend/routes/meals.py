import logging
from datetime import date
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

import config as settings
from crud import (
    delete_meal,
    delete_todays_meals,
    get_meals_by_date,
)
from dependencies import get_current_user, get_db, get_request_timezone
from errors import ApiError
from models import Meal, User
from schemas import (
    ClearMealsResponse,
    DeleteMealResponse,
    MealResponse,
    NutritionEstimate,
)
from services import clock
from services.meals import log_meal
from services.nutrition_ai import (
    EstimatorFailed,
    EstimatorNotConfigured,
    EstimatorTimeout,
)

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/meals",
    tags=["meals"],
)

# Status, code and client-facing message per failure. Exception text is
# logged, never returned.
ESTIMATE_ERRORS = {
    EstimatorNotConfigured: (503, "estimation_unavailable", "Meal estimation is not available right now."),
    EstimatorTimeout: (504, "estimation_timeout", "Meal estimation timed out. Please try again."),
    EstimatorFailed: (502, "estimation_failed", "Meal estimation failed. Please try again."),
}
UNEXPECTED_ESTIMATE_ERROR = (500, "internal_error", "Something went wrong while logging the meal.")

# Accepted image types, each with a check that the bytes really start like
# that kind of file (the declared content type comes from the client).
IMAGE_SIGNATURES = {
    "image/jpeg": lambda data: data.startswith(b"\xff\xd8\xff"),
    "image/png": lambda data: data.startswith(b"\x89PNG\r\n\x1a\n"),
    "image/webp": lambda data: data[:4] == b"RIFF" and data[8:12] == b"WEBP",
}

@router.get("/today", response_model=list[MealResponse])
def meals_today(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    tz: ZoneInfo = Depends(get_request_timezone),
):
    return get_meals_by_date(
        db=db,
        user=user,
        target_date=clock.local_today(tz),
    )

async def save_estimated_meal(
    db: Session,
    user: User,
    tz: ZoneInfo,
    message: str | None,
    image: UploadFile | None,
) -> Meal:
    """Check the upload, estimate the meal and save it (auto-save). Raises
    ApiError for a bad image or a failed estimate. Shared by the unversioned
    and /v1 estimate routes."""

    image_bytes = None
    image_content_type = None

    if image is not None:
        if image.content_type not in IMAGE_SIGNATURES:
            raise ApiError(
                400,
                "unsupported_image_type",
                "Image must be JPEG, PNG, or WebP.",
            )

        # Read at most one byte past the limit, so an oversized upload is
        # never loaded whole. Starlette has already spooled it to disk.
        image_bytes = await image.read(settings.MAX_IMAGE_BYTES + 1)

        if not image_bytes:
            raise ApiError(
                400,
                "empty_image",
                "The image is empty.",
            )

        if len(image_bytes) > settings.MAX_IMAGE_BYTES:
            raise ApiError(
                413,
                "image_too_large",
                "The photo is too large. Please choose a smaller photo.",
            )

        if not IMAGE_SIGNATURES[image.content_type](image_bytes):
            raise ApiError(
                400,
                "invalid_image",
                "The image isn't a valid JPEG, PNG, or WebP file.",
            )

        image_content_type = image.content_type

    try:
        # log_meal blocks (OpenAI call, first-use import, database write);
        # run it off the event loop so other requests keep being served.
        return await run_in_threadpool(
            log_meal,
            db=db,
            user=user,
            message=message,
            tz=tz,
            image_bytes=image_bytes,
            image_content_type=image_content_type,
        )

    except Exception as exc:
        logger.exception("Meal estimate failed")
        raise ApiError(
            *ESTIMATE_ERRORS.get(type(exc), UNEXPECTED_ESTIMATE_ERROR)
        ) from exc

@router.post("/estimate", response_model=NutritionEstimate)
async def estimate_meal(
    message: str = Form(...),
    image: Optional[UploadFile] = File(default=None),
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    tz: ZoneInfo = Depends(get_request_timezone),
) -> NutritionEstimate:
    """
    Estimate calories and macros from a meal description and optional image,
    then save the resulting meal to the database.
    """

    meal = await save_estimated_meal(db, user, tz, message, image)

    # The model's estimate as saved: the response this route has always sent.
    return NutritionEstimate.model_validate(meal.ai_payload)

@router.delete("/today")
def clear_todays_meals(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    tz: ZoneInfo = Depends(get_request_timezone),
) -> ClearMealsResponse:
    deleted_count = delete_todays_meals(
        db=db,
        user=user,
        today=clock.local_today(tz),
    )

    return ClearMealsResponse(
        message="Today's meals cleared.",
        deleted_meals=deleted_count,
    )
@router.delete("/{meal_id}")
def remove_meal(
    meal_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> DeleteMealResponse:
    deleted = delete_meal(
        db=db,
        user=user,
        meal_id=meal_id,
    )

    if not deleted:
        raise ApiError(404, "meal_not_found", "Meal not found.")

    return DeleteMealResponse(
        message="Meal deleted.",
        meal_id=meal_id,
    )
@router.get("/date/{meal_date}", response_model=list[MealResponse])
def get_meals_for_date(
    meal_date: date,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return get_meals_by_date(
        db=db,
        user=user,
        target_date=meal_date,
    )