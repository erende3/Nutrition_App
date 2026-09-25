import os
import shutil
import subprocess
import sys
import warnings
from pathlib import Path

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
