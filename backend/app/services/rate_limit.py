"""Shared Redis-backed limits for the authenticated ICE-server endpoint."""

from __future__ import annotations

import hashlib
import logging
from typing import Protocol
from uuid import uuid4

from fastapi import Depends, HTTPException, Request

from app.core.config import Settings
from app.services.auth import VerifiedUser, require_user

logger = logging.getLogger(__name__)

# One Redis script enforces both rolling-window limits atomically. Redis TIME
# makes decisions independent of worker clocks; sorted sets retain at most the
# configured request count per window and expire automatically.
_RATE_LIMIT_SCRIPT = """
local window_ms = tonumber(ARGV[1])
local user_limit = tonumber(ARGV[2])
local global_limit = tonumber(ARGV[3])
local clock = redis.call('TIME')
local now_ms = tonumber(clock[1]) * 1000 + math.floor(tonumber(clock[2]) / 1000)
local cutoff_ms = now_ms - window_ms
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', cutoff_ms)
redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', cutoff_ms)
local user_count = redis.call('ZCARD', KEYS[1])
local global_count = redis.call('ZCARD', KEYS[2])
local function retry_ms(key, count, limit)
  local index = count - limit
  local oldest = redis.call('ZRANGE', key, index, index, 'WITHSCORES')
  if #oldest == 0 then return window_ms end
  return math.max(1, tonumber(oldest[2]) + window_ms - now_ms)
end
local retry = 0
if user_count >= user_limit then
  retry = math.max(retry, retry_ms(KEYS[1], user_count, user_limit))
end
if global_count >= global_limit then
  retry = math.max(retry, retry_ms(KEYS[2], global_count, global_limit))
end
if retry > 0 then return {0, retry} end
local request_id = ARGV[4]
redis.call('ZADD', KEYS[1], now_ms, request_id)
redis.call('ZADD', KEYS[2], now_ms, request_id)
redis.call('PEXPIRE', KEYS[1], window_ms * 2)
redis.call('PEXPIRE', KEYS[2], window_ms * 2)
return {1, 0}
"""


class RedisEvalStore(Protocol):
    async def eval(self, script: str, numkeys: int, *keys_and_args: object) -> object: ...

    async def aclose(self) -> None: ...


class RateLimitStoreUnavailable(Exception):
    """Raised when the shared store cannot safely enforce the limit."""


class RateLimitExceeded(Exception):
    def __init__(self, retry_after_seconds: int) -> None:
        self.retry_after_seconds = max(1, retry_after_seconds)


class IceServerRateLimiter:
    def __init__(
        self,
        store: RedisEvalStore,
        *,
        user_limit: int = 10,
        global_limit: int = 120,
        window_seconds: int = 60,
        namespace: str = "northstar:production:ice-servers",
    ) -> None:
        self._store = store
        self._user_limit = user_limit
        self._global_limit = global_limit
        self._window_seconds = window_seconds
        self._namespace = namespace

    async def check(self, verified_subject: str) -> None:
        # Do not store employee identifiers or access tokens in Redis keys.
        subject_digest = hashlib.sha256(verified_subject.encode("utf-8")).hexdigest()
        try:
            result = await self._store.eval(
                _RATE_LIMIT_SCRIPT,
                2,
                f"{self._namespace}:user:{subject_digest}",
                f"{self._namespace}:global",
                self._window_seconds * 1000,
                self._user_limit,
                self._global_limit,
                uuid4().hex,
            )
            allowed, retry_ms = self._validate_result(result)
        except Exception as exc:
            # Avoid logging exception text; client errors may contain connection
            # details or the configured Redis URL.
            logger.warning("rate_limit_store_unavailable", extra={"event": "rate_limit_store_unavailable"})
            raise RateLimitStoreUnavailable from exc

        if not allowed:
            raise RateLimitExceeded((retry_ms + 999) // 1000)

    def _validate_result(self, result: object) -> tuple[int, int]:
        # Redis integer replies decode to Python ints. Reject coercions such as
        # bools, strings, tuples, extra elements, and unknown allow codes.
        if type(result) is not list or len(result) != 2:
            raise ValueError("Unexpected rate-limit response shape")
        allowed, retry_ms = result
        if type(allowed) is not int or allowed not in {0, 1}:
            raise ValueError("Unexpected rate-limit decision")
        if type(retry_ms) is not int or retry_ms < 0 or retry_ms > self._window_seconds * 1000:
            raise ValueError("Unexpected rate-limit retry value")
        if (allowed == 1 and retry_ms != 0) or (allowed == 0 and retry_ms == 0):
            raise ValueError("Inconsistent rate-limit response")
        return allowed, retry_ms


def create_redis_client(settings: Settings) -> RedisEvalStore:
    """Create a lazy async client; no connection or ping occurs here."""
    if not settings.rate_limit_redis_url:
        raise RateLimitStoreUnavailable
    from redis.asyncio import Redis

    try:
        return Redis.from_url(
            settings.rate_limit_redis_url.get_secret_value(),
            socket_connect_timeout=1.0,
            socket_timeout=1.0,
            decode_responses=False,
        )
    except Exception:
        logger.error("rate_limit_client_initialization_failed", extra={"event": "rate_limit_client_initialization_failed"})
        raise RateLimitStoreUnavailable from None


def create_ice_server_rate_limiter(settings: Settings, store: RedisEvalStore) -> IceServerRateLimiter:
    return IceServerRateLimiter(
        store,
        user_limit=settings.ice_servers_user_limit,
        global_limit=settings.ice_servers_global_limit,
        window_seconds=settings.ice_servers_rate_window_seconds,
        namespace=f"northstar:{settings.environment}:ice-servers",
    )


def get_ice_server_rate_limiter(
    request: Request,
) -> IceServerRateLimiter:
    limiter = getattr(request.app.state, "ice_server_rate_limiter", None)
    if limiter is None:
        logger.warning("rate_limit_store_unavailable", extra={"event": "rate_limit_store_unavailable"})
        raise HTTPException(status_code=503, detail="Service temporarily unavailable")
    return limiter


async def require_ice_server_rate_limit(
    user: VerifiedUser = Depends(require_user),
    limiter: IceServerRateLimiter = Depends(get_ice_server_rate_limiter),
) -> None:
    subject = user.claims.get("sub")
    if not isinstance(subject, str) or not subject:
        # This should be unreachable because JWT validation requires `sub`;
        # fail closed if that invariant ever changes.
        raise HTTPException(status_code=401, detail="Invalid or expired access token")
    try:
        await limiter.check(subject)
    except RateLimitExceeded as exc:
        raise HTTPException(
            status_code=429,
            detail="Too many requests",
            headers={"Retry-After": str(exc.retry_after_seconds)},
        ) from exc
    except RateLimitStoreUnavailable as exc:
        raise HTTPException(status_code=503, detail="Service temporarily unavailable") from exc
