"""Twilio Network Traversal Service token retrieval and response validation."""

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import urlsplit

import httpx

from app.core.config import Settings
from app.schemas.calls import IceServer, IceServersResponse

logger = logging.getLogger(__name__)
TWILIO_TOKEN_URL = "https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Tokens.json"
_SID_PATTERN = re.compile(r"^(?:AC|SK)[0-9a-fA-F]{32}$")
_MAX_USERNAME_LENGTH = 512
_MAX_CREDENTIAL_LENGTH = 4096


class TwilioTurnUnavailable(Exception):
    """Raised for unavailable configuration, provider failures, or bad data."""


def _validate_ice_url(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 2048:
        raise ValueError("invalid ICE URL")
    scheme, separator, address = value.partition(":")
    scheme = scheme.lower()
    if not separator or scheme not in {"stun", "stuns", "turn", "turns"}:
        raise ValueError("unsupported ICE URL scheme")
    if "@" in address or "#" in address:
        raise ValueError("invalid ICE URL authority")
    parsed = urlsplit(f"//{address}")
    host = (parsed.hostname or "").lower()
    expected_suffix = ".turn.twilio.com" if scheme in {"turn", "turns"} else ".stun.twilio.com"
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValueError("invalid ICE URL port") from exc
    if (
        not host.endswith(expected_suffix)
        or not host[: -len(expected_suffix)]
        or port is None
        or parsed.path
        or parsed.fragment
        or parsed.query not in {"", "transport=udp", "transport=tcp"}
    ):
        raise ValueError("ICE URL is not a valid Twilio server URI")
    return value


def _validate_provider_payload(
    payload: Any,
    expected_ttl: int,
    issued_at: datetime | None = None,
) -> IceServersResponse:
    if not isinstance(payload, dict):
        raise ValueError("response must be an object")

    username = payload.get("username")
    if (
        not isinstance(username, str)
        or not username.strip()
        or username != username.strip()
        or len(username) > _MAX_USERNAME_LENGTH
        or any(character.isspace() for character in username)
    ):
        raise ValueError("invalid token username")

    raw_ttl = payload.get("ttl")
    if isinstance(raw_ttl, bool) or not isinstance(raw_ttl, (str, int)):
        raise ValueError("invalid token TTL")
    try:
        returned_ttl = int(raw_ttl)
    except (TypeError, ValueError) as exc:
        raise ValueError("invalid token TTL") from exc
    if returned_ttl != expected_ttl:
        raise ValueError("returned token TTL does not match the request")

    raw_servers = payload.get("ice_servers")
    if not isinstance(raw_servers, list) or not raw_servers or len(raw_servers) > 32:
        raise ValueError("invalid ICE server list")

    ice_servers: list[IceServer] = []
    found_turn = False
    for raw_server in raw_servers:
        if not isinstance(raw_server, dict):
            raise ValueError("invalid ICE server entry")
        raw_urls = raw_server.get("urls")
        if isinstance(raw_urls, str):
            urls: str | list[str] = _validate_ice_url(raw_urls)
            normalized_urls = [urls]
        elif isinstance(raw_urls, list) and raw_urls and len(raw_urls) <= 16:
            normalized_urls = [_validate_ice_url(url) for url in raw_urls]
            urls = normalized_urls
        else:
            raise ValueError("invalid ICE server URLs")

        is_turn = any(urlsplit(url).scheme.lower() in {"turn", "turns"} for url in normalized_urls)
        server_username: str | None = None
        credential: str | None = None
        if is_turn:
            found_turn = True
            server_username = raw_server.get("username")
            credential = raw_server.get("credential")
            if server_username != username:
                raise ValueError("TURN server username does not match token username")
            if (
                not isinstance(credential, str)
                or not credential.strip()
                or len(credential) > _MAX_CREDENTIAL_LENGTH
            ):
                raise ValueError("invalid TURN credential")
        ice_servers.append(IceServer(urls=urls, username=server_username, credential=credential))

    if not found_turn:
        raise ValueError("response contains no TURN server")

    expires_at = (issued_at or datetime.now(timezone.utc)) + timedelta(seconds=returned_ttl)
    return IceServersResponse(ice_servers=ice_servers, expires_at=expires_at)


async def create_turn_configuration(settings: Settings) -> IceServersResponse:
    if not settings.twilio_account_sid or not settings.twilio_api_key or not settings.twilio_api_secret:
        raise TwilioTurnUnavailable("provider is not configured")
    api_key = settings.twilio_api_key.get_secret_value()
    api_secret = settings.twilio_api_secret.get_secret_value()
    if (
        not _SID_PATTERN.fullmatch(settings.twilio_account_sid)
        or not settings.twilio_account_sid.startswith("AC")
        or not _SID_PATTERN.fullmatch(api_key)
        or not api_key.startswith("SK")
        or not api_secret.strip()
    ):
        raise TwilioTurnUnavailable("provider configuration is invalid")

    endpoint = TWILIO_TOKEN_URL.format(account_sid=settings.twilio_account_sid)
    issued_at = datetime.now(timezone.utc)
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(5.0, connect=2.0),
            follow_redirects=False,
        ) as client:
            response = await client.post(
                endpoint,
                auth=(
                    api_key,
                    api_secret,
                ),
                data={"Ttl": settings.twilio_turn_ttl_seconds},
            )
        if not 200 <= response.status_code < 300:
            logger.warning("twilio_turn_provider_failure", extra={"event": "twilio_turn_provider_failure"})
            raise TwilioTurnUnavailable("provider request failed")
        try:
            payload = response.json()
            return _validate_provider_payload(payload, settings.twilio_turn_ttl_seconds, issued_at)
        except (ValueError, TypeError):
            logger.warning("twilio_turn_invalid_response", extra={"event": "twilio_turn_invalid_response"})
            raise TwilioTurnUnavailable("provider response was invalid") from None
    except httpx.HTTPError:
        logger.warning("twilio_turn_provider_unavailable", extra={"event": "twilio_turn_provider_unavailable"})
        raise TwilioTurnUnavailable("provider unavailable") from None
