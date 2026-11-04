import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jwt import PyJWKClient

from app.api.router import api_router
from app.core.config import Settings
from app.core.errors import install_error_handlers
from app.services import auth as auth_module


PROJECT_URL = "https://project.example"
JWT_ISSUER = f"{PROJECT_URL}/auth/v1"
JWKS_URL = f"{JWT_ISSUER}/.well-known/jwks.json"


@pytest.fixture(params=["ES256", "RS256"])
def signed_token(monkeypatch, request):
    algorithm = request.param
    if algorithm == "ES256":
        private_key = ec.generate_private_key(ec.SECP256R1())
    else:
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(jwt.algorithms.get_default_algorithms()[algorithm].to_jwk(private_key.public_key()))
    kid = f"identity-route-{algorithm.lower()}"
    jwk.update({"kid": kid, "use": "sig", "alg": algorithm})

    client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=300)
    monkeypatch.setattr(client, "fetch_data", lambda: {"keys": [jwk]})
    monkeypatch.setattr(auth_module, "_jwks_client", lambda _url: client)

    now = int(time.time())
    claims = {
        "exp": now + 300,
        "iat": now,
        "sub": "local-test-user",
        "iss": JWT_ISSUER,
        "aud": "authenticated",
        "role": "service_role",
    }
    token = jwt.encode(claims, private_key, algorithm=algorithm, headers={"kid": kid})
    return token, private_key, algorithm, kid


def make_client():
    settings = Settings(
        cors_origins=["http://localhost:5173"],
        supabase_url=PROJECT_URL,
        supabase_anon_key="local-test-public-key",
        jwt_issuer=JWT_ISSUER,
        jwt_jwks_url=JWKS_URL,
        jwt_audience="authenticated",
        jwt_algorithms=["ES256", "RS256"],
    )
    app = FastAPI()
    install_error_handlers(app)
    app.include_router(api_router, prefix="/api/v1")
    app.dependency_overrides[auth_module.get_settings] = lambda: settings
    return TestClient(app)


def test_current_user_returns_only_verified_subject(signed_token):
    token, _private_key, _algorithm, _kid = signed_token
    with make_client() as client:
        response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 200
    assert response.json() == {"user_id": "local-test-user"}


def test_current_user_rejects_missing_bearer_credentials():
    with make_client() as client:
        response = client.get("/api/v1/auth/me")

    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.json()["error"]["code"] == "unauthorized"


def test_current_user_rejects_invalid_signature_before_returning_identity(signed_token, caplog):
    _token, _private_key, algorithm, kid = signed_token
    wrong_key = ec.generate_private_key(ec.SECP256R1()) if algorithm == "ES256" else rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    now = int(time.time())
    claims = {
        "exp": now + 300,
        "iat": now,
        "sub": "attacker-selected-user",
        "iss": JWT_ISSUER,
        "aud": "authenticated",
    }
    forged_token = jwt.encode(claims, wrong_key, algorithm=algorithm, headers={"kid": kid})

    # The fixture's JWKS contains the original key, while this token was signed by another key.
    with make_client() as client:
        response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {forged_token}"})

    assert response.status_code == 401
    assert response.json()["error"] == {
        "code": "unauthorized",
        "message": "Authentication required or invalid",
    }
    assert "attacker-selected-user" not in caplog.text
    assert forged_token not in caplog.text
