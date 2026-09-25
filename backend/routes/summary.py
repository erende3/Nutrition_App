from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from dependencies import get_current_user, get_db, get_request_timezone
from models import User
from schemas import DailySummaryResponse
from services import clock
from services.summary import get_daily_summary


router = APIRouter(
    prefix="/summary",
    tags=["summary"],
)


@router.get("/daily", response_model=DailySummaryResponse)
def daily_summary(
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
    tz: ZoneInfo = Depends(get_request_timezone),
):
    return get_daily_summary(
        db,
        user,
        clock.local_today(tz),
    )
