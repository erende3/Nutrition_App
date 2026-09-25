from datetime import datetime

from sqlalchemy import Float, ForeignKey, Integer, String, DateTime
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


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

    daily_calorie_goal: Mapped[int] = mapped_column(
        Integer,
        default=2200,
    )

    meals: Mapped[list["Meal"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
    )


class Meal(Base):
    __tablename__ = "meals"

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

    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
    )

    user: Mapped["User"] = relationship(
        back_populates="meals",
    )