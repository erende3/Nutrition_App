from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from crud import create_meal
from models import User
from schemas import MealSource, NutritionEstimate
from services import clock
from services.nutrition_ai import estimate_nutrition


def log_meal(
    db: Session,
    user: User,
    message: str,
    tz: ZoneInfo,
    image_bytes: bytes | None = None,
    image_content_type: str | None = None,
) -> NutritionEstimate:
    """Estimate a meal and save it for the user (auto-save), dated in the
    user's timezone.

    Blocking (AI call and database write): call it from a worker thread.
    """

    # Read before the (possibly slow) estimate, so a meal submitted just
    # before midnight stays on the day it was submitted.
    logged_at = clock.utc_now()

    result = estimate_nutrition(
        message=message,
        image_bytes=image_bytes,
        image_content_type=image_content_type,
    )

    create_meal(
        db=db,
        user=user,
        result=result,
        source=MealSource.photo if image_bytes is not None else MealSource.text,
        description=message,
        created_at=logged_at.replace(tzinfo=None),
        local_date=logged_at.astimezone(tz).date(),
    )

    return result.estimate
