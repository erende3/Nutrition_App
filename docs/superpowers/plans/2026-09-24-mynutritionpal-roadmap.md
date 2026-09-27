# MyNutritionPal Development Roadmap

**Date:** 2026-09-24
**Inputs:** the codebase onboarding report, the Graphify graph, source code, git history, and the product vision from 2026-09-24.
**Status:** Planning only. No application code has been changed.

## Guiding principles

- Stabilize before building. Every phase leaves the app working end to end.
- Build seams, not frameworks: one current-user dependency, one estimator boundary, one API client, one shared client store.
- The backend is the source of truth for meals and goals. Daily totals are **calculated when read**, never stored, so editing or deleting a meal updates totals for free.
- Meals auto-save after a successful estimate. There is no mandatory review step.

## Decisions that are cheap now and expensive later

| # | Decision | Recommended now | What it protects |
|---|---|---|---|
| 1 | What "a day" means | Store `eaten_at` (UTC, timezone-aware) plus `local_date` (the user's calendar date when the meal was logged, from the client's timezone). Query by `(user_id, local_date)`. | History calendar, daily totals, travel, HealthKit sample dates |
| 2 | Daily totals | SQL `SUM` when read; no stored daily-total table | Edits and deletes update totals automatically |
| 3 | Goals over time | A `daily_goals` table: `effective_date`, calories, nullable protein/carbs/fat targets, `source` (calculated / manual / healthkit) | Past days keep the goal they had; HealthKit adds rows; macro targets have a home |
| 4 | User identity | One `get_current_user` dependency. Every query is filtered by `user_id`. No user ids in URLs. | Adding auth means replacing one function |
| 5 | AI boundary | Keep three shapes separate: the LLM output schema, the stored meal, and the API response. Record provider, model and prompt version on every meal. The model name comes from config. | Swapping models, comparing accuracy, re-estimating meals |
| 6 | Raw AI output | Store the full estimate JSON (assumptions, per-item breakdown) in a JSON column beside the typed totals | Richer meal information later without a migration each time |
| 7 | Input channel | A `source` field on each meal: text / photo / voice. Voice follows voice input → transcription → the existing text path; the transcription technology is chosen in Phase 6. | Voice needs no new estimation endpoint |
| 8 | Units | Metric everywhere in the backend; convert only for display | HealthKit and locales |
| 9 | Migrations | Alembic from the first schema change; no SQLite-only features | Moving to Postgres for multi-user |
| 10 | API contract | Explicit response models, one error format, a `/v1` prefix before the first external build | Older app versions keep working |
| 11 | Client state | One shared `@Observable` store, injected through the environment. One `APIClient` with a configurable base URL and a place to add an auth header. | Edits show up on every screen; auth can be added later |

## Where the single-user assumption lives today

*Historical: this describes the code on 2026-09-24. Milestone 0.3 replaced the direct calls with `get_current_user`, and Milestone 0.4 replaced the server-local "today" with `local_date` and `X-Timezone`. The single user (id 1), the single goal column and SQLite remain.*

- `get_or_create_default_user(db)` is called directly in 8 route handlers: `routes/meals.py:51,121,144,165,188`, `routes/summary.py:64`, `routes/users.py:40,62`.
- User 1 is created implicitly (`dependencies.py:16-29`), and onboarding overwrites it.
- There is one goal column, `users.daily_calorie_goal`, with no history (`models.py:48`), read directly by `summary.py:39`.
- "Today" means the server's local date (`crud.py:37`, `summary.py:20`), while `created_at` is stored as naive UTC (`models.py:91`).
- iOS has no concept of identity: the `NutritionAPI` singleton has no auth header hook, and nothing is scoped to an account.
- A single SQLite file sits next to the code.
- Already correct: every function in `crud.py` takes a `user`, and `delete_meal` is scoped by `user_id`. Keep that pattern.

---

## Phase 0: Foundation (reproducible setup, safety net, cleanup)

**Accomplish**
- `backend/requirements.txt` with pinned versions (from the working Python 3.11 environment), `backend/.env.example`, and README run steps for the backend and the iOS app.
- `DATABASE_URL` and the OpenAI model name read from the environment, with today's values as defaults.
- A pytest harness: temporary SQLite database, `TestClient`, and a fake estimator (monkeypatched). Characterization tests for every endpoint. The confirmed timezone bug and negative-goal bug are pinned as `xfail` tests.
- Delete the debug prints (`app.py`, `routes/meals.py`, `NutritionAPI.swift`), the duplicate `include_router` calls, unused imports, the unused `todays_meals` in `clear_todays_meals`, `Item.swift` with the SwiftData container, and `OnboardingViewModel.onboardingComplete`.

**Why now:** every later phase needs a way to prove the core loop still works. Cleanup is cheapest while the code is small.

**Likely files:** `backend/app.py`, `database.py`, `routes/*.py`, new `backend/tests/`, new `backend/requirements.txt`, new `README.md`, `MyNutritionPalApp.swift`, `Item.swift`, `NutritionAPI.swift`, `OnboardingViewModel.swift`.

**Depends on:** nothing.

**Decisions:** Python version (3.11 is what's installed; 3.12+ is fine too). Plain pytest only; no extra test frameworks.

**Not yet:** any behavior change, schema change or refactor beyond deleting dead code.

**Done when:** a fresh clone runs by following the README; `pytest` passes, with the known bugs as `xfail`; no `print` calls remain in the backend; the iOS app builds and behaves the same as before.

## Milestone 0.3: backend/API architecture (added 2026-09-25)

A behavior-preserving milestone between Phase 0 and Phase 1. It finished the one remaining Phase 0 item and pulled forward the structural, no-user-visible-change parts of Phases 1 and 3, so the later phases build on clean seams. Plan: `docs/superpowers/plans/2026-09-25-milestone-0.3-backend-architecture.md`.

- **From Phase 0:** the OpenAI model name comes from the environment (`config.py`, `OPENAI_MODEL`).
- **From Phase 1, item 4:** the OpenAI client has an explicit timeout (60 s) and retry count (1), both configurable. The estimate and the meal save run off the event loop. The sync SDK stays, called through `run_in_threadpool`.
- **From Phase 1, item 5 (partly):** estimate failures are logged, and the client gets a generic message with 503 / 504 / 502 / 500. Exception text never reaches the client. The body is still `{"detail": str}`; the single error envelope with error codes stays in Phase 3.
- **From Phase 3:**
  - Pydantic response models on every route. `/meals/today` and `/meals/date` share `MealResponse`, which now includes confidence and the calorie range, and no `user_id`.
  - The `get_current_user` dependency, which all user-scoped routes use. It still returns user 1, and the first-user creation race is fixed.
  - The estimator boundary: typed estimator errors, with no SDK types leaking out of `services/nutrition_ai.py`.
- **New seams:** `services/meals.py` (estimate plus auto-save) and `services/summary.py` (daily totals).

**Still in Phase 1:** Alembic, `local_date` and timezone, calorie goal clamping, the upload size limit, and moving to an SQL day filter (`get_meals_by_date` still filters in Python).

**Still in Phase 3:** `/v1`, the day endpoint, the error envelope with codes, splitting the LLM schema from the API response, and AI metadata on meals.

## Milestone 0.4: backend correctness (added 2026-09-25)

This completes Phase 1 items 1–3. Plan: `docs/superpowers/plans/2026-09-25-milestone-0.4-backend-correctness.md`.

- **Item 1, migrations.** Alembic, with revisions `0001_baseline`, `0002_goal_positive_check` and `0003_meal_local_date`. `python app.py` migrates before serving and refuses to serve if migration fails. The development database was stamped at the baseline and migrated in place, with a backup.
- **Item 2, day handling.** Meals store `local_date`, backfilled from `created_at` in `DEFAULT_TIMEZONE`. "Today" uses the optional `X-Timezone` header or the server default, and day queries filter on `(user_id, local_date)` in SQL. `created_at` keeps its name and naive-UTC format.
- **Item 3, the goal invariant.** A stored goal is always positive: `CHECK (daily_calorie_goal > 0)`, a summary guard, and a fallback to the default 2200 with `goal_adjusted: true` when the formula gives 0 or less. **Nutrition-policy bounds (minimums, maximums, sex-specific floors) are deliberately not decided.** That's a product decision, to make at the latest before the Phase 5 goal and macro features.
- **Still open from Phase 1:** item 6, the upload size limit, which waits for Phase 2's image downscaling.
- **Moved to Phase 2:** iOS sending `X-Timezone`, and showing a notice when `goal_adjusted` is true.

## Milestone 0.5: iOS networking foundation (added 2026-09-25)

The first slice of Phase 2. Plan: `docs/superpowers/plans/2026-09-25-milestone-0.5-ios-networking.md`.

- **Base URL from the build configuration.** `API_BASE_URL` (Config/*.xcconfig, set per developer in the git-ignored `Config/Local.xcconfig`) → the `APIBaseURL` Info.plist key → `AppConfig`. The hardcoded IP is gone. The Mac's `.local` name survives network changes. Release has no URL until Phase 8.
- **ATS:** `NSAllowsLocalNetworking` replaces `NSAllowsArbitraryLoads`.
- **`APIClient`:** one request path for all six calls. It sends `X-Timezone` on every request, uses a 300 s timeout for estimates and 20 s otherwise, and never retries automatically.
- **`APIError`:** shows the backend's `detail`, a generic message for 422, and connection failures that name the server. Retry on the Root and History error screens; the Dashboard clears stale errors. *(Milestone 0.7 replaced this single Dashboard error, whose clearing could erase a photo error, with separate errors per operation.)*
- **Tests:** `URLProtocol`-stubbed client tests, config, error and decoding tests on iOS; the backend's error body shapes are pinned (`tests/test_error_contract.py`). No backend production change.
- **Kept on purpose:** the snake_case model structs and plain `JSONDecoder` (switching to `convertFromSnakeCase` would break the explicit `CodingKeys`).

**Still in Phase 2:** the image pipeline with `PhotosPicker` and the upload limit (Phase 1 item 6), planned as Milestone 0.6; the shared `NutritionStore`, full loading/empty states, the `goal_adjusted` notice and onboarding input ranges, planned as Milestone 0.7. *(0.7 made the existing ranges visible and consistent rather than tightening them.)*

## Milestone 0.6: photo pipeline (added 2026-09-25)

This completes Phase 1 item 6 and the photo part of Phase 2. Plan: `docs/superpowers/plans/2026-09-25-milestone-0.6-photo-pipeline.md`.

- **Client downscaling.** `MealPhoto` turns every picked photo into the upload JPEG: at most 1536 px on the long edge, upright, quality 0.7, with no source metadata (so no location). It runs in a background task right after the pick, so nothing is encoded on the main thread, and the Dashboard keeps only that JPEG and its preview. This size and quality policy is the client's contract; the app doesn't recompress to reach a byte target.
- **Photo sources.** Choose Photo (`PhotosPicker`) next to Take Photo. Take Photo appears only when the camera source is available. (The iOS 18.6 simulator provides a simulated camera, so there it's shown.)
- **Upload limit.** `MAX_IMAGE_BYTES` (default 10 MiB): the route reads at most one byte past it and returns 413 above it. Uploads must also start with the signature of their declared type (JPEG, PNG or WebP), or they get a 400. Nothing is estimated or saved in either case. The HTTP layer still accepts any body size; a request-size cap belongs to the production deployment (Phase 8).
- **No schema or response-shape change.** Meal `source` and the image reference stay in Phase 3.
- **Deferred to 0.7:** automatic recovery after a network change (the 0.5 observation). 0.6's device acceptance records whether History's Retry recovers without a relaunch. *(It did. 0.7 found the cause was the Dashboard's missing refresh triggers, not the networking layer.)*

## Milestone 0.7: iOS client state (added 2026-09-26)

This completes Phase 2. Plan: `docs/superpowers/plans/2026-09-26-milestone-0.7-client-state.md`. No backend change, no migration, no API change.

- **Diagnosis.** The Dashboard loaded once. It had no Retry, no pull-to-refresh and no refresh on returning to the app, and it showed placeholder numbers (2200 / 0) as if they were data. `APIClient`, `URLSession` and the `.local` address hold no state that goes stale across a network change: in 0.6, a fresh request recovered at once.
- **`NutritionStore`** (`@Observable`, owned by the app root): today's summary and meals only, loaded together and applied together. Concurrent refreshes share one request, and a failed refresh keeps the old data. Logging or deleting a meal fetches fresh data after any older refresh, whose result is dropped. The profile, forms, photos and each operation's own error stay in their views.
- **Refresh triggers:** first appearance, the app becoming active (`scenePhase`), pull-to-refresh on both screens, Retry, and after log and delete. There's no connectivity monitoring and no automatic retry.
- **Honest states:** dashes before the first load; data stays on screen while refreshing and after a failure, with a banner and Retry; History keeps its list while refreshing. Separate load, estimate, photo and delete errors (0.6 review #8). Cancelled requests are never shown as errors (0.5 review M4).
- **Photos:** `PhotoDraft` adds Cancel to "Preparing photo…" (0.6 review #3); the newest pick still wins.
- **Onboarding:** `goal_adjusted` is decoded and explained on the results step, using the returned goal, and BMR/Maintenance are hidden when adjusted or not positive. The existing input ranges are kept in one place, and an invalid weight is explained and blocks Continue instead of being clamped silently. Unit-conversion tests added.
- **Still open, a product decision:** nutrition-policy goal bounds. The app's accepted inputs can still produce positive goals as low as 1 kcal (a 0.7 planning sweep found about 658,000 input combinations under 1000 kcal). This must be decided before the Phase 5 goal and macro features.

## Milestone 0.8: meal provenance and goal history (added 2026-09-26)

The first half of Phase 3: the backend data model. Plan: `docs/superpowers/plans/2026-09-26-milestone-0.8-data-model.md`. No API response-shape change and no iOS change.

- **Phase 3 is split in two.** 0.8 is the data model (this section). **Milestone 0.9 is the API contract v1:** `/v1`, the error envelope with codes, `GET /v1/days/{date}`, the estimate returning the saved meal, the new meal fields in responses, and the iOS switch-over.
- **Estimator provenance.** `estimate_nutrition` returns an `EstimateResult`: the estimate plus the provider, the model asked (read from config at call time) and `PROMPT_VERSION`. A test pins the prompt text and output schema to the version.
- **Meal provenance** (migration `0004`): nullable `source` (`text` / `photo`, from whether an image was sent), `description` (the submitted text, as received), `ai_provider`, `ai_model`, `prompt_version`, and `ai_payload` (the model's full estimate, including assumptions; never the image). Meals logged earlier keep NULL: unknown, not guessed. The stored meal now records its provenance and the full model output separately from the API response; the API response itself is split from the LLM schema in 0.9.
- **Goal history** (migrations `0005`, `0006`): `daily_goals` (`effective_date`, `calories` with `CHECK > 0`, `source`, one row per user per day). The existing goal was copied exactly with source `migrated`, effective from the user's earliest meal date. Onboarding writes a `calculated` or `default` row (the `goal_adjusted` case, now stored) for the user's today (`X-Timezone`); the same day replaces. A day's summary uses the latest goal on or before it; the profile shows the most recent. `users.daily_calorie_goal` is dropped. `GoalSource` and `MealSource` are the one definition of the source values, enforced by model validators; the columns stay plain strings.
- **Deferred:** the image reference (to the storage phase) and `edited_at` (Phase 5), macro target columns (Phase 5), and exposing any of this in the API (0.9).
- **Still open, a product decision required before Phase 5:** nutrition-policy goal bounds (goals down to 1 kcal are still possible). Onboarding input ranges are unchanged.

## Milestone 0.9: API contract v1 (added 2026-09-27)

The second half of Phase 3. Plan: `docs/superpowers/plans/2026-09-27-milestone-0.9-api-contract.md`. No schema change or migration (head stays `0006`).

- **`/v1`** is a separate FastAPI app mounted at `/v1`, with its own schema (`/v1/openapi.json`). The unversioned routes are frozen and unchanged for app builds that still use them; their removal is a later milestone.
- **Error envelope:** `{"error": {"code", "message"}}`, with `fields` for `validation_failed` (never echoing input); stable codes for every failure; unexpected errors are JSON. `ApiError` (an `HTTPException` with a code) keeps the unversioned `{"detail"}` bodies byte-identical.
- **`GET /v1/days/{date}`** replaces the today/date/summary read model: the meals stored on that local date, calorie and macro totals, the goal in effect (`{"calories"}` only: the goal's source stays internal), and `calories_remaining` / `percentage` from the same code as `/summary/daily`. The date is never converted.
- **Meals:** `POST /v1/meals/estimate` returns 201 and the saved meal (the API response is now separate from the LLM schema); `DELETE /v1/meals/{id}` returns 204. Public meal fields add `assumptions`, `source`, `description` and `local_date`; `created_at` is UTC with `Z`, to the second. The AI provider, model, prompt version and raw output stay internal. A photo meal may have no text: its description is NULL, and the estimator gets the old placeholder, so `PROMPT_VERSION` is unchanged.
- **iOS** switches to `/v1`: one day request per refresh, the envelope's message in errors, and no placeholder text for photo-only meals.
- **Deferred:** a public goal-history endpoint and the goal's source (until manual or macro goals make them useful), typed profile enums in OpenAPI, documenting error responses in OpenAPI, date ranges for a calendar, removing the unversioned routes.

## Milestone 0.10: design system foundation (added 2026-09-27)

The first part of Phase 4. Plan: `docs/superpowers/plans/2026-09-27-milestone-0.10-design-foundation.md`. iOS only, apart from one dev-server fix. No API, schema or data change.

- **Direction** ("calm, native, legible"), approved from a mockup: SF Pro on Dynamic Type, one emerald accent, flat cards (a hairline border in light only), radii 12 (controls) and 16 (cards), rounded numbers. UI UX Pro Max was an input; its web fonts, landing-page pattern and a low-contrast pairing were rejected.
- **Light and dark** follow the system. Before, only the Dashboard was forced dark, so a light-mode phone showed a dark Dashboard and a light History.
- **Tokens** are named color sets in the asset catalog, each with light and dark values, and every text pair meets WCAG AA. Shared components only where the screens reuse them: a card surface, a primary button and an inline error.
- **Screens restyled** with their behavior unchanged: the Dashboard, History (calories at the trailing edge; macros on one line), onboarding (the goal-adjusted notice as an info callout, with the same wording) and the root screen.
- **Accessibility:** Dynamic Type everywhere (the stat cards and meal rows stack at accessibility sizes), VoiceOver phrases for the ring, stat cards and meals, decorative icons hidden, Reduce Motion for the ring, 44 pt minimum tap targets.
- **Dev server:** `python app.py` now starts from a git worktree that has no `backend/.venv`.
- **Deferred:** Phase 5 screen designs (calendar History, meal detail and edit, Settings) and the navigation structure; macro display. From 0.9, the placeholder description ("Estimate this meal from the image.") that older photo meals may carry in `/v1` responses. The real database has none today, and only a pre-0.9 app build using the unversioned estimate route can create one. It gets fixed when those routes are removed or when a meal's description is first shown (Phase 5), whichever comes first, by mapping it at read time; stored meals are never rewritten.

## Phase 1: Backend correctness

**Accomplish**
1. An Alembic baseline migration of the current schema.
2. Day handling: ~~`eaten_at` (UTC, timezone-aware)~~ plus `local_date`. *Superseded in part by Milestone 0.4, D6: `created_at` (naive UTC) was kept and `local_date` added; `eaten_at` is deferred to Phase 5, when meals become editable.* The client sends its IANA timezone in an `X-Timezone` header; if it's missing, fall back to the server's timezone. Filter in SQL by `(user_id, local_date)`. One shared day-query function replaces the three copies.
3. Calorie goal safeguards, applied at every layer:
   - ~~realistic input ranges in `UserOnboardingRequest`;~~ *Deferred by Milestone 0.4, D9: the request limits are unchanged.*
   - ~~a pure function that calculates the goal, then clamps it between a floor and a ceiling and reports when it did;~~ *Superseded by Milestone 0.4, D4 (option B): a goal of 0 or below falls back to the default 2200 and `goal_adjusted: true` reports it; positive goals are kept. Nutrition-policy floors and ceilings are a separate, undecided product decision.*
   - a database `CHECK (daily_calorie_goal > 0)`;
   - a zero-goal guard in the summary anyway.
4. A non-blocking estimate endpoint: change the route to a plain `def` so FastAPI runs it in a thread pool (the smallest fix; `AsyncOpenAI` also works). Give the OpenAI client an explicit timeout and a small retry count.
5. Consistent errors: log exceptions on the server and return a generic message with an error code. *Done in Milestone 0.3 except the error codes, which moved to the Phase 3 error envelope.* OpenAI timeout → 504; bad input → 400 or 422. Exception text never goes to the client.
6. An upload limit: reject images over roughly 10 MB. *Done in Milestone 0.6: `MAX_IMAGE_BYTES`, 10 MiB by default, returns 413.*

**Why now:** the confirmed bugs break the core promise that a meal counts toward the right day. History and macros must not be built on wrong dates.

**Likely files:** `models.py`, `crud.py`, `schemas.py`, `routes/meals.py`, `routes/summary.py`, `services/calorie_goal.py`, `services/nutrition_ai.py`, new `backend/alembic/`.

**Depends on:** Phase 0 tests.

**Decisions:** whether the timezone travels in a header or in the request body (header recommended).

**Decided (2026-09-24), with later changes marked.** Milestone 0.4 revised some of these on 2026-09-25 (plan: `docs/superpowers/plans/2026-09-25-milestone-0.4-backend-correctness.md`):
- ~~Development data in `nutrition.db` is wiped; no backfill logic.~~ *Superseded by 0.4, D2: the development database was migrated in place, with a backup, and existing meals' `local_date` was backfilled.*
- ~~The Alembic baseline starts from a fresh database.~~ *Superseded by 0.4, D2: the baseline revision reproduces the existing schema, and existing databases are stamped at it.*
- An invalid calculated goal is **replaced and the user is notified**; onboarding is not rejected. *As implemented in 0.4, D4: "replaced" means a goal of 0 or below becomes the default 2200, and the response carries `goal_adjusted: true`. Positive goals are not clamped. The iOS notice comes in Phase 2.*
- ~~Safety bounds live in one settings object that can be changed through the environment, not scattered constants.~~ *Superseded by 0.4, D4: no goal bounds exist yet. When a nutrition policy is decided, its bounds should be configurable settings.*
- Production thresholds are decided separately; 1200 / 1500 kcal are placeholders only. *Still open: nutrition-policy bounds are deferred, to be decided at the latest before the Phase 5 goal and macro features.*
- Zero, negative or clearly invalid goals must be impossible to store or serve. *Done in 0.4 for zero and negative goals: the `CHECK` constraint, the fallback and the summary guard. "Clearly invalid" positive goals (e.g. 154 kcal) are left to the nutrition policy.* *(Milestone 0.7 planning found that the app's own input ranges can give goals as low as 1 kcal; still undecided.)*

**Not yet:** the goals table (Phase 3), macro targets, auth, new endpoints.

**Done when:**
- The Phase 0 `xfail` tests pass.
- A meal logged at 23:30 local time counts toward that local day.
- No accepted input produces a goal ≤ 0; a sweep test covers the full input ranges.
- `/summary/daily` responds while a slow fake estimate is still running.
- No 500 response contains exception text.

## Phase 2: iOS stabilization

**Accomplish**
- The base URL comes from the build configuration (xcconfig → Info.plist key): Debug uses ~~your LAN IP~~ the Mac's `.local` name from `Config/Local.xcconfig` (Milestone 0.5); Release uses the production URL, empty until Phase 8. Arbitrary HTTP loads are allowed only for local-network development.
- Remove `forceOnboarding`. ~~Keep your testing workflow with a Debug-only launch argument (e.g. `-resetOnboarding`).~~ *Removed in `10b7a8d`. The launch argument was superseded: onboarding state lives on the server (`onboarding_complete`), so a client flag can't reset it; re-onboarding needs a fresh database.*
- An `APIClient` with:
  - one request function;
  - ~~a shared decoder using `.convertFromSnakeCase`, with models renamed to camelCase;~~ *Superseded by Milestone 0.5, D7: the models keep snake_case names or explicit `CodingKeys`; renaming waits for the Phase 3 model changes.*
  - a typed `APIError` that shows the backend's error message;
  - the `X-Timezone` header on every request.
- An image pipeline: downscale to about 1024–1536 px on the long edge, JPEG at about 0.7 quality, off the main thread. Check the camera is available, and offer `PhotosPicker` as a fallback or alternative. *Done in Milestone 0.6 (1536 px, 0.7).*
- Loading, error and empty states with a retry button on the Root, Dashboard and History screens. Clear stale errors after a successful refresh. *Done in Milestone 0.7, with errors kept separate per operation.*
- A shared `@Observable` `NutritionStore` (today's summary and meals), so the Dashboard and History read the same state. *Done in Milestone 0.7.*
- Tests: decoding tests against fixture JSON, `APIClient` tests with a stubbed `URLProtocol`, and onboarding unit-conversion tests. *Done across Milestones 0.5–0.7.*

**Why now:** once the backend is correct, the client has to stop hiding errors and start sending its timezone. Configuration is also a precondition for anyone else running the app.

**Likely files:** `NutritionAPI.swift` (→ `APIClient`), `RootView.swift`, `ContentView.swift`, `MealHistoryView.swift`, `CameraPicker.swift`, `OnboardingViewModel.swift`, the model structs, `Info.plist`, `project.pbxproj` / new `.xcconfig` files, the test targets.

**Depends on:** Phase 1 for the timezone header and error format. The base-URL and `forceOnboarding` work can run alongside Phase 1.

**Decisions:** a single shared store (recommended) vs each view fetching its own data. The minimum iOS version stays at 18.5 unless voice (Phase 6) needs more.

**Not yet:** visual redesign, the history calendar, meal editing, voice.

**Done when:**
- A fresh install onboards once, and relaunching goes straight to the Dashboard.
- Backend error messages appear to the user in plain language.
- A 12 MP photo uploads at under about 500 KB. *0.6 checks this empirically on the device; the contract is the 1536 px / 0.7 policy, not a byte size.*
- The app runs on a simulator with no camera. *The iOS 18.6 simulator provides a simulated camera; 0.6 hides Take Photo whenever the camera source is unavailable.*
- The Xcode tests pass.

## Phase 3: Data model and API contract for growth

**Accomplish**
- A `get_current_user` dependency replaces all 8 direct calls (it still returns user 1). Audit that every query is filtered by user. *Done in Milestone 0.3.*
- Pydantic response models for every route, one error format, and the `/v1` prefix. *Response models done in Milestone 0.3; the error format and `/v1` done in Milestone 0.9.*
- New meal fields:
  - `source` (text / photo / voice); *done in Milestone 0.8 for text and photo; voice comes with Phase 6;*
  - `description` (the user's own text); *done in 0.8;*
  - `ai_provider`, `ai_model`, `prompt_version`; *done in 0.8;*
  - `ai_payload` (a JSON column with assumptions and per-item breakdown); *done in 0.8 (the model's full estimate);*
  - `edited_at`. *Deferred to Phase 5, with meal editing (0.8, D2).*
  - Confidence and calorie range are exposed in the API. *Done in Milestone 0.3 (`MealResponse`).*
- A `daily_goals` table. Onboarding writes a row. The summary for date D uses the latest row whose `effective_date` is on or before D. Migrate `users.daily_calorie_goal` into it, then remove the column. *Done in Milestone 0.8 (without macro target columns, which come with Phase 5).*
- A day endpoint, `GET /v1/days/{date}`, returning that day's meals, calorie and macro totals, and goal. It replaces the today-only endpoints. *Done in Milestone 0.9 (calorie and macro totals and the goal; macro targets come with Phase 5).*
- An estimator boundary: `estimate_nutrition(input) -> EstimateResult`, with one provider adapter module and the model chosen by config. The LLM schema is separate from the API schema. *`EstimateResult` done in Milestone 0.8, and stored meals keep the full model output (`ai_payload`); the API response was separated from the LLM schema in 0.9.*

**Why now:** editing, history and macros all build on this contract. Changing it after the UI depends on it would double the work.

**Likely files:** `models.py`, `schemas.py` (possibly split into request/response modules), `crud.py`, `dependencies.py`, `routes/*`, `services/nutrition_ai.py`, Alembic migrations, the iOS models and `APIClient`.

**Depends on:** Phases 1–2.

**Decisions:** the shape of the day endpoint; a goals table (recommended) vs columns on `users`; keeping integer ids (fine, since queries are always filtered by user).

**Decided (2026-09-24):**
- Meal photos will be kept long term, for thumbnails and re-estimation.
- Phase 3 adds only a nullable image reference on the meal (a storage key, not a URL or blob), so storage can be plugged in later. *Milestone 0.8, D2: deferred to the storage phase, since the column would stay empty until then; adding it is a small additive migration.*
- No production image storage until the production-backend phase, where the object-storage choice is made.

**Not yet:** authentication, Postgres, HealthKit, macro-target calculation, AI evaluation.

**Done when:**
- OpenAPI shows typed responses for every route.
- A test shows that changing the goal today leaves yesterday's summary unchanged. *Done in Milestone 0.8 (`test_changing_the_goal_today_leaves_yesterday_unchanged`).*
- Changing the model through the environment needs no code change.
- Every data access goes through `get_current_user`.

## Phase 4: Design system foundation (UI UX Pro Max)

**Accomplish**
- Use UI UX Pro Max to set a visual direction.
- Design tokens: color for light and dark mode, a type scale that supports Dynamic Type, spacing and corner radii.
- Core SwiftUI components: card, primary button, calorie ring, macro bar, meal row, and empty / error / loading states.
- Screen designs for the logging flow, Dashboard, History calendar, meal detail and edit, and Settings.
- An accessibility baseline: VoiceOver labels, contrast, Dynamic Type.

**Why now:** the Phase 5 screens get designed before they're built, which avoids rework. Stabilization is done, so this styles a working app.

**Likely files:** a new `DesignSystem/` folder; `ContentView.swift` split into per-screen files; the asset catalog.

**Depends on:** Phase 2 (stable views) and Phase 3 (macros and confidence available to design around).

**Decisions:** ~~support light mode or keep dark only (the app is currently forced dark)~~ *decided in 0.10: light and dark, following the system;* navigation structure, e.g. Today / History / Settings tabs, with logging as the main action.

**Not yet:** building the new features, or animation polish beyond the core components.

**Done when:** every component has a SwiftUI preview; existing screens use the components; the existing screens pass an accessibility check. *Milestone 0.10 did the tokens, the shared components and the restyle of the existing screens, with the accessibility baseline. The screen designs for the Phase 5 screens remain.*

## Phase 5: Core tracking features

**Accomplish**
- Meal edit (`PATCH /v1/meals/{id}` for name, calories, macros, date and time) and delete for any day. Totals update because they're calculated when read.
- History: a calendar or date navigator showing each day's meals and totals, with edit and delete.
- Dashboard: macro totals and progress against targets.
- Macro targets: a default split derived from the calorie goal and stored in the goal row.
- Settings: editing the profile adds a recalculated goal row effective from today; a manual goal override is stored with `source=manual`.
- Meal detail: confidence range and assumptions.

**Why now:** these are the core product features, now resting on a correct contract and a design system.

**Likely files:** `routes/meals.py`, a new day route module, `crud.py`, `services/calorie_goal.py` (macro split); iOS History, Dashboard, new MealDetail and Settings views, `NutritionStore`.

**Depends on:** Phases 3 and 4.

**Decisions:** how editing works (typing new numbers, re-estimating from corrected text, or both); how macro targets are calculated; whether editing calories rescales the macros.

**Not yet:** voice, HealthKit, accounts, offline mode.

**Done when:**
- Editing a past meal changes only that day's totals.
- History can reach any past date.
- A profile edit changes the goal from today onward and leaves earlier days alone.
- Every new endpoint and store action has tests.

## Phase 6: Voice logging

**Accomplish:** voice input → transcription → the existing text estimation path, saved with `source=voice`. The transcript lands in the text field. Handle microphone permission (and speech permission if relevant), falling back to text if denied.

**Why now:** once the logging flow and design exist, this is small, and it needs no backend change.

**Likely files:** new voice input view and model, the logging UI, Info.plist usage strings.

**Depends on:** Phase 3 (the `source` field) and Phases 4–5 (the logging UI).

**Decisions:** the transcription technology is **not committed** (Apple on-device, a server-side model, or another provider are all open) and will be evaluated in this phase. Also: submit when the user stops speaking, or let them edit the transcript first. The meal still auto-saves once submitted.

**Not yet:** sending audio to the backend, multilingual tuning.

**Done when:** speaking a meal saves it with `source=voice`; denying permission leaves a working text path.

## Phase 7: AI quality and model evaluation (can run in parallel after Phase 3)

**Accomplish**
- An evaluation set of about 30–50 meals (text and photos) with reference nutrition from USDA data or food labels.
- A script that reports, per model and prompt version:
  - mean calorie and macro error;
  - how often the true value falls inside the predicted range;
  - latency;
  - cost.
- Prompt improvements such as per-item breakdowns and explicit portion assumptions.

**Why now:** it's only meaningful once the estimator boundary and per-meal metadata exist; before that, tuning is guesswork.

**Likely files:** `services/nutrition_ai.py` and its adapters, new `backend/evals/`.

**Depends on:** Phase 3.

**Decisions:** the reference data source, acceptable error targets, and which models to compare.

**Not yet:** fine-tuning, building a food database, combining several models.

**Done when:** one command produces a comparison report, and changing the default model is a config change backed by evaluation numbers.

## Phase 8: Accounts, auth and production backend

**Accomplish**
- Accounts with Sign in with Apple (the natural fit for an iOS-first app). The backend verifies Apple's identity token and issues its own session token, which `get_current_user` reads.
- Data-isolation tests: user A can never read, edit or delete user B's data.
- Migrate the existing data into the first account.
- Postgres, and a hosted deployment with HTTPS.
- Secrets management, per-user rate limits on estimates, and request size limits.
- Account deletion (an App Store requirement) and data export.

**Why now:** it must happen before anyone else uses the app. The Phase 3 seams make it an addition rather than a rewrite. **Decided (2026-09-24):** no outside testers yet; this phase stays after the core tracking features.

**Likely files:** `dependencies.py`, a new auth route module, `models.py` (`apple_sub`, email), config, deployment files; on iOS, the sign-in flow, Keychain token storage, and the `APIClient` auth header.

**Depends on:** Phase 3 (current-user seam) and Phase 1 (migrations).

**Decisions:** auth providers, hosting, Postgres provider, token strategy.

**Not yet:** social features, a web client, admin tools.

**Done when:**
- Two test accounts are fully isolated, proven by automated tests.
- Release builds talk to an HTTPS backend with no arbitrary-HTTP exception.
- Account deletion works.

## Phase 9: HealthKit

**Accomplish**
- Read access (with permission) to active energy and body mass; optionally write dietary energy and macros to Health.
- A dynamic goal calculation that writes goal rows with `source=healthkit`.
- A user setting to turn it on or off.

**Why now:** it needs goal history (Phase 3), Settings (Phase 5), and, if any Health data reaches the server, accounts and a privacy policy (Phase 8).

**Likely files:** a new iOS HealthKit service, the goals endpoint, `services/calorie_goal.py`.

**Depends on:** Phases 3, 5 and 8.

**Decisions:** where the dynamic goal is calculated (recommended: on the device, sending only the derived daily numbers); whether meals are written to Health; the adjustment algorithm.

**Not yet:** Google Fit or wearable integrations.

**Done when:** with permission, today's goal reflects activity; without it, the app behaves as before; App Store HealthKit requirements are met.

## Phase 10: Release polish and operations

**Accomplish**
- A UX polish pass with UI UX Pro Max: motion, haptics, onboarding copy.
- Crash reporting and privacy-respecting analytics.
- Monitoring of estimate latency and errors, and database backups.
- A privacy policy and App Store assets.
- Optionally, logging that queues while offline.

This phase can be folded into Phase 8 if you release early.

---

## Immediate next step

*Historical: this was the first step on 2026-09-24. The milestone sections above (0.3 onward) record the current position.*

**Phase 0**, starting with **Milestone 0.1: backend safety net**:

- `backend/requirements.txt` (pinned), `backend/.env.example`, and a README section on running the backend.
- `database.py` reads `DATABASE_URL`; the default stays `sqlite:///./nutrition.db`.
- `backend/tests/conftest.py`: a temporary SQLite database, `TestClient`, and a fake estimator.
- Tests:
  - the default profile;
  - onboarding with known numbers: 30-year-old male, 175 cm, 70 kg, moderately active, maintain → BMR 1649, TDEE 2556, goal 2556;
  - estimating saves the meal and the summary counts it;
  - delete; delete of a missing meal returns 404;
  - an unsupported image type returns 400;
  - `xfail`: a meal logged in the late local evening shows up in today's totals;
  - `xfail`: no accepted onboarding input produces a goal ≤ 0.
- **Done when:** `pytest` shows everything passing except the 2 expected failures, and nothing else in the app has changed.

A detailed TDD task plan for Milestone 0.1 will be written separately using the writing-plans format.
