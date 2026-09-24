print("1 - starting app.py")
from dotenv import load_dotenv
print("2 - dotenv imported")
from fastapi import FastAPI
print("3 - fastapi imported")


from database import Base, engine
print("4 - database imported")

print("5a - importing meals")
from routes import meals
print("5b - meals imported")

print("5c - importing summary")
from routes import summary
print("5d - summary imported")

print("5e - importing users")
from routes import users
print("5f - users imported")

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