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
    if overrides.get("environment") == "production" and "rate_limit_redis_url" not in overrides:
        values["rate_limit_redis_url"] = "redis://localhost:6379/0"
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


def test_production_accepts_preview_and_production_https_origins():
    origins = [
        "https://northstar-backend-developmen.northstar-1k1.pages.dev",
        "https://northstar-1k1.pages.dev",
    ]
    settings = valid_settings(
        environment="production",
        cors_origins=origins,
        rate_limit_redis_url="redis://localhost:6379/0",
    )
    assert settings.cors_origins == origins


def test_production_requires_shared_rate_limit_store():
    with pytest.raises(ValidationError, match="RATE_LIMIT_REDIS_URL is required"):
        valid_settings(environment="production", rate_limit_redis_url=None)


@pytest.mark.parametrize("url", ["http://redis.example", "not-a-redis-url", "redis:///missing-host"])
def test_rate_limit_store_url_must_be_valid_redis_url(url):
    with pytest.raises(ValidationError, match="valid redis:// or rediss:// URL"):
        valid_settings(rate_limit_redis_url=url)


@pytest.mark.parametrize(
    "url",
    [
        "redis://redis.internal:6379/0",
        "rediss://user:pass@cache.example:6380/2?ssl_cert_reqs=required",
        "redis://cache.example",
    ],
)
def test_rate_limit_store_accepts_valid_urls_and_authentication(url):
    settings = valid_settings(rate_limit_redis_url=url)
    assert settings.rate_limit_redis_url.get_secret_value() == url


@pytest.mark.parametrize(
    "url",
    [
        "redis://cache.example:notaport/0",
        "redis://cache.example:/0",
        "redis://cache.example:0/0",
        "redis://cache.example:65536/0",
        "redis://cache.example/-1",
        "redis://cache.example/not-a-db",
        "redis:///0",
        "redis://bad host/0",
        "redis://cache.example/0#fragment",
        "redis://[not-an-ipv6-address]/0",
        "ftp://cache.example/0",
    ],
)
def test_rate_limit_store_rejects_malformed_urls(url):
    with pytest.raises(ValidationError, match="valid redis:// or rediss:// URL"):
        valid_settings(rate_limit_redis_url=url)


def test_rate_limit_url_validation_error_does_not_reveal_password():
    password = "not-a-real-password-for-test"
    with pytest.raises(ValidationError) as error:
        valid_settings(rate_limit_redis_url=f"redis://user:{password}@cache.example:bad/0")
    assert password not in str(error.value)


@pytest.mark.parametrize(
    "origin",
    [
        "*",
        "https://*.pages.dev",
        "https://preview.*.pages.dev",
        "https://northstar.example/path",
        "https://user@northstar.example",
    ],
)
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
