"""Alembic migrations: parity with the models, the pre-Alembic upgrade path,
all-or-nothing revisions, and the `python app.py` migrate-before-serve path.

Every test uses its own temporary SQLite file, never the app's database.
"""

import shutil
from datetime import datetime
from functools import partial
from zoneinfo import ZoneInfo
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
    assert rows(db_url, "SELECT user_id, calories, source FROM daily_goals") == [
        (1, 2633, "migrated")
    ]
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


def insert_dated_meal(db_url, meal_name="Eggs", local_date="2026-09-25", user_id=1):
    run_sql(
        db_url,
        [
            "INSERT INTO meals (user_id, meal_name, calories, protein_g, carbohydrates_g, "
            "fat_g, confidence, calorie_low, calorie_high, created_at, local_date) "
            f"VALUES ({user_id}, '{meal_name}', 400, 20, 35, 20, 0.85, 350, 450, "
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


GOAL_ROWS = "SELECT user_id, effective_date, calories, source FROM daily_goals ORDER BY user_id"


def test_goal_history_migration_copies_each_goal_from_the_earliest_meal_date(
    db_url, monkeypatch
):
    monkeypatch.setattr(config, "DEFAULT_TIMEZONE", "Pacific/Auckland")
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0004_meal_provenance")
    insert_users_with_goals(db_url, [2633, 1800, 2200])
    insert_dated_meal(db_url, local_date="2026-09-03")
    insert_dated_meal(db_url, local_date="2026-09-01")
    insert_dated_meal(db_url, local_date="2026-09-10", user_id=2)

    before = datetime.now(ZoneInfo("Pacific/Auckland")).date().isoformat()
    command.upgrade(alembic_cfg, "0005_daily_goals")
    after = datetime.now(ZoneInfo("Pacific/Auckland")).date().isoformat()

    goals = rows(db_url, GOAL_ROWS)
    assert goals[:2] == [
        (1, "2026-09-01", 2633, "migrated"),
        (2, "2026-09-10", 1800, "migrated"),
    ]
    # No meals: the migration date in DEFAULT_TIMEZONE.
    assert goals[2][0] == 3 and goals[2][2:] == (2200, "migrated")
    assert goals[2][1] in {before, after}
    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users ORDER BY id") == [
        (1, 2633),
        (2, 1800),
        (3, 2200),
    ]
    assert rows(db_url, "SELECT count(*) FROM daily_goals WHERE created_at IS NULL") == [(0,)]


def test_goal_history_rejects_non_positive_goals_and_two_goals_on_one_day(db_url):
    command.upgrade(db_migrations.alembic_config(db_url), "0005_daily_goals")
    insert_users_with_goals(db_url, [2633])

    def insert_goal(calories, effective_date="2026-09-01"):
        run_sql(
            db_url,
            [
                "INSERT INTO daily_goals (user_id, effective_date, calories, source, "
                f"created_at) VALUES (1, '{effective_date}', {calories}, 'calculated', "
                "'2026-09-01 12:00:00')"
            ],
        )

    for calories in (0, -1):
        with pytest.raises(IntegrityError):
            insert_goal(calories)
    insert_goal(2633)
    with pytest.raises(IntegrityError):
        insert_goal(1800)
    assert rows(db_url, GOAL_ROWS) == [(1, "2026-09-01", 2633, "calculated")]


def test_goal_history_migration_downgrades_and_upgrades_again(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0005_daily_goals")
    insert_users_with_goals(db_url, [2633])

    command.downgrade(alembic_cfg, "0004_meal_provenance")

    assert "daily_goals" not in inspect(create_engine(db_url)).get_table_names()
    assert rows(db_url, "SELECT daily_calorie_goal FROM users") == [(2633,)]

    insert_dated_meal(db_url, local_date="2026-09-05")
    command.upgrade(alembic_cfg, "0005_daily_goals")

    assert rows(db_url, GOAL_ROWS) == [(1, "2026-09-05", 2633, "migrated")]


def user_columns(db_url):
    return {column["name"] for column in inspect(create_engine(db_url)).get_columns("users")}


def test_dropping_the_user_goal_column_keeps_users_meals_and_goals(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0005_daily_goals")
    insert_users_with_goals(db_url, [2633])
    run_sql(db_url, ["UPDATE users SET age = 30, sex = 'male' WHERE id = 1"])
    insert_dated_meal(db_url, local_date="2026-09-01")
    command.downgrade(alembic_cfg, "0004_meal_provenance")
    command.upgrade(alembic_cfg, "0005_daily_goals")

    command.upgrade(alembic_cfg, "0006_drop_user_goal_column")

    assert "daily_calorie_goal" not in user_columns(db_url)
    assert rows(db_url, "SELECT id, age, sex FROM users") == [(1, 30, "male")]
    assert rows(db_url, "SELECT id, user_id, meal_name, local_date FROM meals") == [
        (1, 1, "Eggs", "2026-09-01")
    ]
    assert rows(db_url, GOAL_ROWS) == [(1, "2026-09-01", 2633, "migrated")]


def test_restoring_the_user_goal_column_uses_the_latest_goal(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0006_drop_user_goal_column")
    run_sql(
        db_url,
        [
            "INSERT INTO users (id) VALUES (1), (2)",
            "INSERT INTO daily_goals (user_id, effective_date, calories, source, created_at) "
            "VALUES (1, '2026-09-26', 2856, 'calculated', '2026-09-26 12:00:00'), "
            "(1, '2026-09-01', 2633, 'migrated', '2026-09-01 12:00:00')",
        ],
    )

    command.downgrade(alembic_cfg, "0005_daily_goals")

    # User 2 never had a goal: the default.
    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users ORDER BY id") == [
        (1, 2856),
        (2, 2200),
    ]
    with pytest.raises(IntegrityError):
        run_sql(db_url, ["UPDATE users SET daily_calorie_goal = 0 WHERE id = 1"])


def test_full_round_trip_keeps_meals_and_the_current_goal(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, "0003_meal_local_date")
    insert_users_with_goals(db_url, [2633])
    insert_dated_meal(db_url, local_date="2026-09-01")
    insert_dated_meal(db_url, meal_name="Soup", local_date="2026-09-25")
    before = rows(db_url, "SELECT * FROM meals ORDER BY id")

    command.upgrade(alembic_cfg, "head")
    command.downgrade(alembic_cfg, "0003_meal_local_date")

    assert rows(db_url, "SELECT * FROM meals ORDER BY id") == before
    assert rows(db_url, "SELECT id, daily_calorie_goal FROM users") == [(1, 2633)]

    command.upgrade(alembic_cfg, "head")

    assert db_migrations.current_revision(db_url) == head()
    assert rows(db_url, GOAL_ROWS) == [(1, "2026-09-01", 2633, "migrated")]


IDENTITY = "0007_meal_identity_and_edits"
BEFORE_IDENTITY = "0006_drop_user_goal_column"
MEAL_INDEXES = {"ix_meals_id", "ix_meals_user_id", "ix_meals_user_local_date"}


def meals_sql(db_url):
    return rows(db_url, "SELECT sql FROM sqlite_master WHERE name = 'meals'")[0][0]


def meals_sequence(db_url):
    return rows(db_url, "SELECT seq FROM sqlite_sequence WHERE name = 'meals'")


def insert_meals_with_ids(db_url, ids):
    run_sql(
        db_url,
        [
            "INSERT INTO meals (id, user_id, meal_name, calories, protein_g, "
            "carbohydrates_g, fat_g, confidence, calorie_low, calorie_high, created_at, "
            "local_date, source, description, ai_provider, ai_model, prompt_version, "
            f"ai_payload) VALUES ({meal_id}, 1, 'Meal {meal_id}', {meal_id * 10}, 1.3, "
            f"27.0, 0.3, 0.85, 90, 120, '2026-09-25 12:00:0{index}.156307', '2026-09-25', "
            "'text', 'a banana', 'openai', 'gpt-4.1-mini', 'v1', "
            "'{\"assumptions\": [\"one medium banana\"]}')"
            for index, meal_id in enumerate(ids)
        ],
    )


def test_identity_migration_keeps_every_meal_and_stops_reusing_ids(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, BEFORE_IDENTITY)
    run_sql(db_url, ["INSERT INTO users (id, age) VALUES (1, 30)"])
    insert_meals_with_ids(db_url, [3, 7, 16])
    before = rows(db_url, "SELECT * FROM meals ORDER BY id")

    command.upgrade(alembic_cfg, IDENTITY)

    assert rows(db_url, "SELECT * FROM meals ORDER BY id") == [tuple(row) + (None,) for row in before]
    assert "AUTOINCREMENT" in meals_sql(db_url)
    assert meals_sequence(db_url) == [(16,)]
    columns = meal_columns(db_url)
    assert columns["edited_at"]["nullable"] is True
    inspector = inspect(create_engine(db_url))
    assert {index["name"] for index in inspector.get_indexes("meals")} == MEAL_INDEXES
    assert [
        (key["referred_table"], key["constrained_columns"], key["referred_columns"])
        for key in inspector.get_foreign_keys("meals")
    ] == [("users", ["user_id"], ["id"])]
    assert rows(db_url, "PRAGMA integrity_check") == [("ok",)]

    # The newest meal's id is never handed out again.
    run_sql(db_url, ["DELETE FROM meals WHERE id = 16"])
    insert_dated_meal(db_url)
    assert rows(db_url, "SELECT max(id) FROM meals") == [(17,)]


def test_new_database_never_reuses_meal_ids(db_url):
    db_migrations.upgrade_to_head(db_url)
    run_sql(db_url, ["INSERT INTO users (id) VALUES (1)"])

    insert_dated_meal(db_url)
    insert_dated_meal(db_url)
    run_sql(db_url, ["DELETE FROM meals WHERE id = 2"])
    insert_dated_meal(db_url)

    assert rows(db_url, "SELECT id FROM meals ORDER BY id") == [(1,), (3,)]


def test_the_models_create_meals_with_autoincrement(db_url):
    engine = create_engine(db_url)
    Base.metadata.create_all(engine)

    assert "AUTOINCREMENT" in meals_sql(db_url)


def test_identity_migration_downgrades_and_upgrades_again(db_url):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, BEFORE_IDENTITY)
    run_sql(db_url, ["INSERT INTO users (id) VALUES (1)"])
    insert_meals_with_ids(db_url, [4, 9])
    before = rows(db_url, "SELECT * FROM meals ORDER BY id")
    command.upgrade(alembic_cfg, IDENTITY)
    run_sql(db_url, ["UPDATE meals SET edited_at = '2026-09-28 14:05:00' WHERE id = 9"])

    command.downgrade(alembic_cfg, BEFORE_IDENTITY)

    assert "edited_at" not in meal_columns(db_url)
    assert "AUTOINCREMENT" not in meals_sql(db_url)
    assert rows(db_url, "SELECT * FROM meals ORDER BY id") == before
    assert meals_sequence(db_url) == []
    assert {index["name"] for index in inspect(create_engine(db_url)).get_indexes("meals")} == MEAL_INDEXES

    command.upgrade(alembic_cfg, IDENTITY)

    assert rows(db_url, "SELECT id, edited_at FROM meals ORDER BY id") == [(4, None), (9, None)]
    assert meals_sequence(db_url) == [(9,)]
    assert rows(db_url, "PRAGMA integrity_check") == [("ok",)]


def test_failed_identity_migration_leaves_meals_at_the_previous_revision(db_url, tmp_path):
    alembic_cfg = db_migrations.alembic_config(db_url)
    command.upgrade(alembic_cfg, BEFORE_IDENTITY)
    run_sql(db_url, ["INSERT INTO users (id) VALUES (1)"])
    insert_meals_with_ids(db_url, [5])
    before_rows = rows(db_url, "SELECT * FROM meals")
    before_sql = meals_sql(db_url)
    location = tmp_path / "scripts"
    shutil.copytree(BACKEND / "migrations", location, ignore=shutil.ignore_patterns("__pycache__"))
    revision = location / "versions" / f"{IDENTITY}.py"
    revision.write_text(
        revision.read_text().replace(
            "def downgrade()",
            "_original_upgrade = upgrade\n\n\n"
            "def upgrade():\n"
            "    _original_upgrade()\n"
            "    raise RuntimeError('deliberately broken migration')\n\n\n"
            "def downgrade()",
        )
    )

    with pytest.raises(RuntimeError, match="deliberately broken"):
        db_migrations.upgrade_to_head(db_url, script_location=location)

    assert db_migrations.current_revision(db_url) == BEFORE_IDENTITY
    assert meals_sql(db_url) == before_sql
    assert rows(db_url, "SELECT * FROM meals") == before_rows
    assert rows(db_url, "PRAGMA integrity_check") == [("ok",)]
