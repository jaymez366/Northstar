from collections.abc import Mapping
from dataclasses import dataclass, field
from functools import lru_cache
import logging
from typing import Any

import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.core.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)
logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class VerifiedUser:
    """A token and claims produced only after successful JWT verification."""

    access_token: str = field(repr=False)
    claims: Mapping[str, Any]


@lru_cache
def _jwks_client(jwks_url: str) -> PyJWKClient:
    return PyJWKClient(jwks_url, cache_jwk_set=True, lifespan=300)


def verify_supabase_token(token: str, settings: Settings) -> dict[str, Any]:
    signing_key = _jwks_client(str(settings.jwt_jwks_url)).get_signing_key_from_jwt(token)
    return jwt.decode(
        token,
        signing_key.key,
        algorithms=settings.jwt_algorithms,
        audience=settings.jwt_audience,
        issuer=str(settings.jwt_issuer),
        options={"require": ["exp", "iat", "sub", "iss", "aud"]},
    )


def require_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    settings: Settings = Depends(get_settings),
) -> VerifiedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        logger.warning("authentication_failed", extra={"event": "authentication_failed"})
        raise HTTPException(status_code=401, detail="Bearer token required", headers={"WWW-Authenticate": "Bearer"})
    try:
        claims = verify_supabase_token(credentials.credentials, settings)
        return VerifiedUser(access_token=credentials.credentials, claims=claims)
    except Exception as exc:
        logger.warning("authentication_failed", extra={"event": "authentication_failed"})
        raise HTTPException(status_code=401, detail="Invalid or expired access token", headers={"WWW-Authenticate": "Bearer"}) from exc
