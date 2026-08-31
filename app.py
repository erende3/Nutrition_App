import sys
import os
from typing import Optional
from dotenv import load_dotenv
import os
from datetime import date

load_dotenv()

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field

from sqlalchemy.orm import Session

from database import Base, SessionLocal, engine
from models import User, Meal
from schemas import NutritionEstimate
from services.nutrition_ai import estimate_nutrition

app = FastAPI(
    title="AI Nutrition Estimator",
    description="Estimate meal calories and macronutrients from text and images.",
)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()
def get_or_create_default_user(db: Session) -> User:
    user = db.get(User, 1)

    if user is None:
        user = User(
            id=1,
            daily_calorie_goal=2200,
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    return user

def get_daily_summary_from_db(
    db: Session,
    user: User,
) -> dict:
    today = date.today()

    meals = (
        db.query(Meal)
        .filter(Meal.user_id == user.id)
        .all()
    )

    todays_meals = [
        meal
        for meal in meals
        if meal.created_at.date() == today
    ]

    calories_consumed = sum(
        meal.calories
        for meal in todays_meals
    )

    daily_goal = user.daily_calorie_goal

    calories_remaining = max(
        daily_goal - calories_consumed,
        0,
    )

    percentage = min(
        (calories_consumed / daily_goal) * 100,
        100,
    )

    return {
        "date": today.isoformat(),
        "daily_goal": daily_goal,
        "calories_consumed": calories_consumed,
        "calories_remaining": calories_remaining,
        "percentage": round(percentage, 1),
    }


class CalorieGoal(BaseModel):
    daily_goal: int = Field(gt=0, description="Daily calorie goal")


daily_goal = 2200
calories_consumed = 0
tracking_date = date.today()


def reset_tracker_if_new_day() -> None:
    """Reset the calorie total when a new day begins."""

    global calories_consumed, tracking_date

    if date.today() != tracking_date:
        calories_consumed = 0
        tracking_date = date.today()


def get_daily_summary() -> dict:
    """Return the current daily calorie progress."""

    reset_tracker_if_new_day()

    remaining = max(daily_goal - calories_consumed, 0)
    percentage = min((calories_consumed / daily_goal) * 100, 100)

    return {
        "date": tracking_date.isoformat(),
        "daily_goal": daily_goal,
        "calories_consumed": calories_consumed,
        "calories_remaining": remaining,
        "percentage": round(percentage, 1),
    }


@app.get("/")
def home() -> dict[str, str]:
    return {
        "message": "Nutrition estimator is running.",
        "documentation": "/docs",
    }

@app.post("/estimate", response_model=NutritionEstimate)
async def estimate_meal(
    message: str = Form(...),
    image: Optional[UploadFile] = File(default=None),
    db: Session = Depends(get_db),
) -> NutritionEstimate:
    """
    Estimate calories and macros from a meal description and optional image.

    The estimate is approximate and should not be treated as medical advice.
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

        meal = Meal(
            user_id=user.id,
            meal_name=estimate.meal_name,
            calories=estimate.calories,
            protein_g=estimate.protein_g,
            carbohydrates_g=estimate.carbohydrates_g,
            fat_g=estimate.fat_g,
            confidence=estimate.confidence,
            calorie_low=estimate.calorie_low,
            calorie_high=estimate.calorie_high,
        )

        db.add(meal)
        db.commit()

        return estimate

    except HTTPException:
        raise

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Nutrition estimation failed: {exc}",
        ) from exc
    
@app.get("/daily-summary")
def daily_summary(
    db: Session = Depends(get_db),
) -> dict:
    user = get_or_create_default_user(db)

    return get_daily_summary_from_db(
        db,
        user,
    )

@app.get("/meals/today")
def meals_today(
    db: Session = Depends(get_db),
) -> list[dict]:
    user = get_or_create_default_user(db)
    today = date.today()

    meals = (
        db.query(Meal)
        .filter(Meal.user_id == user.id)
        .order_by(Meal.created_at.desc())
        .all()
    )

    todays_meals = [
        meal
        for meal in meals
        if meal.created_at.date() == today
    ]

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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
    )