import pytest
from pydantic import ValidationError

from app.core.config import Settings


def valid_settings(**overrides):
    values = {
        "environment": "test",
        "cors_origins": ["https://northstar.example"],
        "supabase_url": "https://project.example",
        "supabase_anon_key": "public-placeholder",
        "jwt_issuer": "https://project.example/auth/v1",
        "jwt_jwks_url": "https://project.example/auth/v1/.well-known/jwks.json",
        "twilio_account_sid": None,
        "twilio_api_key": None,
        "twilio_api_secret": None,
    }
    return Settings(**(values | overrides))


def test_settings_accept_explicit_origins():
    assert valid_settings().cors_origins == ["https://northstar.example"]


def test_settings_reject_wildcard_cors_origin():
    with pytest.raises(ValidationError, match="explicit origins"):
        valid_settings(cors_origins=["*"])


def test_settings_require_at_least_one_cors_origin():
    with pytest.raises(ValidationError):
        valid_settings(cors_origins=[])


def test_settings_reject_http_jwks_url():
    with pytest.raises(ValidationError, match="JWT_JWKS_URL must use HTTPS"):
        valid_settings(jwt_jwks_url="http://project.example/auth/v1/.well-known/jwks.json")


def test_settings_reject_jwks_url_for_another_project():
    with pytest.raises(ValidationError, match="configured Supabase project host"):
        valid_settings(jwt_jwks_url="https://another-project.example/auth/v1/.well-known/jwks.json")


def test_settings_reject_jwks_url_with_wrong_path():
    with pytest.raises(ValidationError, match="Supabase JWKS path"):
        valid_settings(jwt_jwks_url="https://project.example/other/jwks.json")


def test_production_requires_https_cors_origins():
    with pytest.raises(ValidationError, match="CORS_ORIGINS must use HTTPS"):
        valid_settings(environment="production", cors_origins=["http://northstar.example"])


def test_production_rejects_loopback_cors_origins():
    with pytest.raises(ValidationError, match="loopback origins"):
        valid_settings(environment="production", cors_origins=["https://localhost:5173"])


def test_production_accepts_explicit_https_origin():
    settings = valid_settings(environment="production")
    assert settings.cors_origins == ["https://northstar.example"]


@pytest.mark.parametrize("origin", ["*", "https://northstar.example/path", "https://user@northstar.example"])
def test_settings_reject_non_origin_cors_entries(origin):
    with pytest.raises(ValidationError):
        valid_settings(cors_origins=[origin])


def test_request_body_limit_has_safe_bounds():
    with pytest.raises(ValidationError):
        valid_settings(max_request_body_bytes=0)


def test_environment_must_be_known():
    with pytest.raises(ValidationError, match="ENVIRONMENT must be"):
        valid_settings(environment="staging-ish")


def test_twilio_configuration_must_be_complete():
    with pytest.raises(ValidationError, match="must be configured together"):
        valid_settings(twilio_account_sid="AC" + "a" * 32)


def test_twilio_ttl_is_bounded_by_provider_maximum():
    with pytest.raises(ValidationError):
        valid_settings(twilio_turn_ttl_seconds=86401)
