from fastapi.testclient import TestClient


PREVIEW_ORIGIN = "https://northstar-backend-developmen.northstar-1k1.pages.dev"
PRODUCTION_ORIGIN = "https://northstar-1k1.pages.dev"


def test_calls_preflight_allows_exact_preview_and_production_origins(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("CORS_ORIGINS", f"{PREVIEW_ORIGIN},{PRODUCTION_ORIGIN}")
    monkeypatch.setenv("SUPABASE_URL", "https://project.example")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "public-placeholder")
    monkeypatch.setenv("JWT_ISSUER", "https://project.example/auth/v1")
    monkeypatch.setenv("JWT_JWKS_URL", "https://project.example/auth/v1/.well-known/jwks.json")
    monkeypatch.setenv("RATE_LIMIT_REDIS_URL", "redis://localhost:6379/0")

    from app.core.config import get_settings
    get_settings.cache_clear()
    from app.main import create_app

    try:
        with TestClient(create_app()) as client:
            for origin in (PREVIEW_ORIGIN, PRODUCTION_ORIGIN):
                response = client.options(
                    "/api/v1/calls/ice-servers",
                    headers={
                        "Origin": origin,
                        "Access-Control-Request-Method": "GET",
                        "Access-Control-Request-Headers": "authorization",
                    },
                )

                assert response.status_code == 200
                assert response.headers["access-control-allow-origin"] == origin
                assert "get" in response.headers["access-control-allow-methods"].lower()
                assert "authorization" in response.headers["access-control-allow-headers"].lower()

            rejected = client.options(
                "/api/v1/calls/ice-servers",
                headers={
                    "Origin": "https://attacker.example",
                    "Access-Control-Request-Method": "GET",
                    "Access-Control-Request-Headers": "authorization",
                },
            )
            assert rejected.status_code == 400
            assert "access-control-allow-origin" not in rejected.headers
    finally:
        get_settings.cache_clear()


def test_health_check_returns_ok(monkeypatch):
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("CORS_ORIGINS", "http://localhost:5173")
    monkeypatch.setenv("SUPABASE_URL", "https://project.example")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "public-placeholder")
    monkeypatch.setenv("JWT_ISSUER", "https://project.example/auth/v1")
    monkeypatch.setenv("JWT_JWKS_URL", "https://project.example/auth/v1/.well-known/jwks.json")
    from app.core.config import get_settings
    get_settings.cache_clear()
    from app.main import create_app
    app = create_app()
    client = TestClient(app)
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    ready = client.get("/api/v1/ready")
    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}
    allowed = client.get("/api/v1/health", headers={"Origin": "http://localhost:5173"})
    assert allowed.headers["access-control-allow-origin"] == "http://localhost:5173"
    rejected = client.get("/api/v1/health", headers={"Origin": "https://attacker.example"})
    assert "access-control-allow-origin" not in rejected.headers
    get_settings.cache_clear()
