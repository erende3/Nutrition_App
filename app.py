from dotenv import load_dotenv
from fastapi import FastAPI

from database import Base, engine
from routes import meals, summary, users

load_dotenv()

app = FastAPI(
    title="AI Nutrition Estimator",
    description="Estimate meal calories and macronutrients from text and images.",
)
app.include_router(meals.router)
app.include_router(summary.router)
app.include_router(users.router)


Base.metadata.create_all(bind=engine)

app.include_router(summary.router)
app.include_router(meals.router)



@app.get("/")
def home() -> dict[str, str]:
    return {
        "message": "Nutrition estimator is running.",
        "documentation": "/docs",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )