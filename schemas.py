from pydantic import BaseModel, Field


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