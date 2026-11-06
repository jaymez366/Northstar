import logging

from fastapi import APIRouter, Depends, HTTPException, Response

from app.core.config import Settings, get_settings
from app.schemas.calls import IceServersResponse
from app.services.auth import VerifiedUser, require_user
from app.services.rate_limit import require_ice_server_rate_limit
from app.services.twilio_turn import TwilioTurnUnavailable, create_turn_configuration

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/calls")


@router.get("/ice-servers", response_model=IceServersResponse, response_model_exclude_none=True)
async def get_ice_servers(
    response: Response,
    _user: VerifiedUser = Depends(require_user),
    _rate_limit: None = Depends(require_ice_server_rate_limit),
    settings: Settings = Depends(get_settings),
) -> IceServersResponse:
    """Return fresh Twilio ICE servers to an authenticated Supabase user."""
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    try:
        return await create_turn_configuration(settings)
    except TwilioTurnUnavailable as exc:
        logger.warning("turn_credentials_unavailable", extra={"event": "turn_credentials_unavailable"})
        raise HTTPException(status_code=503, detail="Call connectivity credentials are temporarily unavailable") from exc
