from datetime import datetime
from enum import Enum

from pydantic import BaseModel, ConfigDict, Field


class NutritionEstimate(BaseModel):
    """Structured nutrition estimate returned by the AI."""

    meal_name: str = Field(
        description="A short name for the meal."
    )

    calories: int = Field(
        description="Estimated total calories."
    )

    protein_g: float = Field(
        description="Estimated protein in grams."
    )

    carbohydrates_g: float = Field(
        description="Estimated carbohydrates in grams."
    )

    fat_g: float = Field(
        description="Estimated fat in grams."
    )

    confidence: float = Field(
        ge=0,
        le=1,
        description="Confidence in the estimate from 0 to 1.",
    )

    calorie_low: int = Field(
        description="Lower end of the likely calorie range."
    )

    calorie_high: int = Field(
        description="Upper end of the likely calorie range."
    )

    assumptions: list[str] = Field(
        description="Important assumptions about portions and ingredients."
    )

class Sex(str, Enum):
    male = "male"
    female = "female"


class ActivityLevel(str, Enum):
    sedentary = "sedentary"
    lightly_active = "lightly_active"
    moderately_active = "moderately_active"
    very_active = "very_active"
    extremely_active = "extremely_active"

class Goal(str, Enum):
    lose_weight = "lose_weight"
    maintain = "maintain"
    gain_weight = "gain_weight"


class UserOnboardingRequest(BaseModel):
    age: int = Field(ge=13, le=120)

    sex: Sex

    height_cm: float = Field(
        gt=50,
        lt=300,
    )

    weight_kg: float = Field(
        gt=20,
        lt=500,
    )

    activity_level: ActivityLevel

    goal: Goal

class UserOnboardingResponse(BaseModel):
    bmr: int

    tdee: int

    daily_calorie_goal: int

    # True when the calculated goal was not positive and the default was used.
    goal_adjusted: bool

class UserProfileResponse(BaseModel):
    id: int
    age: int | None
    sex: str | None
    height_cm: float | None
    weight_kg: float | None
    activity_level: str | None
    goal: str | None
    daily_calorie_goal: int
    onboarding_complete: bool

class MealResponse(BaseModel):
    """A saved meal, as returned by the meal list endpoints."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    meal_name: str
    calories: int
    protein_g: float
    carbohydrates_g: float
    fat_g: float
    confidence: float
    calorie_low: int
    calorie_high: int
    created_at: datetime


class DailySummaryResponse(BaseModel):
    date: str
    daily_goal: int
    calories_consumed: int
    calories_remaining: int
    percentage: float


class ClearMealsResponse(BaseModel):
    message: str
    deleted_meals: int


class DeleteMealResponse(BaseModel):
    message: str
    meal_id: int


class HomeResponse(BaseModel):
    message: str
    documentation: str
