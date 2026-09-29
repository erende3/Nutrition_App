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
- **Switching branches:** code from before Milestone 0.4 cannot log meals against a migrated database (it doesn't know `local_date`), and code from before Milestone 0.8 can't run against revision `0006` or later (it reads `users.daily_calorie_goal`, which `0006` removes). To run older code, restore your backup, or downgrade first: `alembic downgrade 0003_meal_local_date` for 0.4–0.7 code, `alembic downgrade 0001_baseline` for older code. Code from before Milestone 0.12 won't start against revision `0007` (it doesn't know that revision); downgrade with `alembic downgrade 0006_drop_user_goal_column` to run it (meal ids can then be reused again, and edit times are dropped).
- **Back up before migrating** (`cp nutrition.db nutrition.db.pre-<version>.bak`). The backup is the real rollback: a downgrade keeps your meals, but downgrading below `0005` discards goal history (only each user's latest goal survives, in `users`), and below `0004` discards the recorded provenance of meals logged since.

### Configuration

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | For meal estimates | none | OpenAI access. Put it in `backend/.env`. |
| `DATABASE_URL` | No | `sqlite:///./nutrition.db` | SQLAlchemy database URL. Set it in `backend/.env` or in the shell; a shell value wins. The default path is relative to the directory you start the server from. |
| `OPENAI_MODEL` | No | `gpt-4.1-mini` | Model used for meal estimates. |
| `OPENAI_TIMEOUT_SECONDS` | No | `60` | Per-attempt timeout for the OpenAI request. Keep the worst case (timeout × (retries + 1)) under the iOS app's 300-second request timeout. |
| `OPENAI_MAX_RETRIES` | No | `1` | How many times the OpenAI SDK retries a failed request. |
| `MAX_IMAGE_BYTES` | No | `10485760` (10 MiB) | Largest meal photo `POST /meals/estimate` accepts. Must be positive, or startup stops. |
| `DEFAULT_TIMEZONE` | No | The server's timezone (`TZ` or `/etc/localtime`), else `UTC` | IANA timezone (e.g. `America/New_York`) that decides "today" when a request has no `X-Timezone` header, and that migration `0003` uses to date existing meals. An unknown name stops startup. |

Blank values in `.env` count as unset.

All settings are read in `backend/config.py`.

**Days and timezones.** Each meal stores `local_date`, the user's calendar date when it was logged. Today's meals, clearing today and the daily summary use the date in the request's timezone: the optional `X-Timezone` header (an IANA name) or `DEFAULT_TIMEZONE`. An unknown `X-Timezone` returns 400. The iOS app sends the phone's timezone on every request, so "today" is the phone's day; `DEFAULT_TIMEZONE` applies to clients that don't send the header.

**Calorie goals.** Goals are kept over time in `daily_goals`: each row is a user's goal from its `effective_date` until their next one. Onboarding sets the goal from the user's today on (in the `X-Timezone` zone); onboarding again the same day replaces that day's goal. A day's summary uses the latest goal on or before that day, so changing the goal leaves earlier days alone; the profile shows the most recent goal. With no goal (before onboarding) the default, 2200, applies. Each goal records its `source`: `calculated`, `default` (see below) or `migrated` (the goal a user had before goal history, from migration `0005`). The allowed values are defined once, in `GoalSource` (`schemas.py`).

A stored goal is always positive. If the calculation gives 0 or less (only possible for extreme inputs), onboarding stores the default goal (2200) with source `default` and returns `goal_adjusted: true`, and the iOS app then says the default goal was used. There are no minimum or maximum goal policies yet: a positive goal is kept even when it's implausibly low (inputs the app accepts can give goals down to 1 kcal). **That policy is an open product decision, required before the Phase 5 goal and macro features.**

When an estimate fails, the API returns 503 (estimator not configured, e.g. no API key), 504 (the AI provider timed out), 502 (the AI provider failed) or 500 (anything else), with a generic `detail` message. The underlying error is logged by the server, never returned to the client.

**Meal photos.** An image sent to `POST /meals/estimate` must be JPEG, PNG or WebP, and its bytes must start like that type of file; otherwise the API returns 400. An image over `MAX_IMAGE_BYTES` returns 413. In both cases nothing is estimated or saved. Photos aren't stored: they go to the AI provider and are discarded.

**What a saved meal records.** Besides its totals, each meal stores how it was logged (`source`: `text` or `photo`, defined once in `MealSource`), the text submitted with it exactly as received (`description`), which AI made the estimate (`ai_provider`, `ai_model` and `prompt_version`), and the model's full estimate including its assumptions (`ai_payload`). API v1 returns `source`, `description` and the assumptions; the AI provider, model, prompt version and raw output stay internal. Meals logged before Milestone 0.8 have these fields empty: unknown, not guessed. `PROMPT_VERSION` in `services/nutrition_ai.py` must be bumped whenever the prompt, instructions or output schema change: a test pins each version to a hash of them and fails until the new version and its hash are added (existing entries must never be edited).

### API v1

The API is versioned under `/v1` (schema at `/v1/openapi.json`, docs at `/v1/docs`; every operation documents the error envelope as `ErrorResponse`). The unversioned routes (`/meals/...`, `/summary/daily`, `/users/...`) are frozen, unchanged, for app builds that still use them, and will be removed in a later milestone. Clients must ignore response fields they don't know: fields may be added without a new version.

| Request | Success | |
|---|---|---|
| `GET /v1/days/{YYYY-MM-DD}` | 200 day | The meals logged on that calendar date, newest first, with totals and the goal in effect that day |
| `POST /v1/meals/estimate` | 201 meal | Multipart `message` and/or `image`; estimates and saves the meal |
| `PATCH /v1/meals/{id}` | 200 meal | Edits a meal (below) |
| `DELETE /v1/meals/{id}` | 204, no body | |
| `GET /v1/users/profile` | 200 profile | Same as the unversioned route |
| `POST /v1/users/onboarding` | 200 result | Same as the unversioned route |

**Days.** `{date}` is the meal's stored `local_date`: the user's calendar date when it was logged. Reading a day never converts it (a meal logged at 23:30 in New York stays on that date wherever the user is later), so `X-Timezone` plays no part; the client asks for its own today. The goal is the one in effect that day (`{"calories": ...}`; where it came from stays internal). `calories_remaining` and `percentage` are exactly as `/summary/daily`: remaining never goes below 0, and percentage stops at 100, to 1 decimal. Macro totals are rounded to 1 decimal.

```json
{
  "date": "2026-09-27",
  "goal": {"calories": 2633},
  "totals": {"calories": 1250, "protein_g": 80.5, "carbohydrates_g": 120.0, "fat_g": 40.2},
  "calories_remaining": 1383,
  "percentage": 47.5,
  "meals": [{
    "id": 17, "meal_name": "Chicken and rice", "calories": 650,
    "protein_g": 45.0, "carbohydrates_g": 70.0, "fat_g": 15.0,
    "confidence": 0.8, "calorie_low": 550, "calorie_high": 750,
    "assumptions": ["1 cup cooked rice"], "source": "text",
    "description": "chicken and rice", "local_date": "2026-09-27",
    "created_at": "2026-09-27T18:04:11Z", "edited_at": null
  }]
}
```

A meal's `created_at` is UTC, always `YYYY-MM-DDTHH:MM:SSZ`; `edited_at` has the same format, or is `null` if the meal was never edited. `assumptions`, `source` and `description` are `null` for meals logged before they were recorded; `description` is also `null` for a photo meal sent without text (the estimator is then asked with the placeholder the app used to send, so the prompt version is unchanged). Photo meals that older app builds saved with that placeholder as their description are also served with `description: null`; the stored value isn't changed.

**Meal ids** are never reused from migration `0007` on: a deleted meal's id is never given to a new meal, so an id a client holds means the same meal or none. (Ids deleted above the highest one before that migration can't be known and may be used once more.)

**Editing a meal.** `PATCH /v1/meals/{id}` takes JSON with any of `meal_name`, `calories`, `protein_g`, `carbohydrates_g` and `fat_g` (at least one). Each is saved exactly as sent: calories and macros are independent, so nothing is rescaled or recalculated. The limits are input sanity, not nutrition advice: a name of 1–80 characters (trimmed), calories a whole number from 0 to 10,000, macros from 0 to 1,000 g. Anything else in the body (the description, date, time, source or AI fields), `null`, an empty body or a value out of range returns 422 `validation_failed`, and nothing changes. `edited_at` moves only when a value actually changes; sending the values a meal already has changes nothing. The meal's date, time, text and the AI's original range, confidence and assumptions are never changed, and totals follow the edit because they're summed when read. Another user's meal, or a missing one, is 404 `meal_not_found`. The last edit wins.

**Errors.** Every v1 error is JSON, `{"error": {"code": "...", "message": "..."}}`. The code is stable and machine-readable; the message is safe to show and may change. Validation errors add `"fields": [{"field": "body.age", "message": "..."}]` and never echo what was sent.

| Status | Code | When |
|---|---|---|
| 400 | `invalid_timezone` | `X-Timezone` isn't an IANA name (estimate, onboarding) |
| 400 | `unsupported_image_type`, `empty_image`, `invalid_image` | The photo isn't JPEG/PNG/WebP, is empty, or doesn't match its type |
| 400 | `bad_request` | A request body that can't be parsed at all |
| 404 | `meal_not_found`, `not_found` | No such meal (for this user); no such route |
| 405 | `method_not_allowed` | |
| 413 | `image_too_large` | Over `MAX_IMAGE_BYTES` |
| 422 | `validation_failed` | Invalid body, path, date or meal id; an estimate with neither text nor photo; an edit with nothing to change |
| 500 | `internal_error` | Anything unexpected; details are logged, never returned |
| 502 / 503 / 504 | `estimation_failed` / `estimation_unavailable` / `estimation_timeout` | The AI provider failed / isn't configured / timed out |
| other | `http_error` | Any other HTTP error the framework raises (fallback; not expected in normal use) |

The unversioned routes return the same failures as `{"detail": ...}`, as before.

## iOS app

Open `frontend/MyNutritionPal/MyNutritionPal.xcodeproj` in Xcode (iOS 18.5+).

### Backend address

Debug builds read the backend address from `frontend/MyNutritionPal/Config/Local.xcconfig`, which is git-ignored. Create it once:

```bash
cd frontend/MyNutritionPal/Config
cp Local.xcconfig.example Local.xcconfig
scutil --get LocalHostName     # e.g. Erics-MacBook-Pro
```

Then set `API_BASE_URL` in `Local.xcconfig`, and rebuild:

```
API_BASE_URL = http:/$()/Erics-MacBook-Pro.local:8000
```

- Write `http:/$()/`, not `http://`: in an xcconfig file, `//` starts a comment.
- The Mac's `.local` name stays the same when you change networks (home Wi-Fi, Personal Hotspot), so switching networks doesn't need a rebuild. If a network blocks it, use the Mac's LAN IP instead (`ipconfig getifaddr en0`), e.g. `http:/$()/192.168.1.20:8000`, and rebuild when it changes.
- Keep the phone and the Mac on the same network, and allow the app's Local Network prompt on first launch (Settings > Privacy & Security > Local Network).
- Without `Local.xcconfig`, the app builds but says no server address is set. Release builds have no address until there's a production backend.
- The app allows plain HTTP only to local-network hosts (`NSAllowsLocalNetworking`).

### How the app calls the backend

All requests go through `APIClient.swift`, to API v1. It sends the phone's timezone in `X-Timezone`, waits up to 300 s for a meal estimate and 20 s for anything else, and never retries on its own (an estimate saves the meal, so a retry could log it twice). Failures show the error envelope's `message` (the `code` is kept on `APIError`), or say which server couldn't be reached. A cancelled request (for example, when you leave a screen mid-load) isn't shown as an error.

### Today's data and refreshing

The Today tab and History read the same shared state, `NutritionStore.swift`: today, loaded in one request (`GET /v1/days/{date}`, with the date worked out on the phone, in its timezone, at each refresh). Each screen keeps its own form, photo and error state. The store refreshes today:

- when the tabs first appear, and whenever the app becomes active again (for example, back from Settings after switching Wi-Fi, from Control Center, or on a new day);
- at midnight, or when the timezone changes, while the app is open;
- when you pull to refresh on either screen, or tap Retry;
- after a meal is logged or deleted, so both screens update together.

Refreshes that overlap share one request. If a refresh fails, the data already on screen stays and a banner explains the problem, with Retry. Nothing watches the network or retries on its own; the next refresh simply uses the current network.

**History by date.** History opens on today (the shared day above) and can show any earlier day: previous and next day, the date (which opens a calendar limited to today and earlier) and a Today button. A past day is loaded separately and never replaces today's data. Choosing another day clears the old day's meals at once, and only the most recent choice's answer is shown, so a day's meals never appear under another date. The chosen day stays while the app runs (including in the background); on today, History moves to the new day at midnight. Deleting a meal refetches the day it was on.

**Meal details and editing.** Tapping a meal in History opens its details: its numbers, when it was logged (and last edited), what it was logged from, and the AI's original estimate (range, confidence, assumptions), leaving out anything the server doesn't have. **Edit** opens a sheet for the name, calories and macros. Save is enabled once something changed and everything is valid; problems are explained under each field. Cancel discards; swiping the sheet down with changes asks first; if saving fails, what you typed stays. A saved edit shows at once, and only that meal's day is fetched again (today's, if the date changed while it was open). If the meal was deleted meanwhile, the app says so instead of saving. Swipe to delete still works on the rows.

### Meal photos

**Take Photo** uses the camera and appears only when the device has a usable one. **Choose Photo** picks from the photo library (`PhotosPicker`, which needs no photo-library permission). Either way, the app prepares the photo in the background as soon as it's picked (`MealPhoto.swift`): at most 1536 px on the long edge, upright, JPEG at quality 0.7, and without the original's metadata, so no location is sent. A typical phone photo uploads at a few hundred KB. While a photo is being prepared (a library photo may first download from iCloud), **Cancel** stops waiting for it and keeps any photo picked earlier.

### Onboarding

Onboarding accepts ages 13–120, heights 3'0"–8'11" and weights 70–700 lb. A weight outside that range, or one that isn't a number, is explained on the screen and blocks Continue; it's never changed silently. These are the app's input limits, not nutrition advice.

### Look and design tokens

The app follows the phone's light or dark appearance. Colors are named sets in `Assets.xcassets`, each with a light and a dark value (the emerald accent is `AccentColor`), used through Xcode's generated symbols such as `Color.surface` or `.foregroundStyle(.textSecondary)`. `DesignSystem/Theme.swift` holds the two corner radii and the style for numbers; `DesignSystem/Components.swift` holds the card surface, the primary button and the inline error. Text uses Dynamic Type styles. Use these rather than fixed colors or font sizes, and check a change in both appearances and at a large accessibility text size.

### Tests

```bash
cd frontend/MyNutritionPal
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme MyNutritionPal -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:MyNutritionPalTests API_BASE_URL=
```

Use a simulator with iOS 18.5 or later. The unit tests use a stubbed network. Xcode launches the app itself as the test host, though, and the app makes its usual launch requests (reading the profile, then today's summary and meals) to the configured server. `API_BASE_URL=` on the command line leaves the address empty, so the test host makes no requests.
