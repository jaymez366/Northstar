from fastapi.testclient import TestClient

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
