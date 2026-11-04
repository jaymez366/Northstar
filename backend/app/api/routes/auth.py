from fastapi import APIRouter, Depends

from app.schemas.auth import CurrentUserResponse
from app.services.auth import VerifiedUser, require_user

router = APIRouter(prefix="/auth")


@router.get("/me", response_model=CurrentUserResponse)
def current_user(user: VerifiedUser = Depends(require_user)) -> CurrentUserResponse:
    """Return the subject from a JWT after Supabase signature and claim checks."""
    return CurrentUserResponse(user_id=str(user.claims["sub"]))
