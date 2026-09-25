from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from crud import create_meal
from models import User
from schemas import NutritionEstimate
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

    estimate = estimate_nutrition(
        message=message,
        image_bytes=image_bytes,
        image_content_type=image_content_type,
    )

    logged_at = clock.utc_now()

    create_meal(
        db=db,
        user=user,
        estimate=estimate,
        created_at=logged_at.replace(tzinfo=None),
        local_date=logged_at.astimezone(tz).date(),
    )

    return estimate
