import logging
from datetime import date
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from crud import (
    delete_meal,
    delete_todays_meals,
    get_meals_by_date,
)
from dependencies import get_current_user, get_db, get_request_timezone
from models import User
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

# Status and client-facing message per failure. Exception text is logged,
# never returned.
ESTIMATE_ERRORS = {
    EstimatorNotConfigured: (503, "Meal estimation is not available right now."),
    EstimatorTimeout: (504, "Meal estimation timed out. Please try again."),
    EstimatorFailed: (502, "Meal estimation failed. Please try again."),
}
UNEXPECTED_ESTIMATE_ERROR = (500, "Something went wrong while logging the meal.")

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

    image_bytes = None
    image_content_type = None

    if image is not None:
        allowed_types = {
            "image/jpeg",
            "image/png",
            "image/webp",
        }

        if image.content_type not in allowed_types:
            raise HTTPException(
                status_code=400,
                detail="Image must be JPEG, PNG, or WebP.",
            )

        image_bytes = await image.read()

        if not image_bytes:
            raise HTTPException(
                status_code=400,
                detail="The image is empty.",
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
        status_code, detail = ESTIMATE_ERRORS.get(
            type(exc),
            UNEXPECTED_ESTIMATE_ERROR,
        )
        raise HTTPException(
            status_code=status_code,
            detail=detail,
        ) from exc

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
        raise HTTPException(
            status_code=404,
            detail="Meal not found.",
        )

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