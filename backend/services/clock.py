"""The current time, read in one place so tests can freeze it."""

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def local_today(tz: ZoneInfo) -> date:
    """Today's calendar date in the given timezone."""
    return utc_now().astimezone(tz).date()
