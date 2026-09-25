"""Run and check the Alembic migrations for the app database.

Nothing here runs on import; app.py calls upgrade_to_head() only when
started as a script.
"""

from pathlib import Path

from alembic import command
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine, inspect

import config as settings

BACKEND = Path(__file__).resolve().parent


class MigrationError(RuntimeError):
    """The database is not in a state the app can safely migrate or serve."""


def alembic_config(database_url=None, script_location=None) -> Config:
    alembic_cfg = Config(str(BACKEND / "alembic.ini"))
    alembic_cfg.set_main_option(
        "script_location",
        str(script_location or BACKEND / "migrations"),
    )
    # The config parser treats "%" as interpolation.
    alembic_cfg.set_main_option(
        "sqlalchemy.url",
        (database_url or settings.DATABASE_URL).replace("%", "%%"),
    )
    return alembic_cfg


def current_revision(database_url=None) -> str | None:
    engine = create_engine(database_url or settings.DATABASE_URL)
    try:
        with engine.connect() as connection:
            return MigrationContext.configure(connection).get_current_revision()
    finally:
        engine.dispose()


def head_revision(script_location=None) -> str | None:
    return ScriptDirectory.from_config(
        alembic_config(script_location=script_location)
    ).get_current_head()


def ensure_at_head(database_url=None, script_location=None) -> None:
    current = current_revision(database_url)
    head = head_revision(script_location)

    if current != head:
        raise MigrationError(
            f"The database is at revision {current} but the code expects {head}. "
            "Run `alembic upgrade head` from backend/."
        )


def _has_app_tables(database_url) -> bool:
    engine = create_engine(database_url)
    try:
        tables = set(inspect(engine).get_table_names())
    finally:
        engine.dispose()
    return bool(tables - {"alembic_version"})


def upgrade_to_head(database_url=None, script_location=None) -> None:
    """Upgrade to the latest revision, then verify the database is there."""

    url = database_url or settings.DATABASE_URL

    if current_revision(url) is None and _has_app_tables(url):
        raise MigrationError(
            "The database has tables but no migration history (it was created "
            "before Alembic). Back it up, then run "
            "`alembic stamp 0001_baseline` from backend/."
        )

    command.upgrade(alembic_config(url, script_location), "head")
    ensure_at_head(url, script_location)
