import json
import time
from datetime import datetime, timezone

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jwt import PyJWKClient

from app.api.routes.calls import router as calls_router
from app.core.config import Settings, get_settings
from app.core.errors import install_error_handlers
from app.schemas.calls import IceServersResponse
from app.services import auth as auth_module
from app.services import twilio_turn


PROJECT_URL = "https://project.example"
JWT_ISSUER = f"{PROJECT_URL}/auth/v1"
JWKS_URL = f"{JWT_ISSUER}/.well-known/jwks.json"
TEST_ACCOUNT_SID = "AC" + "a" * 32
TEST_API_KEY = "SK" + "b" * 32
TEST_API_SECRET = "local-test-permanent-secret"
TEMP_USERNAME = "temporary-user-123"
TEMP_CREDENTIAL = "temporary-turn-password"
TEST_TTL = 3600


def make_settings(*, twilio_configured=True, ttl=TEST_TTL):
    values = {
        "environment": "test",
        "cors_origins": ["http://localhost:3000"],
        "supabase_url": PROJECT_URL,
        "supabase_anon_key": "local-test-public-key",
        "jwt_issuer": JWT_ISSUER,
        "jwt_jwks_url": JWKS_URL,
        "jwt_audience": "authenticated",
        "jwt_algorithms": ["ES256", "RS256"],
        "twilio_turn_ttl_seconds": ttl,
    }
    if twilio_configured:
        values.update({
            "twilio_account_sid": TEST_ACCOUNT_SID,
            "twilio_api_key": TEST_API_KEY,
            "twilio_api_secret": TEST_API_SECRET,
        })
    return Settings(**values)


@pytest.fixture
def user_token(monkeypatch):
    private_key = ec.generate_private_key(ec.SECP256R1())
    jwk = json.loads(jwt.algorithms.get_default_algorithms()["ES256"].to_jwk(private_key.public_key()))
    jwk.update({"kid": "local-twilio-test-key", "use": "sig", "alg": "ES256"})
    jwks_client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=300)
    monkeypatch.setattr(jwks_client, "fetch_data", lambda: {"keys": [jwk]})
    monkeypatch.setattr(auth_module, "_jwks_client", lambda _url: jwks_client)

    def issue(subject="local-user"):
        now = int(time.time())
        claims = {
            "exp": now + 300,
            "iat": now,
            "sub": subject,
            "iss": JWT_ISSUER,
            "aud": "authenticated",
        }
        return jwt.encode(claims, private_key, algorithm="ES256", headers={"kid": "local-twilio-test-key"})

    return issue


def make_client(settings):
    app = FastAPI()
    install_error_handlers(app)
    app.include_router(calls_router, prefix="/api/v1")
    app.dependency_overrides[get_settings] = lambda: settings
    return TestClient(app)


def provider_payload(*, username=TEMP_USERNAME, credential=TEMP_CREDENTIAL, ttl="3600"):
    return {
        "username": username,
        "ttl": ttl,
        "account_sid": TEST_ACCOUNT_SID,
        "password": "top-level-provider-password-must-not-be-returned",
        "ice_servers": [
            {"urls": "stun:global.stun.twilio.com:3478"},
            {
                "username": username,
                "credential": credential,
                "urls": "turn:global.turn.twilio.com:3478?transport=udp",
            },
            {
                "username": username,
                "credential": credential,
                "urls": ["turn:global.turn.twilio.com:3478?transport=tcp"],
            },
        ],
    }


class FakeResponse:
    def __init__(self, status_code=201, payload=None, json_error=None):
        self.status_code = status_code
        self.payload = payload
        self.json_error = json_error

    def json(self):
        if self.json_error:
            raise self.json_error
        return self.payload


def mock_twilio(monkeypatch, outcomes):
    requests = []
    remaining = list(outcomes)

    class FakeAsyncClient:
        def __init__(self, *, timeout, follow_redirects):
            assert timeout.connect == 2.0
            assert timeout.read == 5.0
            assert follow_redirects is False

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def post(self, url, *, auth, data):
            requests.append({"url": url, "auth": auth, "data": data})
            outcome = remaining.pop(0) if remaining else remaining
            if isinstance(outcome, Exception):
                raise outcome
            return outcome

    monkeypatch.setattr(twilio_turn.httpx, "AsyncClient", FakeAsyncClient)
    return requests


def test_unauthenticated_request_does_not_call_twilio(monkeypatch):
    calls = mock_twilio(monkeypatch, [FakeResponse(payload=provider_payload())])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers")
    assert response.status_code == 401
    assert calls == []


def test_invalid_jwt_does_not_call_twilio(user_token, monkeypatch):
    calls = mock_twilio(monkeypatch, [FakeResponse(payload=provider_payload())])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": "Bearer invalid-token"})
    assert response.status_code == 401
    assert calls == []


def test_valid_user_receives_twilio_ice_servers_and_correct_ttl(user_token, monkeypatch):
    payload = provider_payload()
    calls = mock_twilio(monkeypatch, [FakeResponse(payload=payload)])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    body = response.json()
    assert len(body["ice_servers"]) == 3
    assert body["ice_servers"][0] == {"urls": "stun:global.stun.twilio.com:3478"}
    assert body["ice_servers"][1] == {
        "urls": "turn:global.turn.twilio.com:3478?transport=udp",
        "username": TEMP_USERNAME,
        "credential": TEMP_CREDENTIAL,
    }
    assert calls == [{
        "url": f"https://api.twilio.com/2010-04-01/Accounts/{TEST_ACCOUNT_SID}/Tokens.json",
        "auth": (TEST_API_KEY, TEST_API_SECRET),
        "data": {"Ttl": TEST_TTL},
    }]


def test_expiry_is_calculated_from_server_time_and_returned_ttl(user_token, monkeypatch):
    before = datetime.now(timezone.utc).timestamp() + TEST_TTL
    mock_twilio(monkeypatch, [FakeResponse(payload=provider_payload(ttl=TEST_TTL))])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    after = datetime.now(timezone.utc).timestamp() + TEST_TTL
    expires_at = datetime.fromisoformat(response.json()["expires_at"].replace("Z", "+00:00")).timestamp()
    assert response.status_code == 200
    assert before <= expires_at <= after


def test_missing_twilio_configuration_fails_safely(user_token, monkeypatch):
    calls = mock_twilio(monkeypatch, [])
    with make_client(make_settings(twilio_configured=False)) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "request_failed"
    assert calls == []


@pytest.mark.parametrize("status_code", [401, 403, 500, 503])
def test_twilio_http_errors_are_hidden(user_token, monkeypatch, caplog, status_code):
    mock_twilio(monkeypatch, [FakeResponse(status_code=status_code, payload={"message": TEST_API_SECRET})])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 503
    assert TEST_API_SECRET not in response.text
    assert TEST_API_SECRET not in caplog.text


def test_twilio_timeout_fails_safely(user_token, monkeypatch, caplog):
    mock_twilio(monkeypatch, [twilio_turn.httpx.TimeoutException("sensitive provider detail")])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 503
    assert "sensitive provider detail" not in response.text
    assert "sensitive provider detail" not in caplog.text


def test_malformed_json_fails_safely(user_token, monkeypatch):
    mock_twilio(monkeypatch, [FakeResponse(json_error=ValueError("malformed sensitive payload"))])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 503
    assert "malformed sensitive payload" not in response.text


@pytest.mark.parametrize("payload", [
    {"ttl": "3600", "ice_servers": provider_payload()["ice_servers"]},
    {"username": TEMP_USERNAME, "ice_servers": provider_payload()["ice_servers"]},
    {"username": TEMP_USERNAME, "ttl": "3600"},
    {"username": TEMP_USERNAME, "ttl": "3600", "ice_servers": []},
    {"username": TEMP_USERNAME, "ttl": "3600", "ice_servers": [None]},
    {"username": TEMP_USERNAME, "ttl": "3600", "ice_servers": [{"urls": "https://evil.example/"}]},
    {"username": TEMP_USERNAME, "ttl": "3600", "ice_servers": [{"urls": "turn:global.turn.twilio.com:3478"}]},
    {"username": TEMP_USERNAME, "ttl": "3600", "ice_servers": [{"urls": "turn:global.turn.twilio.com:3478", "username": "other", "credential": TEMP_CREDENTIAL}]},
    {"username": TEMP_USERNAME, "ttl": "60", "ice_servers": provider_payload()["ice_servers"]},
])
def test_malformed_provider_fields_fail_safely(user_token, monkeypatch, payload):
    mock_twilio(monkeypatch, [FakeResponse(payload=payload)])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 503
    assert TEMP_CREDENTIAL not in response.text


def test_permanent_twilio_credentials_never_appear_in_response_or_logs(user_token, monkeypatch, caplog):
    mock_twilio(monkeypatch, [FakeResponse(payload=provider_payload())])
    with make_client(make_settings()) as client:
        response = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token()}"})
    assert response.status_code == 200
    assert TEST_ACCOUNT_SID not in response.text
    assert TEST_API_KEY not in response.text
    assert TEST_API_SECRET not in response.text
    assert "top-level-provider-password-must-not-be-returned" not in response.text
    assert TEST_API_KEY not in caplog.text
    assert TEST_API_SECRET not in caplog.text


def test_each_request_receives_fresh_uncached_credentials(user_token, monkeypatch):
    first = provider_payload(username="temporary-user-one", credential="temporary-one")
    second = provider_payload(username="temporary-user-two", credential="temporary-two")
    calls = mock_twilio(monkeypatch, [FakeResponse(payload=first), FakeResponse(payload=second)])
    with make_client(make_settings()) as client:
        one = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token('user-one')}"})
        two = client.get("/api/v1/calls/ice-servers", headers={"Authorization": f"Bearer {user_token('user-two')}"})
    assert len(calls) == 2
    assert one.json()["ice_servers"][1]["credential"] == "temporary-one"
    assert two.json()["ice_servers"][1]["credential"] == "temporary-two"
    assert one.json()["ice_servers"][1]["credential"] != two.json()["ice_servers"][1]["credential"]


def test_response_schema_accepts_web_rtc_configuration():
    result = twilio_turn._validate_provider_payload(provider_payload(), TEST_TTL)
    parsed = IceServersResponse.model_validate(result.model_dump())
    assert parsed.ice_servers[0].urls == "stun:global.stun.twilio.com:3478"
