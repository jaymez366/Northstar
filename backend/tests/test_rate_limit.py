import asyncio
import time

import pytest

from app.services.rate_limit import (
    IceServerRateLimiter,
    RateLimitExceeded,
    RateLimitStoreUnavailable,
    _RATE_LIMIT_SCRIPT,
)


class FakeAtomicRedis:
    """In-process atomic fake for deterministic tests; production uses Redis Lua."""

    def __init__(self):
        self._lock = asyncio.Lock()
        self._entries = {}
        self.calls = 0
        self.fail = False

    async def eval(self, script, numkeys, *args):
        assert script == _RATE_LIMIT_SCRIPT
        assert numkeys == 2
        if self.fail:
            raise ConnectionError("private redis endpoint detail")
        user_key, global_key, window_ms, user_limit, global_limit, request_id = args
        window_ms = int(window_ms)
        async with self._lock:
            self.calls += 1
            now = time.monotonic() * 1000
            cutoff = now - window_ms
            for key in (user_key, global_key):
                self._entries[key] = [entry for entry in self._entries.get(key, []) if entry[0] > cutoff]

            user_entries = self._entries[user_key]
            global_entries = self._entries[global_key]
            retry_ms = 0
            for entries, limit in ((user_entries, int(user_limit)), (global_entries, int(global_limit))):
                if len(entries) >= limit:
                    index = len(entries) - limit
                    retry_ms = max(retry_ms, int(entries[index][0] + window_ms - now))
            if retry_ms:
                return [0, max(1, retry_ms)]
            user_entries.append((now, request_id))
            global_entries.append((now, request_id))
            return [1, 0]


def limiter(store, *, user_limit=10, global_limit=120, window=60):
    return IceServerRateLimiter(
        store,
        user_limit=user_limit,
        global_limit=global_limit,
        window_seconds=window,
        namespace="test:ice",
    )


class FixedResponseStore:
    def __init__(self, response):
        self.response = response

    async def eval(self, *_args):
        return self.response


def test_requests_below_limit_are_allowed():
    async def run():
        service = limiter(FakeAtomicRedis(), user_limit=2)
        await service.check("employee-a")
        await service.check("employee-a")
    asyncio.run(run())


def test_exceeding_user_limit_returns_retry_after_value():
    async def run():
        service = limiter(FakeAtomicRedis(), user_limit=1)
        await service.check("employee-a")
        with pytest.raises(RateLimitExceeded) as error:
            await service.check("employee-a")
        assert error.value.retry_after_seconds >= 1
    asyncio.run(run())


def test_independent_users_have_independent_user_limits():
    async def run():
        service = limiter(FakeAtomicRedis(), user_limit=1)
        await service.check("employee-a")
        await service.check("employee-b")
        with pytest.raises(RateLimitExceeded):
            await service.check("employee-a")
    asyncio.run(run())


def test_limiter_instances_share_endpoint_limit_and_store():
    async def run():
        store = FakeAtomicRedis()
        first_worker = limiter(store, user_limit=10, global_limit=2)
        second_worker = limiter(store, user_limit=10, global_limit=2)
        await first_worker.check("employee-a")
        await second_worker.check("employee-b")
        with pytest.raises(RateLimitExceeded):
            await first_worker.check("employee-c")
    asyncio.run(run())


def test_concurrent_requests_are_counted_atomically():
    async def run():
        store = FakeAtomicRedis()
        service = limiter(store, user_limit=10, global_limit=120)

        async def attempt():
            try:
                await service.check("employee-a")
                return True
            except RateLimitExceeded:
                return False

        outcomes = await asyncio.gather(*(attempt() for _ in range(20)))
        assert sum(outcomes) == 10
        assert store.calls == 20
    asyncio.run(run())


def test_store_failure_fails_closed_without_sensitive_exception_text(caplog):
    async def run():
        store = FakeAtomicRedis()
        store.fail = True
        with pytest.raises(RateLimitStoreUnavailable):
            await limiter(store).check("employee-a")
    asyncio.run(run())
    assert "private redis endpoint detail" not in caplog.text


def test_store_timeout_fails_closed():
    class TimeoutStore:
        async def eval(self, *_args):
            raise TimeoutError("sensitive redis timeout details")

    async def run():
        with pytest.raises(RateLimitStoreUnavailable):
            await limiter(TimeoutStore()).check("employee-a")

    asyncio.run(run())


@pytest.mark.parametrize(
    "response",
    [
        [],
        [1],
        [1, 0, 99],
        [2, 0],
        [-1, 0],
        [0, -1],
        [0, 60_001],
        ["1", 0],
        [True, 0],
        [1, True],
        [1, 1],
        [0, 0],
        None,
        (1, 0),
        {"allowed": 1, "retry": 0},
        "allow",
    ],
)
def test_malformed_lua_responses_fail_closed(response, caplog):
    async def run():
        with pytest.raises(RateLimitStoreUnavailable):
            await limiter(FixedResponseStore(response)).check("employee-a")

    asyncio.run(run())
    assert "Unexpected rate-limit" not in caplog.text
    assert "employee-a" not in caplog.text
