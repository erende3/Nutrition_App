from dotenv import load_dotenv

# Load .env before importing modules that read configuration at import time
# (database.py reads DATABASE_URL). Existing environment variables win.
load_dotenv()

from fastapi import FastAPI

import api_v1
from routes import meals
from routes import summary
from routes import users
from schemas import HomeResponse

app = FastAPI(
    title="AI Nutrition Estimator",
    description="Estimate meal calories and macronutrients from text and images.",
)
# The unversioned routes are frozen for the app builds that still use them.
app.include_router(meals.router)
app.include_router(summary.router)
app.include_router(users.router)
app.mount("/v1", api_v1.app)


@app.get("/")
def home() -> HomeResponse:
    return HomeResponse(
        message="Nutrition estimator is running.",
        documentation="/docs",
    )


def main() -> None:
    """Migrate the database to the latest revision, then serve.

    If the migration fails, exit non-zero without starting the server, so it
    never serves against an outdated or partly migrated schema.
    """

    import sys
    import traceback
    from pathlib import Path

    import uvicorn

    import db_migrations

    try:
        db_migrations.upgrade_to_head()
    except Exception as exc:
        traceback.print_exc()
        print(
            f"\nDatabase migration failed: {exc}\nThe server was not started.",
            file=sys.stderr,
        )
        raise SystemExit(1) from exc

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        # Must be absolute: uvicorn matches excluded directories against
        # absolute paths. Needs watchfiles (requirements-dev.txt).
        reload_excludes=[str(Path(__file__).resolve().parent / ".venv")],
    )


if __name__ == "__main__":
    main()
