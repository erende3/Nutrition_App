from dotenv import load_dotenv

# Load .env before importing modules that read configuration at import time
# (database.py reads DATABASE_URL). Existing environment variables win.
load_dotenv()

from fastapi import FastAPI

from database import Base, engine
from routes import meals
from routes import summary
from routes import users
from schemas import HomeResponse

app = FastAPI(
    title="AI Nutrition Estimator",
    description="Estimate meal calories and macronutrients from text and images.",
)
app.include_router(meals.router)
app.include_router(summary.router)
app.include_router(users.router)


Base.metadata.create_all(bind=engine)


@app.get("/")
def home() -> HomeResponse:
    return HomeResponse(
        message="Nutrition estimator is running.",
        documentation="/docs",
    )


if __name__ == "__main__":
    from pathlib import Path

    import uvicorn

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        # Must be absolute: uvicorn matches excluded directories against
        # absolute paths. Needs watchfiles (requirements-dev.txt).
        reload_excludes=[str(Path(__file__).resolve().parent / ".venv")],
    )
