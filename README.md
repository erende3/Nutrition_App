# MyNutritionPal

AI-powered calorie and nutrition tracker: a SwiftUI iOS app (`frontend/`) and a FastAPI backend (`backend/`).

## Backend

Requires Python 3.11. Keep the repository outside iCloud-synced folders (such as `~/Desktop` or `~/Documents` with iCloud Drive enabled); iCloud can stall file reads for minutes, which freezes imports and the server.

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env        # then set OPENAI_API_KEY in .env
python app.py               # migrates the database, then serves on http://0.0.0.0:8000 (API docs at /docs)
```

`python app.py` auto-reloads on code changes and ignores `.venv`. To run uvicorn directly with the same behavior (reachable from a phone on your LAN), migrate first:

```bash
alembic upgrade head
uvicorn app:app --host 0.0.0.0 --port 8000 --reload --reload-exclude "$PWD/.venv"
```

The `--reload-exclude` path must be absolute, and it only takes effect when `watchfiles` is installed (it is in `requirements-dev.txt`).

Run the tests (from `backend/`, with the virtualenv active):

```bash
python -m pytest
```

Tests use a temporary database and a fake nutrition estimator. They never call OpenAI or touch `nutrition.db`.

### Database migrations

The schema is managed by Alembic (`backend/migrations/`). Run commands from `backend/`.

- `python app.py` runs `alembic upgrade head` before serving. If the migration fails, it exits without starting the server, so it never serves against an outdated or partly migrated schema. Importing the app never migrates.
- **Restart `python app.py` after pulling a new migration.** Auto-reload restarts the server on code changes but does not migrate.
- A database created before Alembic (tables but no migration history) is refused. Back it up, then stamp it once: `alembic stamp 0001_baseline`, then `alembic upgrade head`.
- Migration `0003` fills in existing meals' local dates using `DEFAULT_TIMEZONE`. Set it explicitly when migrating data logged in a different zone from the server's.
- **Switching branches:** code from before Milestone 0.4 cannot log meals against a migrated database (it doesn't know `local_date`). To run older code, restore your backup or run `alembic downgrade 0001_baseline` first.

### Configuration

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | For meal estimates | none | OpenAI access. Put it in `backend/.env`. |
| `DATABASE_URL` | No | `sqlite:///./nutrition.db` | SQLAlchemy database URL. Set it in `backend/.env` or in the shell; a shell value wins. The default path is relative to the directory you start the server from. |
| `OPENAI_MODEL` | No | `gpt-4.1-mini` | Model used for meal estimates. |
| `OPENAI_TIMEOUT_SECONDS` | No | `60` | Per-attempt timeout for the OpenAI request. Keep the worst case (timeout × (retries + 1)) under the iOS app's 300-second request timeout. |
| `OPENAI_MAX_RETRIES` | No | `1` | How many times the OpenAI SDK retries a failed request. |
| `DEFAULT_TIMEZONE` | No | The server's timezone (`TZ` or `/etc/localtime`), else `UTC` | IANA timezone (e.g. `America/New_York`) that decides "today" when a request has no `X-Timezone` header, and that migration `0003` uses to date existing meals. An unknown name stops startup. |

Blank values in `.env` count as unset.

All settings are read in `backend/config.py`.

**Days and timezones.** Each meal stores `local_date`, the user's calendar date when it was logged. Today's meals, clearing today and the daily summary use the date in the request's timezone: the optional `X-Timezone` header (an IANA name) or `DEFAULT_TIMEZONE`. An unknown `X-Timezone` returns 400. The iOS app doesn't send the header yet, so the server's timezone is used.

**Calorie goals.** A stored goal is always positive. If the calculation gives 0 or less (only possible for extreme inputs), onboarding stores the default goal (2200) and returns `goal_adjusted: true`. There are no minimum or maximum goal policies yet.

When an estimate fails, the API returns 503 (estimator not configured, e.g. no API key), 504 (the AI provider timed out), 502 (the AI provider failed) or 500 (anything else), with a generic `detail` message. The underlying error is logged by the server, never returned to the client.

## iOS app

Open `frontend/MyNutritionPal/MyNutritionPal.xcodeproj` in Xcode (iOS 18.5+).

The backend address is currently hardcoded as `baseURL` in `frontend/MyNutritionPal/MyNutritionPal/NutritionAPI.swift`. Set it to `http://<your Mac's LAN IP>:8000`, and keep the phone and the Mac on the same network.
