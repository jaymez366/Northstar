import jwt
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.db import supabase as supabase_module
from app.db.supabase import get_user_supabase
from app.services.auth import VerifiedUser


def test_users_receive_isolated_clients_with_their_own_tokens(monkeypatch):
    created_clients = []

    class FakePostgrest:
        def __init__(self):
            self.authorization = None

        def auth(self, token):
            self.authorization = token

    class FakeClient:
        def __init__(self):
            self.postgrest = FakePostgrest()

    def fake_create_client(url, key):
        assert url == "https://project.example/"
        assert key == "public-anon-placeholder"
        client = FakeClient()
        created_clients.append(client)
        return client

    monkeypatch.setattr(supabase_module, "create_client", fake_create_client)
    settings = Settings(
        cors_origins=["http://localhost:5173"],
        supabase_url="https://project.example",
        supabase_anon_key="public-anon-placeholder",
        jwt_issuer="https://project.example/auth/v1",
        jwt_jwks_url="https://project.example/auth/v1/.well-known/jwks.json",
    )

    user_a = VerifiedUser(access_token="verified-token-a", claims={"sub": "user-a"})
    user_b = VerifiedUser(access_token="verified-token-b", claims={"sub": "user-b"})
    client_a = get_user_supabase(user=user_a, settings=settings)
    client_b = get_user_supabase(user=user_b, settings=settings)

    assert client_a is not client_b
    assert client_a.postgrest.authorization == "verified-token-a"
    assert client_b.postgrest.authorization == "verified-token-b"
    assert len(created_clients) == 2


def test_invalid_token_is_rejected_before_database_client_creation(monkeypatch):
    def unexpected_database_access(*args, **kwargs):
        raise AssertionError("Database client must not be created for an invalid token")

    monkeypatch.setattr(supabase_module, "create_client", unexpected_database_access)
    settings = Settings(
        cors_origins=["http://localhost:5173"],
        supabase_url="https://project.example",
        supabase_anon_key="public-anon-placeholder",
        jwt_issuer="https://project.example/auth/v1",
        jwt_jwks_url="https://project.example/auth/v1/.well-known/jwks.json",
    )

    class RejectingJwks:
        def get_signing_key_from_jwt(self, token):
            raise jwt.InvalidTokenError("invalid token")

    monkeypatch.setattr("app.services.auth._jwks_client", lambda _: RejectingJwks())
    app = FastAPI()

    @app.get("/database")
    def database_route(client=Depends(get_user_supabase)):
        return {"ok": True}

    app.dependency_overrides[supabase_module.get_settings] = lambda: settings
    response = TestClient(app).get("/database", headers={"Authorization": "Bearer invalid-token"})

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or expired access token"
