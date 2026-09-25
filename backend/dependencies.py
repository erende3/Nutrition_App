from fastapi import Depends
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from database import SessionLocal
from models import DEFAULT_DAILY_CALORIE_GOAL, User


def get_db():
    db = SessionLocal()

    try:
        yield db
    finally:
        db.close()


def get_or_create_default_user(db: Session) -> User:
    user = db.get(User, 1)

    if user is None:
        user = User(
            id=1,
            daily_calorie_goal=DEFAULT_DAILY_CALORIE_GOAL,
        )

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
