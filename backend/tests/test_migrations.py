"""Alembic migrations: parity with the models, the pre-Alembic upgrade path,
all-or-nothing revisions, and the `python app.py` migrate-before-serve path.

Every test uses its own temporary SQLite file, never the app's database.
"""

import shutil
from functools import partial
from pathlib import Path

import pytest
import uvicorn
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect, text

import app as app_module
import db_migrations
from database import Base

BACKEND = Path(__file__).resolve().parent.parent
BASELINE = "0001_baseline"

# The schema exactly as the pre-Alembic app created it (Base.metadata.create_all),
# copied from a real development database.
PRE_ALEMBIC_SCHEMA = [
    """CREATE TABLE users (
	id INTEGER NOT NULL,
	age INTEGER,
	sex VARCHAR,
	height_cm FLOAT,
	weight_kg FLOAT,
	activity_level VARCHAR,
	goal VARCHAR,
	daily_calorie_goal INTEGER NOT NULL,
	PRIMARY KEY (id)
)""",
    "CREATE INDEX ix_users_id ON users (id)",
    """CREATE TABLE meals (
	id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,
	meal_name VARCHAR NOT NULL,
	calories INTEGER NOT NULL,
	protein_g FLOAT NOT NULL,
	carbohydrates_g FLOAT NOT NULL,
	fat_g FLOAT NOT NULL,
	confidence FLOAT NOT NULL,
	calorie_low INTEGER NOT NULL,
	calorie_high INTEGER NOT NULL,
	created_at DATETIME NOT NULL,
	PRIMARY KEY (id),
	FOREIGN KEY(user_id) REFERENCES users (id)
)""",
    "CREATE INDEX ix_meals_id ON meals (id)",
    "CREATE INDEX ix_meals_user_id ON meals (user_id)",
]

BROKEN_REVISION = '''
import sqlalchemy as sa
from alembic import op

revision = "9999_broken"
down_revision = {down!r}
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("meals", sa.Column("broken_column", sa.Integer()))
    raise RuntimeError("deliberately broken migration")


def downgrade():
    pass
'''

EXTRA_REVISION = '''
revision = "9998_extra"
down_revision = {down!r}
branch_labels = None
depends_on = None


def upgrade():
    pass


def downgrade():
    pass
'''


@pytest.fixture
def db_url(tmp_path):
    return f"sqlite:///{tmp_path / 'migrations.db'}"


def run_sql(url, statements):
    with create_engine(url).begin() as connection:
        for statement in statements:
            connection.execute(text(statement))


def rows(url, sql):
    with create_engine(url).connect() as connection:
        return connection.execute(text(sql)).all()


def head():
    return ScriptDirectory.from_config(db_migrations.alembic_config()).get_current_head()


def scripts_with(tmp_path, template):
    """A copy of the real migrations plus one extra revision on top of head."""
    location = tmp_path / "scripts"
    shutil.copytree(
        BACKEND / "migrations",
        location,
        ignore=shutil.ignore_patterns("__pycache__"),
    )
    (location / "versions" / "9_extra.py").write_text(template.format(down=head()))
    return location


def create_pre_alembic_database(url):
    run_sql(url, PRE_ALEMBIC_SCHEMA)
    run_sql(
        url,
        [
            "INSERT INTO users (id, age, sex, height_cm, weight_kg, activity_level, "
            "goal, daily_calorie_goal) VALUES "
            "(1, 30, 'male', 175.26, 74.84, 'moderately_active', 'maintain', 2633)",
            "INSERT INTO meals (id, user_id, meal_name, calories, protein_g, "
            "carbohydrates_g, fat_g, confidence, calorie_low, calorie_high, created_at) "
            "VALUES (1, 1, 'Eggs', 400, 20, 35, 20, 0.85, 350, 450, "
            "'2026-09-25 13:47:49.597305')",
        ],
    )


def test_upgrade_from_empty_database_matches_the_models(db_url):
    command.upgrade(db_migrations.alembic_config(db_url), "head")

    with create_engine(db_url).connect() as connection:
        differences = compare_metadata(MigrationContext.configure(connection), Base.metadata)

    assert differences == []
    assert db_migrations.current_revision(db_url) == head()


def test_pre_alembic_database_is_stamped_at_baseline_without_changes(db_url):
    create_pre_alembic_database(db_url)

    command.stamp(db_migrations.alembic_config(db_url), BASELINE)

    assert db_migrations.current_revision(db_url) == BASELINE
    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users") == [(1, 2633)]
    assert rows(db_url, "SELECT id, meal_name, calories FROM meals") == [(1, "Eggs", 400)]


def test_stamped_database_upgrades_to_head_and_keeps_its_rows(db_url):
    create_pre_alembic_database(db_url)
    command.stamp(db_migrations.alembic_config(db_url), BASELINE)

    db_migrations.upgrade_to_head(db_url)

    assert db_migrations.current_revision(db_url) == head()
    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users") == [(1, 2633)]
    assert rows(db_url, "SELECT id, meal_name, calories FROM meals") == [(1, "Eggs", 400)]


def test_upgrade_refuses_existing_tables_without_migration_history(db_url):
    create_pre_alembic_database(db_url)

    with pytest.raises(db_migrations.MigrationError, match="stamp"):
        db_migrations.upgrade_to_head(db_url)

    assert "alembic_version" not in inspect(create_engine(db_url)).get_table_names()
    assert rows(db_url, "SELECT count(*) FROM meals") == [(1,)]


def test_failed_migration_leaves_the_previous_revision_and_no_partial_change(
    db_url, tmp_path
):
    db_migrations.upgrade_to_head(db_url)
    broken = scripts_with(tmp_path, BROKEN_REVISION)

    with pytest.raises(RuntimeError, match="deliberately broken"):
        db_migrations.upgrade_to_head(db_url, script_location=broken)

    assert db_migrations.current_revision(db_url) == head()
    columns = {column["name"] for column in inspect(create_engine(db_url)).get_columns("meals")}
    assert "broken_column" not in columns


def test_revision_check_rejects_a_database_behind_head(db_url, tmp_path):
    db_migrations.upgrade_to_head(db_url)
    newer = scripts_with(tmp_path, EXTRA_REVISION)

    with pytest.raises(db_migrations.MigrationError) as error:
        db_migrations.ensure_at_head(db_url, script_location=newer)

    assert head() in str(error.value)
    assert "9998_extra" in str(error.value)


def test_python_app_does_not_serve_when_migration_fails(db_url, tmp_path, monkeypatch):
    broken = scripts_with(tmp_path, BROKEN_REVISION)
    monkeypatch.setattr(
        db_migrations,
        "upgrade_to_head",
        partial(db_migrations.upgrade_to_head, db_url, script_location=broken),
    )
    served = []
    monkeypatch.setattr(uvicorn, "run", lambda *args, **kwargs: served.append(True))

    with pytest.raises(SystemExit) as exit_info:
        app_module.main()

    assert exit_info.value.code not in (0, None)
    assert served == []


def test_python_app_migrates_before_serving(db_url, monkeypatch):
    monkeypatch.setattr(
        db_migrations,
        "upgrade_to_head",
        partial(db_migrations.upgrade_to_head, db_url),
    )
    revision_when_served = []
    monkeypatch.setattr(
        uvicorn,
        "run",
        lambda *args, **kwargs: revision_when_served.append(
            db_migrations.current_revision(db_url)
        ),
    )

    app_module.main()

    assert revision_when_served == [head()]
