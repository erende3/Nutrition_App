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
from sqlalchemy.exc import IntegrityError

import app as app_module
import config
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


def insert_users_with_goals(url, goals):
    run_sql(
        url,
        [
            f"INSERT INTO users (id, daily_calorie_goal) VALUES ({user_id}, {goal})"
            for user_id, goal in enumerate(goals, start=1)
        ],
    )


def test_goal_migration_repairs_non_positive_goals_then_forbids_them(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, BASELINE)
    insert_users_with_goals(db_url, [0, -5, 2633])

    command.upgrade(alembic_cfg, "0002_goal_positive_check")

    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users ORDER BY id") == [
        (1, 2200),
        (2, 2200),
        (3, 2633),
    ]
    with pytest.raises(IntegrityError):
        insert_users_with_goals(db_url, [0, 0, 0, 0])


def test_goal_migration_downgrades_and_upgrades_again(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0002_goal_positive_check")

    command.downgrade(alembic_cfg, BASELINE)
    insert_users_with_goals(db_url, [0])
    run_sql(db_url, ["UPDATE users SET daily_calorie_goal = 1800"])
    command.upgrade(alembic_cfg, "0002_goal_positive_check")

    assert rows(db_url, "SELECT daily_calorie_goal FROM users") == [(1800,)]


def test_local_date_migration_backfills_from_utc_in_the_default_zone(db_url, monkeypatch):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "America/New_York")
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0002_goal_positive_check")
    insert_users_with_goals(db_url, [2633])
    stored_utc = [
        "2026-09-25 12:00:00",  # 08:00 EDT: same day
        "2026-09-26 01:30:00",  # 21:30 EDT the evening before
        "2026-03-08 04:30:00",  # 23:30 EST on Mar 7 (DST starts later that night)
        "2026-11-01 04:30:00",  # 00:30 EDT on Nov 1 (DST ends later that night)
    ]
    run_sql(
        db_url,
        [
            "INSERT INTO meals (user_id, meal_name, calories, protein_g, carbohydrates_g, "
            "fat_g, confidence, calorie_low, calorie_high, created_at) "
            f"VALUES (1, 'Meal', 100, 1, 1, 1, 0.5, 90, 110, '{created_at}')"
            for created_at in stored_utc
        ],
    )

    command.upgrade(alembic_cfg, "0003_meal_local_date")

    assert rows(db_url, "SELECT local_date FROM meals ORDER BY id") == [
        ("2026-09-25",),
        ("2026-09-25",),
        ("2026-03-07",),
        ("2026-11-01",),
    ]
    columns = {column["name"]: column for column in inspect(create_engine(db_url)).get_columns("meals")}
    assert columns["local_date"]["nullable"] is False
    indexes = {index["name"]: index["column_names"] for index in inspect(create_engine(db_url)).get_indexes("meals")}
    assert indexes["ix_meals_user_local_date"] == ["user_id", "local_date"]


def test_local_date_migration_downgrades_and_upgrades_again(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0003_meal_local_date")

    command.downgrade(alembic_cfg, "0002_goal_positive_check")
    columns = {column["name"] for column in inspect(create_engine(db_url)).get_columns("meals")}
    assert "local_date" not in columns

    command.upgrade(alembic_cfg, "0003_meal_local_date")
    assert db_migrations.current_revision(db_url) == "0003_meal_local_date"


PROVENANCE_COLUMNS = [
    "source",
    "description",
    "ai_provider",
    "ai_model",
    "prompt_version",
    "ai_payload",
]


def insert_dated_meal(db_url, meal_name="Eggs", local_date="2026-09-25"):
    run_sql(
        db_url,
        [
            "INSERT INTO meals (user_id, meal_name, calories, protein_g, carbohydrates_g, "
            "fat_g, confidence, calorie_low, calorie_high, created_at, local_date) "
            f"VALUES (1, '{meal_name}', 400, 20, 35, 20, 0.85, 350, 450, "
            f"'{local_date} 12:00:00', '{local_date}')"
        ],
    )


def meal_columns(db_url):
    return {
        column["name"]: column
        for column in inspect(create_engine(db_url)).get_columns("meals")
    }


def test_provenance_migration_keeps_existing_meals_with_unknown_provenance(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0003_meal_local_date")
    insert_users_with_goals(db_url, [2633])
    insert_dated_meal(db_url)

    command.upgrade(alembic_cfg, "0004_meal_provenance")

    assert rows(db_url, "SELECT id, meal_name, calories, local_date FROM meals") == [
        (1, "Eggs", 400, "2026-09-25")
    ]
    assert rows(db_url, f"SELECT {', '.join(PROVENANCE_COLUMNS)} FROM meals") == [
        (None,) * len(PROVENANCE_COLUMNS)
    ]
    columns = meal_columns(db_url)
    assert all(columns[name]["nullable"] for name in PROVENANCE_COLUMNS)


def test_provenance_migration_downgrades_and_upgrades_again(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0004_meal_provenance")
    insert_users_with_goals(db_url, [2633])
    insert_dated_meal(db_url)
    run_sql(db_url, ["UPDATE meals SET source = 'text', ai_model = 'some-model'"])

    command.downgrade(alembic_cfg, "0003_meal_local_date")

    assert not set(PROVENANCE_COLUMNS) & set(meal_columns(db_url))
    assert rows(db_url, "SELECT id, meal_name FROM meals") == [(1, "Eggs")]

    command.upgrade(alembic_cfg, "0004_meal_provenance")

    assert rows(db_url, "SELECT source, ai_model FROM meals") == [(None, None)]
