import asyncio
import importlib

from fastapi.testclient import TestClient

from app.core.config import Settings


def configured_test_settings():
    return Settings(
        environment="test",
        cors_origins=["http://localhost:5173"],
        supabase_url="https://project.example",
        supabase_anon_key="public-test-placeholder",
        jwt_issuer="https://project.example/auth/v1",
        jwt_jwks_url="https://project.example/auth/v1/.well-known/jwks.json",
        rate_limit_redis_url="redis://localhost:6379/0",
    )


def main_for_settings(monkeypatch, settings):
    monkeypatch.setenv("ENVIRONMENT", settings.environment)
    monkeypatch.setenv("CORS_ORIGINS", ",".join(settings.cors_origins))
    monkeypatch.setenv("SUPABASE_URL", str(settings.supabase_url))
    monkeypatch.setenv("SUPABASE_ANON_KEY", settings.supabase_anon_key)
    monkeypatch.setenv("JWT_ISSUER", str(settings.jwt_issuer))
    monkeypatch.setenv("JWT_JWKS_URL", str(settings.jwt_jwks_url))
    if settings.rate_limit_redis_url:
        monkeypatch.setenv("RATE_LIMIT_REDIS_URL", settings.rate_limit_redis_url.get_secret_value())
    else:
        monkeypatch.delenv("RATE_LIMIT_REDIS_URL", raising=False)

    from app.core.config import get_settings
    get_settings.cache_clear()
    module = importlib.import_module("app.main")
    monkeypatch.setattr(module, "get_settings", lambda: settings)
    return module


class FakeRedisClient:
    def __init__(self):
        self.close_calls = 0

    async def eval(self, *_args):
        return [1, 0]

    async def aclose(self):
        self.close_calls += 1


def test_application_closes_redis_client_on_shutdown_not_per_request(monkeypatch):
    client = FakeRedisClient()
    main_module = main_for_settings(monkeypatch, configured_test_settings())
    monkeypatch.setattr(main_module, "get_settings", configured_test_settings)
    monkeypatch.setattr(main_module, "create_redis_client", lambda _settings: client)
    application = main_module.create_app()

    with TestClient(application) as test_client:
        assert client.close_calls == 0
        assert test_client.get("/api/v1/health").status_code == 200
        assert client.close_calls == 0
        assert application.state.rate_limit_redis_client is client

    assert client.close_calls == 1
    assert application.state.rate_limit_redis_client is None
    assert application.state.ice_server_rate_limiter is None


def test_application_closes_redis_client_when_lifespan_exits_with_exception(monkeypatch):
    client = FakeRedisClient()
    settings = configured_test_settings()
    main_module = main_for_settings(monkeypatch, settings)
    monkeypatch.setattr(main_module, "get_settings", lambda: settings)
    monkeypatch.setattr(main_module, "create_redis_client", lambda _settings: client)
    application = main_module.create_app()

    async def run():
        try:
            async with main_module.lifespan(application):
                raise RuntimeError("test shutdown path")
        except RuntimeError as exc:
            assert str(exc) == "test shutdown path"

    asyncio.run(run())
    assert client.close_calls == 1
    assert application.state.rate_limit_redis_client is None


def test_local_lifespan_without_redis_configuration_starts_without_a_client(monkeypatch):
    settings = configured_test_settings().model_copy(update={"rate_limit_redis_url": None})
    main_module = main_for_settings(monkeypatch, settings)
    monkeypatch.setattr(main_module, "get_settings", lambda: settings)
    application = main_module.create_app()
    with TestClient(application) as test_client:
        assert test_client.get("/api/v1/health").status_code == 200
        assert application.state.rate_limit_redis_client is None
