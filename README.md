# MyNutritionPal

AI-powered calorie and nutrition tracker: a SwiftUI iOS app (`frontend/`) and a FastAPI backend (`backend/`).

## Backend

Requires Python 3.11.

```bash
cd backend
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env        # then set OPENAI_API_KEY in .env
python app.py               # serves on http://0.0.0.0:8000, API docs at /docs
```

Run the tests (from `backend/`, with the virtualenv active):

```bash
python -m pytest
```

Tests use a temporary database and a fake nutrition estimator. They never call OpenAI or touch `nutrition.db`.

### Configuration

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `OPENAI_API_KEY` | For meal estimates | none | OpenAI access. Put it in `backend/.env`. |
| `DATABASE_URL` | No | `sqlite:///./nutrition.db` | SQLAlchemy database URL. Set it in `backend/.env` or in the shell; a shell value wins. The default path is relative to the directory you start the server from. |

## iOS app

Open `frontend/MyNutritionPal/MyNutritionPal.xcodeproj` in Xcode (iOS 18.5+).

The backend address is currently hardcoded as `baseURL` in `frontend/MyNutritionPal/MyNutritionPal/NutritionAPI.swift`. Set it to `http://<your Mac's LAN IP>:8000`, and keep the phone and the Mac on the same network.
