import os
import tempfile
import time
from pathlib import Path

# Must be set before any app module is imported: database.py reads
# DATABASE_URL at import time, and the estimate route checks for a key.
os.environ["DATABASE_URL"] = "sqlite:///" + str(
    Path(tempfile.mkdtemp()) / "test.db"
)
os.environ["OPENAI_API_KEY"] = "test-key-not-used"

# Run the suite in UTC so "today" is the same date on the server clock
# and in stored UTC timestamps. Timezone tests override this.
os.environ["TZ"] = "UTC"
time.tzset()

import openai
import pytest
from fastapi.testclient import TestClient

import app as app_module
import routes.meals
import services.nutrition_ai
from database import Base, engine
from schemas import NutritionEstimate

FAKE_ESTIMATE = NutritionEstimate(
    meal_name="Chicken and rice",
    calories=650,
    protein_g=45.0,
    carbohydrates_g=70.0,
    fat_g=15.0,
    confidence=0.8,
    calorie_low=550,
    calorie_high=750,
    assumptions=["1 cup cooked rice"],
)


@pytest.fixture(autouse=True)
def fresh_database():
    if engine.url.render_as_string() != os.environ["DATABASE_URL"]:
        pytest.exit(
            f"Refusing to run: tests are pointed at {engine.url}, "
            "not the temporary test database. Is DATABASE_URL read in database.py?"
        )
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


class NoRealOpenAIClient:
    def __init__(self, *args, **kwargs):
        raise AssertionError("tests must not create a real OpenAI client")


@pytest.fixture(autouse=True)
def no_real_openai_client(monkeypatch):
    """Fail any test that would reach the real OpenAI API."""
    monkeypatch.setattr(openai, "OpenAI", NoRealOpenAIClient)
    services.nutrition_ai._client.cache_clear()
    yield
    services.nutrition_ai._client.cache_clear()


@pytest.fixture(autouse=True)
def fake_estimator(monkeypatch):
    """Replace the OpenAI call; records what the route passed in."""
    calls = []

    def estimate(message, image_bytes=None, image_content_type=None):
        calls.append(
            {
                "message": message,
                "image_bytes": image_bytes,
                "image_content_type": image_content_type,
            }
        )
        return FAKE_ESTIMATE

    monkeypatch.setattr(routes.meals, "estimate_nutrition", estimate)
    return calls


@pytest.fixture
def fake_estimate():
    return FAKE_ESTIMATE


@pytest.fixture
def client():
    with TestClient(app_module.app) as test_client:
        yield test_client


@pytest.fixture
def server_timezone():
    """Switch the process timezone for one test, then restore UTC."""

    def set_timezone(name):
        os.environ["TZ"] = name
        time.tzset()

    yield set_timezone
    os.environ["TZ"] = "UTC"
    time.tzset()
