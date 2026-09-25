"""Alembic environment.

The database URL comes from the caller (db_migrations.alembic_config) or,
for the alembic CLI, from DATABASE_URL via config.py.
"""

from logging.config import fileConfig

from alembic import context
from dotenv import load_dotenv
from sqlalchemy import create_engine, event

# The alembic CLI does not go through app.py, so load backend/.env here too.
# Values already in the environment win.
load_dotenv()

import config as settings  # noqa: E402
import models  # noqa: E402

alembic_config = context.config

# Only the CLI configures logging; programmatic runs keep the app's loggers.
if alembic_config.cmd_opts is not None and alembic_config.config_file_name:
    fileConfig(alembic_config.config_file_name, disable_existing_loggers=False)


def run_migrations_online() -> None:
    url = alembic_config.get_main_option("sqlalchemy.url") or settings.DATABASE_URL
    engine = create_engine(url)

    if engine.dialect.name == "sqlite":
        # pysqlite does not put DDL inside transactions on its own. Take over
        # BEGIN so a revision that fails partway rolls back completely.
        @event.listens_for(engine, "connect")
        def _disable_pysqlite_transaction_handling(dbapi_connection, _record):
            dbapi_connection.isolation_level = None

        @event.listens_for(engine, "begin")
        def _begin(connection):
            connection.exec_driver_sql("BEGIN")

    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=models.Base.metadata,
                # SQLite cannot alter constraints or columns in place.
                render_as_batch=True,
                transaction_per_migration=True,
            )
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()


if context.is_offline_mode():
    raise SystemExit("Offline (SQL script) migrations are not supported.")

run_migrations_online()
