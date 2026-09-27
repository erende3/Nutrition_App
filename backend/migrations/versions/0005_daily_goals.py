"""Keep calorie goals over time, one row per user per effective date.

Each existing user's current goal is copied exactly into one row with
source 'migrated': whether it was calculated or the default was never
recorded. It takes effect on the user's earliest meal date, so every day
with meals keeps the goal it shows today; a user with no meals gets the
migration date in DEFAULT_TIMEZONE.

users.daily_calorie_goal is left in place; revision 0006 removes it.

Revision ID: 0005_daily_goals
Revises: 0004_meal_provenance
Create Date: 2026-09-26
"""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from alembic import op

import config as settings

revision = "0005_daily_goals"
down_revision = "0004_meal_provenance"
branch_labels = None
depends_on = None

# Frozen here on purpose: a migration must not change if the app's values do.
MIGRATED_SOURCE = "migrated"


def upgrade() -> None:
    daily_goals = op.create_table(
        "daily_goals",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("effective_date", sa.Date(), nullable=False),
        sa.Column("calories", sa.Integer(), nullable=False),
        sa.Column("source", sa.String(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.CheckConstraint("calories > 0", name="ck_daily_goals_calories_positive"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "effective_date",
            name="uq_daily_goals_user_effective_date",
        ),
    )

    users = sa.table(
        "users",
        sa.column("id", sa.Integer),
        sa.column("daily_calorie_goal", sa.Integer),
    )
    meals = sa.table(
        "meals",
        sa.column("user_id", sa.Integer),
        sa.column("local_date", sa.Date),
    )
    connection = op.get_bind()
    now = datetime.now(timezone.utc)
    migration_date = now.astimezone(ZoneInfo(settings.DEFAULT_TIMEZONE)).date()

    for user_id, goal in connection.execute(
        sa.select(users.c.id, users.c.daily_calorie_goal).order_by(users.c.id)
    ).all():
        earliest_meal_date = connection.execute(
            sa.select(sa.func.min(meals.c.local_date)).where(meals.c.user_id == user_id)
        ).scalar()
        connection.execute(
            daily_goals.insert().values(
                user_id=user_id,
                effective_date=earliest_meal_date or migration_date,
                calories=goal,
                source=MIGRATED_SOURCE,
                created_at=now.replace(tzinfo=None),
            )
        )


def downgrade() -> None:
    op.drop_table("daily_goals")
