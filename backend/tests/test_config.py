import json
import os
import subprocess
import sys
from pathlib import Path
from zoneinfo import ZoneInfo

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


def load_default_timezone(**env_overrides):
    env = {key: value for key, value in os.environ.items() if key not in ("TZ", "DEFAULT_TIMEZONE")}
    env.update(env_overrides)
    return subprocess.run(
        [sys.executable, "-c", "import config; print(config.DEFAULT_TIMEZONE)"],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_default_timezone_follows_the_server_timezone():
    result = load_default_timezone(TZ="Asia/Tokyo")

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "Asia/Tokyo"


def test_default_timezone_without_tz_is_a_valid_zone():
    result = load_default_timezone()

    assert result.returncode == 0, result.stderr
    ZoneInfo(result.stdout.strip())


def test_default_timezone_can_be_set_explicitly():
    result = load_default_timezone(TZ="Asia/Tokyo", DEFAULT_TIMEZONE="Europe/Paris")

    assert result.stdout.strip() == "Europe/Paris"


def test_unknown_default_timezone_fails_at_startup():
    result = load_default_timezone(DEFAULT_TIMEZONE="Mars/Olympus_Mons")

    assert result.returncode != 0
    assert "DEFAULT_TIMEZONE='Mars/Olympus_Mons' is not a known IANA timezone" in result.stderr
