"""Record where each meal came from: its input and the AI that estimated it.

All columns are nullable. Existing meals keep NULL, meaning unknown: their
input and the model that estimated them were never recorded.

Revision ID: 0004_meal_provenance
Revises: 0003_meal_local_date
Create Date: 2026-09-26
"""
import sqlalchemy as sa
from alembic import op

revision = "0004_meal_provenance"
down_revision = "0003_meal_local_date"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("meals") as batch_op:
        batch_op.add_column(sa.Column("source", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("description", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("ai_provider", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("ai_model", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("prompt_version", sa.String(), nullable=True))
        batch_op.add_column(sa.Column("ai_payload", sa.JSON(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("meals") as batch_op:
        batch_op.drop_column("ai_payload")
        batch_op.drop_column("prompt_version")
        batch_op.drop_column("ai_model")
        batch_op.drop_column("ai_provider")
        batch_op.drop_column("description")
        batch_op.drop_column("source")
