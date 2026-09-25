"""Store each meal's local calendar date.

Existing meals are backfilled from created_at (stored as naive UTC)
converted to DEFAULT_TIMEZONE, the zone the server has used for "today".

Revision ID: 0003_meal_local_date
Revises: 0002_goal_positive_check
Create Date: 2026-09-25
"""
from datetime import timezone
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from alembic import op

import config as settings

revision = "0003_meal_local_date"
down_revision = "0002_goal_positive_check"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("meals") as batch_op:
        batch_op.add_column(sa.Column("local_date", sa.Date(), nullable=True))

    zone = ZoneInfo(settings.DEFAULT_TIMEZONE)
    meals = sa.table(
        "meals",
        sa.column("id", sa.Integer),
        sa.column("created_at", sa.DateTime),
        sa.column("local_date", sa.Date),
    )
    connection = op.get_bind()

    for meal_id, created_at in connection.execute(
        sa.select(meals.c.id, meals.c.created_at)
    ).all():
        local_date = created_at.replace(tzinfo=timezone.utc).astimezone(zone).date()
        connection.execute(
            meals.update().where(meals.c.id == meal_id).values(local_date=local_date)
        )

    with op.batch_alter_table("meals") as batch_op:
        batch_op.alter_column("local_date", existing_type=sa.Date(), nullable=False)
        batch_op.create_index("ix_meals_user_local_date", ["user_id", "local_date"])


def downgrade() -> None:
    with op.batch_alter_table("meals") as batch_op:
        batch_op.drop_index("ix_meals_user_local_date")
        batch_op.drop_column("local_date")
