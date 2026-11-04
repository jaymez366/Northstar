import json
import time
from io import BytesIO
from unittest.mock import Mock
from urllib.error import HTTPError

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from jwt import PyJWKClient, PyJWKClientConnectionError
from jwt import jwks_client as jwks_client_module

from app.core.config import Settings
from app.db import supabase as supabase_module
from app.db.supabase import get_user_supabase
from app.services import auth as auth_module


PROJECT_URL = "https://project.example"
JWT_ISSUER = f"{PROJECT_URL}/auth/v1"
JWKS_URL = f"{JWT_ISSUER}/.well-known/jwks.json"
JWT_AUDIENCE = "authenticated"
REQUIRED_CLAIMS = ("exp", "iat", "sub", "iss", "aud")


@pytest.fixture(scope="module")
def signing_material():
    material = {}
    for algorithm in ("ES256", "RS256"):
        if algorithm == "ES256":
            private_key = ec.generate_private_key(ec.SECP256R1())
        else:
            private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        jwk = json.loads(jwt.algorithms.get_default_algorithms()[algorithm].to_jwk(private_key.public_key()))
        jwk.update({"kid": f"test-{algorithm.lower()}", "use": "sig", "alg": algorithm})
        material[algorithm] = {"private": private_key, "jwk": jwk}
    return material


def make_settings() -> Settings:
    return Settings(
        cors_origins=["http://localhost:5173"],
        supabase_url=PROJECT_URL,
        supabase_anon_key="test-public-anon-key",
        jwt_issuer=JWT_ISSUER,
        jwt_jwks_url=JWKS_URL,
        jwt_audience=JWT_AUDIENCE,
        jwt_algorithms=["ES256", "RS256"],
    )


def make_jwks_client(monkeypatch, jwk):
    client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=300)
    fetches = []

    def fetch_data():
        fetches.append(True)
        return {"keys": [jwk]}

    monkeypatch.setattr(client, "fetch_data", fetch_data)
    monkeypatch.setattr(auth_module, "_jwks_client", lambda _url: client)
    return fetches


def make_rotating_jwks_client(monkeypatch, first_jwk, rotated_jwk):
    client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=300)
    fetches = []
    key_sets = iter(([first_jwk], [rotated_jwk]))

    def fetch_data():
        fetches.append(True)
        return {"keys": next(key_sets)}

    monkeypatch.setattr(client, "fetch_data", fetch_data)
    monkeypatch.setattr(auth_module, "_jwks_client", lambda _url: client)
    return fetches


def mock_jwks_http_response(monkeypatch, response_body, *, lifespan=300):
    opener = Mock()
    responses = response_body if isinstance(response_body, list) else [response_body]
    pending_responses = iter(responses)

    def open_response(*_args, **_kwargs):
        response = next(pending_responses)
        if isinstance(response, BaseException):
            raise response
        return BytesIO(response)

    opener.open.side_effect = open_response
    monkeypatch.setattr(jwks_client_module.urllib.request, "build_opener", lambda *_args: opener)
    monkeypatch.setattr(
        auth_module,
        "_jwks_client",
        lambda url: PyJWKClient(url, cache_jwk_set=True, lifespan=lifespan),
    )
    return opener


def make_token(private_key, algorithm, kid, **claim_overrides):
    now = int(time.time())
    claims = {
        "exp": now + 3600,
        "iat": now,
        "sub": "local-test-user",
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
    }
    claims.update(claim_overrides)
    return jwt.encode(claims, private_key, algorithm=algorithm, headers={"kid": kid})


def send_to_database_route(monkeypatch, token=None):
    settings = make_settings()
    create_client = Mock(side_effect=AssertionError("database client must not be created for rejected authentication"))
    monkeypatch.setattr(supabase_module, "create_client", create_client)
    app = FastAPI()

    @app.get("/database")
    def database_route(client=Depends(get_user_supabase)):
        return {"ok": True}

    app.dependency_overrides[auth_module.get_settings] = lambda: settings
    headers = {"Authorization": f"Bearer {token}"} if token is not None else {}
    response = TestClient(app).get("/database", headers=headers)
    create_client.assert_not_called()
    return response


def make_rotated_key(algorithm, kid):
    if algorithm == "ES256":
        private_key = ec.generate_private_key(ec.SECP256R1())
    else:
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    jwk = json.loads(jwt.algorithms.get_default_algorithms()[algorithm].to_jwk(private_key.public_key()))
    jwk.update({"kid": kid, "use": "sig", "alg": algorithm})
    return {"private": private_key, "jwk": jwk}


def send_to_authenticated_database_route(monkeypatch, token):
    settings = make_settings()
    postgrest = Mock()
    client = Mock()
    client.postgrest = postgrest
    create_client = Mock(return_value=client)
    monkeypatch.setattr(supabase_module, "create_client", create_client)
    app = FastAPI()

    @app.get("/database")
    def database_route(
        user=Depends(auth_module.require_user),
        supabase_client=Depends(get_user_supabase),
    ):
        return {"user_id": user.claims["sub"]}

    app.dependency_overrides[auth_module.get_settings] = lambda: settings
    response = TestClient(app).get("/database", headers={"Authorization": f"Bearer {token}"})
    return response, create_client, postgrest


def test_missing_bearer_credentials_are_rejected_before_database_access(monkeypatch):
    response = send_to_database_route(monkeypatch)

    assert response.status_code == 401
    assert response.json()["detail"] == "Bearer token required"


@pytest.mark.parametrize("algorithm", ["none", "HS256"])
def test_disallowed_jwt_algorithm_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    trusted_key = signing_material["ES256"]
    now = int(time.time())
    claims = {
        "exp": now + 3600,
        "iat": now,
        "sub": "local-test-user",
        "iss": JWT_ISSUER,
        "aud": JWT_AUDIENCE,
    }
    if algorithm == "none":
        token = jwt.encode(claims, key="", algorithm="none", headers={"kid": trusted_key["jwk"]["kid"]})
    else:
        token = jwt.encode(
            claims,
            key="local-test-only-hmac-key-for-rejection",
            algorithm="HS256",
            headers={"kid": trusted_key["jwk"]["kid"]},
        )
    fetches = make_jwks_client(monkeypatch, trusted_key["jwk"])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_valid_jwt_authenticates_expected_user_and_scopes_database_client(
    monkeypatch, signing_material, algorithm
):
    key = signing_material[algorithm]
    make_jwks_client(monkeypatch, key["jwk"])
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])

    response, create_client, postgrest = send_to_authenticated_database_route(monkeypatch, token)

    assert response.status_code == 200
    assert response.json() == {"user_id": "local-test-user"}
    create_client.assert_called_once_with(PROJECT_URL + "/", "test-public-anon-key")
    postgrest.auth.assert_called_once_with(token)


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_rotated_signing_key_is_accepted_after_jwks_refresh(monkeypatch, signing_material, algorithm):
    previous_key = signing_material[algorithm]
    rotated_key = make_rotated_key(algorithm, f"rotated-{algorithm.lower()}")
    fetches = make_rotating_jwks_client(monkeypatch, previous_key["jwk"], rotated_key["jwk"])
    token = make_token(rotated_key["private"], algorithm, rotated_key["jwk"]["kid"])

    response, create_client, postgrest = send_to_authenticated_database_route(monkeypatch, token)

    assert response.status_code == 200
    assert response.json() == {"user_id": "local-test-user"}
    assert len(fetches) == 2
    create_client.assert_called_once()
    postgrest.auth.assert_called_once_with(token)


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_jwks_network_failure_fails_closed_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    client = PyJWKClient(JWKS_URL, cache_jwk_set=True, lifespan=300)
    fetches = []

    def fail_fetch():
        fetches.append(True)
        raise PyJWKClientConnectionError("mock JWKS endpoint unavailable")

    monkeypatch.setattr(client, "fetch_data", fail_fetch)
    monkeypatch.setattr(auth_module, "_jwks_client", lambda _url: client)

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
@pytest.mark.parametrize("status_code", [401, 403, 404, 500])
def test_jwks_http_errors_fail_closed_before_database_access(
    monkeypatch, signing_material, algorithm, status_code
):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    http_error = HTTPError(JWKS_URL, status_code, "mock JWKS error", None, BytesIO(b""))
    opener = mock_jwks_http_response(monkeypatch, [http_error])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    opener.open.assert_called_once()


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_jwks_timeout_fails_closed_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    opener = mock_jwks_http_response(monkeypatch, [TimeoutError("mock JWKS timeout")])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    opener.open.assert_called_once()


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_unexpected_jwks_redirect_fails_closed_without_following_redirect(
    monkeypatch, signing_material, algorithm
):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    redirect = HTTPError(JWKS_URL, 302, "mock redirect", {"Location": "https://redirect.example/jwks"}, BytesIO(b""))
    opener = mock_jwks_http_response(monkeypatch, [redirect])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    opener.open.assert_called_once()


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_removed_cached_key_is_rejected_after_jwks_cache_expires(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    opener = mock_jwks_http_response(
        monkeypatch,
        [json.dumps({"keys": [key["jwk"]]}).encode(), json.dumps({"keys": []}).encode()],
        lifespan=0.01,
    )

    accepted, create_client, _postgrest = send_to_authenticated_database_route(monkeypatch, token)
    time.sleep(0.02)
    rejected = send_to_database_route(monkeypatch, token)

    assert accepted.status_code == 200
    create_client.assert_called_once()
    assert rejected.status_code == 401
    assert opener.open.call_count == 2


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_failed_refresh_of_expired_cached_key_fails_closed(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    opener = mock_jwks_http_response(
        monkeypatch,
        [json.dumps({"keys": [key["jwk"]]}).encode(), TimeoutError("mock JWKS refresh timeout")],
        lifespan=0.01,
    )

    accepted, create_client, _postgrest = send_to_authenticated_database_route(monkeypatch, token)
    time.sleep(0.02)
    rejected = send_to_database_route(monkeypatch, token)

    assert accepted.status_code == 200
    create_client.assert_called_once()
    assert rejected.status_code == 401
    assert opener.open.call_count == 2


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_future_iat_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    mock_jwks_http_response(monkeypatch, json.dumps({"keys": [key["jwk"]]}).encode())
    token = make_token(key["private"], algorithm, key["jwk"]["kid"], iat=int(time.time()) + 3600)

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_future_nbf_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    mock_jwks_http_response(monkeypatch, json.dumps({"keys": [key["jwk"]]}).encode())
    token = make_token(key["private"], algorithm, key["jwk"]["kid"], nbf=int(time.time()) + 3600)

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_malformed_jwks_json_fails_closed_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    mock_jwks_http_response(monkeypatch, b'{"keys":')
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
@pytest.mark.parametrize(
    "jwks_payload",
    [
        [],
        {},
        {"keys": []},
        {"keys": None},
        {"keys": "not-a-list"},
        {"keys": [{}]},
    ],
    ids=["non-object", "missing-keys", "empty-keys", "null-keys", "wrong-key-container", "invalid-jwk"],
)
def test_invalid_jwks_key_structures_fail_closed_before_database_access(
    monkeypatch, signing_material, algorithm, jwks_payload
):
    key = signing_material[algorithm]
    mock_jwks_http_response(monkeypatch, json.dumps(jwks_payload).encode())
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_expired_jwt_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    fetches = make_jwks_client(monkeypatch, key["jwk"])
    now = int(time.time())
    token = make_token(key["private"], algorithm, key["jwk"]["kid"], exp=now - 10, iat=now - 20)

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_invalid_signature_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    trusted = signing_material[algorithm]
    other_key = ec.generate_private_key(ec.SECP256R1()) if algorithm == "ES256" else rsa.generate_private_key(public_exponent=65537, key_size=2048)
    fetches = make_jwks_client(monkeypatch, trusted["jwk"])
    token = make_token(other_key, algorithm, trusted["jwk"]["kid"])

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_incorrect_issuer_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    fetches = make_jwks_client(monkeypatch, key["jwk"])
    token = make_token(key["private"], algorithm, key["jwk"]["kid"], iss="https://wrong-project.example/auth/v1")

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_incorrect_audience_is_rejected_before_database_access(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    fetches = make_jwks_client(monkeypatch, key["jwk"])
    token = make_token(key["private"], algorithm, key["jwk"]["kid"], aud="another-audience")

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
def test_unknown_key_id_is_rejected_after_jwks_refresh(monkeypatch, signing_material, algorithm):
    key = signing_material[algorithm]
    fetches = make_jwks_client(monkeypatch, key["jwk"])
    token = make_token(key["private"], algorithm, "unknown-test-kid")

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert len(fetches) == 2


@pytest.mark.parametrize("algorithm", ["ES256", "RS256"])
@pytest.mark.parametrize("missing_claim", REQUIRED_CLAIMS)
def test_missing_required_claim_is_rejected_before_database_access(
    monkeypatch, signing_material, algorithm, missing_claim
):
    key = signing_material[algorithm]
    fetches = make_jwks_client(monkeypatch, key["jwk"])
    token = make_token(key["private"], algorithm, key["jwk"]["kid"])
    decoded = jwt.decode(token, options={"verify_signature": False})
    decoded.pop(missing_claim)
    token = jwt.encode(decoded, key["private"], algorithm=algorithm, headers={"kid": key["jwk"]["kid"]})

    response = send_to_database_route(monkeypatch, token)

    assert response.status_code == 401
    assert fetches == [True]
