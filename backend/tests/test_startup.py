import os
import shutil
import sqlite3
import subprocess
import sys
import warnings
from pathlib import Path

import pytest

import app as app_module

BACKEND = Path(__file__).resolve().parent.parent


def run_python(code, cwd, env):
    return subprocess.run(
        [sys.executable, "-c", code],
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_openapi_has_no_duplicate_operations():
    app_module.app.openapi_schema = None
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        app_module.app.openapi()

    duplicates = [
        str(warning.message)
        for warning in caught
        if "Duplicate Operation ID" in str(warning.message)
    ]
    assert duplicates == []


def test_importing_app_prints_nothing(tmp_path):
    env = {**os.environ, "DATABASE_URL": f"sqlite:///{tmp_path / 'startup.db'}"}

    result = run_python("import app", cwd=BACKEND, env=env)

    assert result.returncode == 0, result.stderr
    assert result.stdout == ""


def test_importing_app_creates_no_tables_and_runs_no_migrations(tmp_path):
    database = tmp_path / "import-only.db"
    env = {**os.environ, "DATABASE_URL": f"sqlite:///{database}"}

    result = run_python("import app", cwd=BACKEND, env=env)

    assert result.returncode == 0, result.stderr
    if database.exists():
        with sqlite3.connect(database) as connection:
            tables = connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            ).fetchall()
        assert tables == []


def test_database_url_can_be_set_in_dotenv(tmp_path):
    for source in BACKEND.glob("*.py"):
        shutil.copy(source, tmp_path / source.name)
    for package in ("routes", "services"):
        shutil.copytree(
            BACKEND / package,
            tmp_path / package,
            ignore=shutil.ignore_patterns("__pycache__"),
        )
    dotenv_url = f"sqlite:///{tmp_path / 'from_dotenv.db'}"
    (tmp_path / ".env").write_text(f"DATABASE_URL={dotenv_url}\n")
    env = {key: value for key, value in os.environ.items() if key != "DATABASE_URL"}

    result = run_python(
        "import app, database; print(database.engine.url.render_as_string())",
        cwd=tmp_path,
        env=env,
    )

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip().splitlines()[-1] == dotenv_url


@pytest.mark.parametrize("has_venv", [True, False])
def test_main_excludes_venv_from_reload_only_when_it_exists(tmp_path, monkeypatch, has_venv):
    # A git worktree has no backend/.venv (it runs the main checkout's), and
    # uvicorn rejects an absolute exclude path that doesn't exist.
    import db_migrations
    import uvicorn

    venv = tmp_path / ".venv"
    if has_venv:
        venv.mkdir()
    monkeypatch.setattr(app_module, "__file__", str(tmp_path / "app.py"))
    monkeypatch.setattr(db_migrations, "upgrade_to_head", lambda: None)
    calls = []
    monkeypatch.setattr(uvicorn, "run", lambda *args, **kwargs: calls.append(kwargs))

    app_module.main()

    assert calls[0]["reload_excludes"] == ([str(venv)] if has_venv else [])
