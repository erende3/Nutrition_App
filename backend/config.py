"""Backend settings, read once from the environment.

app.py loads backend/.env before this module is imported; values already set
in the environment win.
"""

import os


def _setting(name: str, default: str) -> str:
    """The environment value, or the default when unset or blank."""
    return os.getenv(name) or default


DATABASE_URL = _setting("DATABASE_URL", "sqlite:///./nutrition.db")

OPENAI_MODEL = _setting("OPENAI_MODEL", "gpt-4.1-mini")
OPENAI_TIMEOUT_SECONDS = float(_setting("OPENAI_TIMEOUT_SECONDS", "60"))
OPENAI_MAX_RETRIES = int(_setting("OPENAI_MAX_RETRIES", "1"))
