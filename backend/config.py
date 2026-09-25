"""Backend settings, read once from the environment.

app.py loads backend/.env before this module is imported; values already set
in the environment win.
"""

import os
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def _setting(name: str, default: str) -> str:
    """The environment value, or the default when unset or blank."""
    return os.getenv(name) or default


DATABASE_URL = _setting("DATABASE_URL", "sqlite:///./nutrition.db")

OPENAI_MODEL = _setting("OPENAI_MODEL", "gpt-4.1-mini")
OPENAI_TIMEOUT_SECONDS = float(_setting("OPENAI_TIMEOUT_SECONDS", "60"))
OPENAI_MAX_RETRIES = int(_setting("OPENAI_MAX_RETRIES", "1"))


def _is_timezone(name: str) -> bool:
    try:
        ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError, OSError):
        return False
    return True


def _server_timezone() -> str:
    """The server's IANA timezone name (from TZ or /etc/localtime), else UTC."""

    candidates = [os.getenv("TZ", "").lstrip(":")]
    try:
        localtime = os.path.realpath("/etc/localtime")
    except OSError:
        localtime = ""
    if "zoneinfo/" in localtime:
        candidates.append(localtime.split("zoneinfo/", 1)[1])

    for name in candidates:
        if name and _is_timezone(name):
            return name
    return "UTC"


# The timezone that decides "today" when a request has no X-Timezone header,
# and the zone used to backfill existing meals' local dates.
DEFAULT_TIMEZONE = os.getenv("DEFAULT_TIMEZONE") or _server_timezone()

if not _is_timezone(DEFAULT_TIMEZONE):
    raise ValueError(
        f"DEFAULT_TIMEZONE={DEFAULT_TIMEZONE!r} is not a known IANA timezone "
        "name (for example America/New_York)."
    )
