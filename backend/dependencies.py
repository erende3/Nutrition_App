from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import Depends, Header, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import config as settings
from database import SessionLocal
from models import User


def get_db():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


def get_or_create_default_user(db: Session) -> User:
    user = db.get(User, 1)

    if user is None:
        user = User(id=1)

        db.add(user)

        try:
            db.commit()
        except IntegrityError:
            # A concurrent request created the user first; use theirs.
            db.rollback()

        user = db.get(User, 1)

    return user


def get_current_user(
    db: Session = Depends(get_db),
) -> User:
    """The user every user-scoped route acts for.

    Always the development user for now; authentication replaces this one
    function later.
    """

    return get_or_create_default_user(db)


def get_request_timezone(
    x_timezone: str | None = Header(default=None),
) -> ZoneInfo:
    """The client's timezone: the X-Timezone header (an IANA name such as
    America/New_York), or the server default when the header is absent."""

    name = x_timezone or settings.DEFAULT_TIMEZONE

    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, OSError):
        raise HTTPException(
            status_code=400,
            detail="X-Timezone must be an IANA timezone name, such as America/New_York.",
        )
