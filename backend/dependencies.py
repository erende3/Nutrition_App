from sqlalchemy.orm import Session

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
        user = User(
            id=1,
            daily_calorie_goal=2200,
        )

        db.add(user)
        db.commit()
        db.refresh(user)

    return user