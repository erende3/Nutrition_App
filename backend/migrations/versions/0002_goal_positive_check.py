"""Forbid non-positive daily calorie goals.

Existing goals of 0 or below are first set to the default goal (2200), the
value the app uses when it cannot calculate one.

Revision ID: 0002_goal_positive_check
Revises: 0001_baseline
Create Date: 2026-09-25
"""
from alembic import op

revision = "0002_goal_positive_check"
down_revision = "0001_baseline"
branch_labels = None
depends_on = None

# Frozen here on purpose: a migration must not change if the app's default does.
DEFAULT_DAILY_CALORIE_GOAL = 2200


def upgrade() -> None:
    op.execute(
        "UPDATE users SET daily_calorie_goal = "
        f"{DEFAULT_DAILY_CALORIE_GOAL} WHERE daily_calorie_goal <= 0"
    )

    with op.batch_alter_table("users") as batch_op:
        batch_op.create_check_constraint(
            "ck_users_daily_calorie_goal_positive",
            "daily_calorie_goal > 0",
        )


def downgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_constraint(
            "ck_users_daily_calorie_goal_positive",
            type_="check",
        )
