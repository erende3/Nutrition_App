"""Never reuse meal ids, and record when a meal was last edited.

Without AUTOINCREMENT, SQLite gives a new meal max(id) + 1, so deleting the
newest meal frees its id for the next one; a client still holding the old id
would then edit or delete the wrong meal. SQLite can't add AUTOINCREMENT in
place, so meals is rebuilt: every row keeps its id and values, and the copy
seeds sqlite_sequence with the highest id. Ids deleted above that before this
migration can't be known and may be used once more.

edited_at (naive UTC, like created_at) is NULL until the meal is edited.

Other databases only get the column: their identity columns never reuse ids.

Revision ID: 0007_meal_identity_and_edits
Revises: 0006_drop_user_goal_column
Create Date: 2026-09-28
"""
import sqlalchemy as sa
from alembic import op

revision = "0007_meal_identity_and_edits"
down_revision = "0006_drop_user_goal_column"
branch_labels = None
depends_on = None


def _recreate() -> str:
    return "always" if op.get_bind().dialect.name == "sqlite" else "auto"


def upgrade() -> None:
    with op.batch_alter_table(
        "meals",
        recreate=_recreate(),
        table_kwargs={"sqlite_autoincrement": True},
    ) as batch_op:
        batch_op.add_column(sa.Column("edited_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table(
        "meals",
        recreate=_recreate(),
        table_kwargs={"sqlite_autoincrement": False},
    ) as batch_op:
        batch_op.drop_column("edited_at")
