from datetime import date, datetime, timezone

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship, validates

from database import Base
from schemas import GoalSource, MealSource

# The goal of a user with no goal history (before onboarding), and the
# fallback when the calculated goal is not positive. Not a nutrition policy
# (Milestone 0.4, D4).
DEFAULT_DAILY_CALORIE_GOAL = 2200


class User(Base):
    __tablename__ = "users"

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

    meals: Mapped[list["Meal"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )


class Meal(Base):
    __tablename__ = "meals"
    __table_args__ = (
        Index("ix_meals_user_local_date", "user_id", "local_date"),
        # A deleted meal's id is never given to a new meal (migration 0007).
        {"sqlite_autoincrement": True},
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

    # Where the meal came from. NULL on meals logged before these were
    # recorded (Milestone 0.8): unknown, not guessed.
    source: Mapped[str | None] = mapped_column(String, nullable=True)

    # The text the user submitted, as received.
    description: Mapped[str | None] = mapped_column(String, nullable=True)

    ai_provider: Mapped[str | None] = mapped_column(String, nullable=True)

    ai_model: Mapped[str | None] = mapped_column(String, nullable=True)

    prompt_version: Mapped[str | None] = mapped_column(String, nullable=True)

    # The model's full estimate (including its assumptions), never the image.
    ai_payload: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    # When the meal was last edited, stored as naive UTC; NULL if never.
    edited_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    user: Mapped["User"] = relationship(
        back_populates="meals",
    )

    @validates("source")
    def _validate_source(self, _key, value):
        return None if value is None else MealSource(value).value

class DailyGoal(Base):
    """A user's calorie goal from effective_date until their next goal."""

    __tablename__ = "daily_goals"
    __table_args__ = (
        CheckConstraint(
            "calories > 0",
            name="ck_daily_goals_calories_positive",
        ),
        UniqueConstraint(
            "user_id",
            "effective_date",
            name="uq_daily_goals_user_effective_date",
        ),
    )

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
    )

    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id"),
    )

    effective_date: Mapped[date] = mapped_column(Date)

    calories: Mapped[int] = mapped_column(Integer)

    # A GoalSource value (schemas.py). A plain string, so new sources need
    # no migration.
    source: Mapped[str] = mapped_column(String)

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc).replace(tzinfo=None),
    )

    @validates("source")
    def _validate_source(self, _key, value):
        return GoalSource(value).value
