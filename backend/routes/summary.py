from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from dependencies import get_db, get_or_create_default_user
from services.summary import get_daily_summary


router = APIRouter(
    prefix="/summary",
    tags=["summary"],
)


@router.get("/daily")
def daily_summary(
    db: Session = Depends(get_db),
) -> dict:
    user = get_or_create_default_user(db)

    return get_daily_summary(
        db,
        user,
        date.today(),
    )
