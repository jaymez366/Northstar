"""Opt-in tests for the actual Redis Lua script.

Set TEST_RATE_LIMIT_REDIS_URL to a disposable test instance to run these. The
tests never read RATE_LIMIT_REDIS_URL and never fall back to application config.
"""

import asyncio
import hashlib
import os
from uuid import uuid4

import pytest
from redis.asyncio import Redis

from app.services.rate_limit import IceServerRateLimiter, RateLimitExceeded


TEST_REDIS_URL = os.environ.get("TEST_RATE_LIMIT_REDIS_URL", "").strip()
pytestmark = pytest.mark.skipif(
    not TEST_REDIS_URL,
    reason="Set TEST_RATE_LIMIT_REDIS_URL to an isolated test Redis instance to run Lua integration tests",
)


def _run_against_test_redis(test_case):
    async def run():
        production_url = os.environ.get("RATE_LIMIT_REDIS_URL", "").strip()
        if production_url and TEST_REDIS_URL == production_url:
            pytest.fail("TEST_RATE_LIMIT_REDIS_URL must not equal RATE_LIMIT_REDIS_URL")
        client = Redis.from_url(
            TEST_REDIS_URL,
            socket_connect_timeout=1.0,
            socket_timeout=2.0,
            decode_responses=False,
        )
        namespace = f"northstar:test:rate-limit-integration:{uuid4().hex}"
        subjects = ("integration-user-a", "integration-user-b", "integration-user-c")
        scoped_keys = [f"{namespace}:global"] + [
            f"{namespace}:user:{hashlib.sha256(subject.encode()).hexdigest()}"
            for subject in subjects
        ]
        try:
            await client.ping()
            await test_case(client, namespace, subjects)
        finally:
            try:
                await client.delete(*scoped_keys)
            finally:
                await client.aclose()

    asyncio.run(run())


def test_redis_lua_enforces_user_global_limits_and_retry_after():
    async def exercise(client, namespace, subjects):
        limiter = IceServerRateLimiter(
            client,
            user_limit=2,
            global_limit=3,
            window_seconds=3,
            namespace=namespace,
        )
        await limiter.check(subjects[0])
        await limiter.check(subjects[0])
        with pytest.raises(RateLimitExceeded) as user_limit_error:
            await limiter.check(subjects[0])
        assert 1 <= user_limit_error.value.retry_after_seconds <= 3

        await limiter.check(subjects[1])
        with pytest.raises(RateLimitExceeded) as global_limit_error:
            await limiter.check(subjects[2])
        assert 1 <= global_limit_error.value.retry_after_seconds <= 3

    _run_against_test_redis(exercise)


def test_redis_lua_rolling_cutoff_and_key_expiration():
    async def exercise(client, namespace, subjects):
        window = 1
        limiter = IceServerRateLimiter(
            client,
            user_limit=1,
            global_limit=10,
            window_seconds=window,
            namespace=namespace,
        )
        user_key = f"{namespace}:user:{hashlib.sha256(subjects[0].encode()).hexdigest()}"
        await limiter.check(subjects[0])
        assert 0 < await client.pttl(user_key) <= window * 2000
        with pytest.raises(RateLimitExceeded):
            await limiter.check(subjects[0])

        await asyncio.sleep(window + 0.1)
        await limiter.check(subjects[0])
        assert await client.exists(user_key) == 1

        await asyncio.sleep(window * 2 + 0.1)
        assert await client.exists(user_key) == 0
        assert await client.exists(f"{namespace}:global") == 0

    _run_against_test_redis(exercise)


def test_redis_lua_retries_at_the_oldest_expiring_request():
    async def exercise(client, namespace, subjects):
        window = 5
        limiter = IceServerRateLimiter(
            client,
            user_limit=1,
            global_limit=10,
            window_seconds=window,
            namespace=namespace,
        )
        user_key = f"{namespace}:user:{hashlib.sha256(subjects[0].encode()).hexdigest()}"
        await limiter.check(subjects[0])
        oldest = await client.zrange(user_key, 0, 0, withscores=True)
        seconds, microseconds = await client.time()
        now_ms = seconds * 1000 + microseconds // 1000
        expected = max(1, (int(oldest[0][1]) + window * 1000 - now_ms + 999) // 1000)
        with pytest.raises(RateLimitExceeded) as error:
            await limiter.check(subjects[0])
        assert max(1, expected - 1) <= error.value.retry_after_seconds <= expected

    _run_against_test_redis(exercise)


def test_redis_lua_concurrent_requests_respect_both_limits():
    async def exercise(client, namespace, subjects):
        limiter = IceServerRateLimiter(
            client,
            user_limit=10,
            global_limit=20,
            window_seconds=10,
            namespace=namespace,
        )

        async def attempt():
            try:
                await limiter.check(subjects[0])
                return True
            except RateLimitExceeded:
                return False

        outcomes = await asyncio.gather(*(attempt() for _ in range(20)))
        assert sum(outcomes) == 10

    _run_against_test_redis(exercise)
