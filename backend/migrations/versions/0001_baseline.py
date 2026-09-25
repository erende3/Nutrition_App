"""Baseline: the schema exactly as the pre-Alembic app created it.

Revision ID: 0001_baseline
Revises:
Create Date: 2026-09-25
"""
import sqlalchemy as sa
from alembic import op

revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("age", sa.Integer(), nullable=True),
        sa.Column("sex", sa.String(), nullable=True),
        sa.Column("height_cm", sa.Float(), nullable=True),
        sa.Column("weight_kg", sa.Float(), nullable=True),
        sa.Column("activity_level", sa.String(), nullable=True),
        sa.Column("goal", sa.String(), nullable=True),
        sa.Column("daily_calorie_goal", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_users_id", "users", ["id"])

    op.create_table(
        "meals",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("meal_name", sa.String(), nullable=False),
        sa.Column("calories", sa.Integer(), nullable=False),
        sa.Column("protein_g", sa.Float(), nullable=False),
        sa.Column("carbohydrates_g", sa.Float(), nullable=False),
        sa.Column("fat_g", sa.Float(), nullable=False),
        sa.Column("confidence", sa.Float(), nullable=False),
        sa.Column("calorie_low", sa.Integer(), nullable=False),
        sa.Column("calorie_high", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_meals_id", "meals", ["id"])
    op.create_index("ix_meals_user_id", "meals", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_meals_user_id", table_name="meals")
    op.drop_index("ix_meals_id", table_name="meals")
    op.drop_table("meals")
    op.drop_index("ix_users_id", table_name="users")
    op.drop_table("users")
