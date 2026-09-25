from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from dependencies import get_current_user, get_db
from models import User
from schemas import DailySummaryResponse
from services.summary import get_daily_summary


router = APIRouter(
    prefix="/summary",
    tags=["summary"],
)


@router.get("/daily", response_model=DailySummaryResponse)
def daily_summary(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    return get_daily_summary(
        db,
        user,
        date.today(),
    )
