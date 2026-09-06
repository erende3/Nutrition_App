
import os
from typing import Optional
from datetime import date

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session


from database import SessionLocal
from models import Meal, User
from schemas import NutritionEstimate
from services.nutrition_ai import estimate_nutrition
from dependencies import get_db, get_or_create_default_user
from crud import (
    create_meal,
    delete_meal,
    delete_todays_meals,
    get_todays_meals,
    get_meals_by_date,
)

router = APIRouter(
    prefix="/meals",
    tags=["meals"],
)

@router.get("/today")
def meals_today(
    db: Session = Depends(get_db),
) -> list[dict]:
    user = get_or_create_default_user(db)

    todays_meals = get_todays_meals(
        db=db,
        user=user,
    )

    return [
        {
            "id": meal.id,
            "meal_name": meal.meal_name,
            "calories": meal.calories,
            "protein_g": meal.protein_g,
            "carbohydrates_g": meal.carbohydrates_g,
            "fat_g": meal.fat_g,
            "created_at": meal.created_at.isoformat(),
        }
        for meal in todays_meals
    ]

@router.post("/estimate", response_model=NutritionEstimate)
async def estimate_meal(
    message: str = Form(...),
    image: Optional[UploadFile] = File(default=None),
    db: Session = Depends(get_db),
) -> NutritionEstimate:
    """
    Estimate calories and macros from a meal description and optional image,
    then save the resulting meal to the database.
    """

    if not os.environ.get("OPENAI_API_KEY"):
        raise HTTPException(
            status_code=500,
            detail="The OPENAI_API_KEY environment variable is not set.",
        )

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
        estimate = estimate_nutrition(
            message=message,
            image_bytes=image_bytes,
            image_content_type=image_content_type,
        )

        user = get_or_create_default_user(db)

        create_meal(
            db=db,
            user=user,
            estimate=estimate,
        )

        return estimate

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Nutrition estimation failed: {exc}",
        ) from exc

@router.delete("/today")
def clear_todays_meals(
    db: Session = Depends(get_db),
) -> dict:
    user = get_or_create_default_user(db)

    todays_meals = get_todays_meals(
        db=db,
        user=user,
    )

    deleted_count = delete_todays_meals(
        db=db,
        user=user,
    )

    return {
        "message": "Today's meals cleared.",
        "deleted_meals": deleted_count,
    }
@router.delete("/{meal_id}")
def remove_meal(
    meal_id: int,
    db: Session = Depends(get_db),
) -> dict:
    user = get_or_create_default_user(db)

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

    return {
        "message": "Meal deleted.",
        "meal_id": meal_id,
    }
@router.get("/date/{meal_date}")
def get_meals_for_date(
    meal_date: date,
    db: Session = Depends(get_db),
):
    user = get_or_create_default_user(db)

    return get_meals_by_date(
        db=db,
        user=user,
        target_date=meal_date,
    )