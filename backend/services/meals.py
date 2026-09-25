from sqlalchemy.orm import Session

from crud import create_meal
from models import User
from schemas import NutritionEstimate
from services.nutrition_ai import estimate_nutrition


def log_meal(
    db: Session,
    user: User,
    message: str,
    image_bytes: bytes | None = None,
    image_content_type: str | None = None,
) -> NutritionEstimate:
    """Estimate a meal and save it for the user (auto-save).

    Blocking (AI call and database write): call it from a worker thread.
    """

    estimate = estimate_nutrition(
        message=message,
        image_bytes=image_bytes,
        image_content_type=image_content_type,
    )

    create_meal(
        db=db,
        user=user,
        estimate=estimate,
    )

    return estimate
