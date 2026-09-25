"""Backend settings, read once from the environment.

app.py loads backend/.env before this module is imported; values already set
in the environment win.
"""

import os

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./nutrition.db")

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
OPENAI_TIMEOUT_SECONDS = float(os.getenv("OPENAI_TIMEOUT_SECONDS", "60"))
OPENAI_MAX_RETRIES = int(os.getenv("OPENAI_MAX_RETRIES", "1"))
