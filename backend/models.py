from datetime import date, datetime, timezone

from sqlalchemy import CheckConstraint, Date, DateTime, Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base

# Every user's goal before onboarding, and the fallback when the calculated
# goal is not positive. Not a nutrition policy (Milestone 0.4, D4).
DEFAULT_DAILY_CALORIE_GOAL = 2200


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            "daily_calorie_goal > 0",
            name="ck_users_daily_calorie_goal_positive",
        ),
    )

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True,
    )

    age: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
    )

    sex: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    height_cm: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    weight_kg: Mapped[float | None] = mapped_column(
        Float,
        nullable=True,
    )

    activity_level: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    goal: Mapped[str | None] = mapped_column(
        String,
        nullable=True,
    )

    daily_calorie_goal: Mapped[int] = mapped_column(
        Integer,
        default=DEFAULT_DAILY_CALORIE_GOAL,
    )

    meals: Mapped[list["Meal"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )


class Meal(Base):
    __tablename__ = "meals"
    __table_args__ = (
        Index("ix_meals_user_local_date", "user_id", "local_date"),
    )

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        index=True,
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
        index=True,
    )

    meal_name: Mapped[str] = mapped_column(String)

    calories: Mapped[int] = mapped_column(Integer)

    protein_g: Mapped[float] = mapped_column(Float)

    carbohydrates_g: Mapped[float] = mapped_column(Float)

    fat_g: Mapped[float] = mapped_column(Float)

    confidence: Mapped[float] = mapped_column(Float)

    calorie_low: Mapped[int] = mapped_column(Integer)

    calorie_high: Mapped[int] = mapped_column(Integer)

    # When the meal was logged, stored as naive UTC.
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
    )

    # The user's calendar date when the meal was logged; decides which
    # day's totals it counts toward.
    local_date: Mapped[date] = mapped_column(Date)

    user: Mapped["User"] = relationship(
        back_populates="meals",
    )