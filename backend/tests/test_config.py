import json
import os
import subprocess
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
SETTINGS = ("DATABASE_URL", "OPENAI_MODEL", "OPENAI_TIMEOUT_SECONDS", "OPENAI_MAX_RETRIES")
PRINT_SETTINGS = (
    "import config, json; print(json.dumps({name: getattr(config, name) for name in "
    + repr(SETTINGS)
    + "}))"
)


def load_settings(**overrides):
    env = {key: value for key, value in os.environ.items() if key not in SETTINGS}
    env.update(overrides)
    result = subprocess.run(
        [sys.executable, "-c", PRINT_SETTINGS],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_settings_defaults():
    assert load_settings() == {
        "DATABASE_URL": "sqlite:///./nutrition.db",
        "OPENAI_MODEL": "gpt-4.1-mini",
        "OPENAI_TIMEOUT_SECONDS": 60.0,
        "OPENAI_MAX_RETRIES": 1,
    }


def test_settings_come_from_the_environment():
    assert load_settings(
        DATABASE_URL="sqlite:///x.db",
        OPENAI_MODEL="m2",
        OPENAI_TIMEOUT_SECONDS="12.5",
        OPENAI_MAX_RETRIES="0",
    ) == {
        "DATABASE_URL": "sqlite:///x.db",
        "OPENAI_MODEL": "m2",
        "OPENAI_TIMEOUT_SECONDS": 12.5,
        "OPENAI_MAX_RETRIES": 0,
    }


def test_blank_settings_fall_back_to_defaults():
    assert load_settings(
        DATABASE_URL="",
        OPENAI_MODEL="",
        OPENAI_TIMEOUT_SECONDS="",
        OPENAI_MAX_RETRIES="",
    ) == {
        "DATABASE_URL": "sqlite:///./nutrition.db",
        "OPENAI_MODEL": "gpt-4.1-mini",
        "OPENAI_TIMEOUT_SECONDS": 60.0,
        "OPENAI_MAX_RETRIES": 1,
    }
