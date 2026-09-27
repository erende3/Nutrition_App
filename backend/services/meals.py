from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from crud import create_meal
from models import Meal, User
from schemas import MealSource
from services import clock
from services.nutrition_ai import estimate_nutrition

# What the estimator is asked when a photo meal has no text: the text the app
# sent itself before API v1, so the prompt (and PROMPT_VERSION) is unchanged.
PHOTO_ONLY_MESSAGE = "Estimate this meal from the image."


def log_meal(
    db: Session,
    user: User,
    message: str | None,
    tz: ZoneInfo,
    image_bytes: bytes | None = None,
    image_content_type: str | None = None,
) -> Meal:
    """Estimate a meal and save it for the user (auto-save), dated in the
    user's timezone. Returns the saved meal.

    message is None for a photo meal without text: the estimator gets
    PHOTO_ONLY_MESSAGE, and the meal has no description.

    Blocking (AI call and database write): call it from a worker thread.
    """

    # Read before the (possibly slow) estimate, so a meal submitted just
    # before midnight stays on the day it was submitted.
    logged_at = clock.utc_now()

    result = estimate_nutrition(
        message=PHOTO_ONLY_MESSAGE if message is None else message,
        image_bytes=image_bytes,
        image_content_type=image_content_type,
    )

    return create_meal(
        db=db,
        user=user,
        result=result,
        source=MealSource.photo if image_bytes is not None else MealSource.text,
        description=message,
        created_at=logged_at.replace(tzinfo=None),
        local_date=logged_at.astimezone(tz).date(),
    )
