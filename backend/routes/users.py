from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from dependencies import get_current_user, get_db
from models import User
from services.calorie_goal import calculate_daily_calorie_goal
from crud import (
    get_user_profile,
    update_user_from_onboarding,
)
from schemas import (
    UserOnboardingRequest,
    UserOnboardingResponse,
    UserProfileResponse,
)

router = APIRouter(
    prefix="/users",
    tags=["users"],
)


@router.post(
    "/onboarding",
    response_model=UserOnboardingResponse,
)
def onboard_user(
    data: UserOnboardingRequest,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
) -> UserOnboardingResponse:

    result = calculate_daily_calorie_goal(
        sex=data.sex,
        age=data.age,
        weight_kg=data.weight_kg,
        height_cm=data.height_cm,
        activity_level=data.activity_level,
        goal=data.goal,
    )

    update_user_from_onboarding(
        db=db,
        user=user,
        data=data,
        daily_calorie_goal=result["daily_calorie_goal"],
    )

    return UserOnboardingResponse(
        bmr=result["bmr"],
        tdee=result["tdee"],
        daily_calorie_goal=result["daily_calorie_goal"],
    )

@router.get(
    "/profile",
    response_model=UserProfileResponse,
)
def user_profile(
    user: User = Depends(get_current_user),
) -> UserProfileResponse:
    profile = get_user_profile(user)

    return UserProfileResponse(**profile)