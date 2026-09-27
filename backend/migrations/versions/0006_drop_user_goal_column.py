"""Keep calorie goals only in goal history (daily_goals).

Drops users.daily_calorie_goal and its positive CHECK; daily_goals.calories
has its own. A downgrade restores the column from each user's latest goal
(the default 2200 when there is none). Goal history itself stays until 0005
is downgraded.

Revision ID: 0006_drop_user_goal_column
Revises: 0005_daily_goals
Create Date: 2026-09-26
"""
import sqlalchemy as sa
from alembic import op

revision = "0006_drop_user_goal_column"
down_revision = "0005_daily_goals"
branch_labels = None
depends_on = None

# Frozen here on purpose: a migration must not change if the app's default does.
DEFAULT_DAILY_CALORIE_GOAL = 2200


def upgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.drop_constraint(
            "ck_users_daily_calorie_goal_positive",
            type_="check",
        )
        batch_op.drop_column("daily_calorie_goal")


def downgrade() -> None:
    with op.batch_alter_table("users") as batch_op:
        batch_op.add_column(
            sa.Column("daily_calorie_goal", sa.Integer(), nullable=True)
        )

    op.execute(
        "UPDATE users SET daily_calorie_goal = COALESCE("
        "(SELECT calories FROM daily_goals"
        " WHERE daily_goals.user_id = users.id"
        " ORDER BY effective_date DESC LIMIT 1), "
        f"{DEFAULT_DAILY_CALORIE_GOAL})"
    )

    with op.batch_alter_table("users") as batch_op:
        batch_op.alter_column(
            "daily_calorie_goal",
            existing_type=sa.Integer(),
            nullable=False,
        )
        batch_op.create_check_constraint(
            "ck_users_daily_calorie_goal_positive",
            "daily_calorie_goal > 0",
        )
