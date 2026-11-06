from functools import lru_cache
import ipaddress
import re
from typing import Annotated
from urllib.parse import urlsplit

from pydantic import AnyHttpUrl, BeforeValidator, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


def _parse_csv(value: object) -> object:
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return value


CsvList = Annotated[list[str], NoDecode, BeforeValidator(_parse_csv)]


def _valid_redis_hostname(hostname: str | None) -> bool:
    if not hostname or any(character.isspace() for character in hostname):
        return False
    try:
        ipaddress.ip_address(hostname)
        return True
    except ValueError:
        pass
    try:
        ascii_hostname = hostname.encode("idna").decode("ascii").rstrip(".")
    except UnicodeError:
        return False
    if not ascii_hostname or len(ascii_hostname) > 253:
        return False
    label_pattern = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
    return all(len(label) <= 63 and label_pattern.fullmatch(label) for label in ascii_hostname.split("."))


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "NorthStar API"
    environment: str = "development"
    log_level: str = "INFO"
    api_prefix: str = "/api/v1"
    cors_origins: CsvList = Field(min_length=1)
    supabase_url: AnyHttpUrl
    supabase_anon_key: str = Field(min_length=1)
    jwt_issuer: AnyHttpUrl
    jwt_audience: str = "authenticated"
    jwt_jwks_url: AnyHttpUrl
    jwt_algorithms: CsvList = Field(default_factory=lambda: ["ES256", "RS256"])
    max_request_body_bytes: int = Field(default=1_048_576, ge=1_024, le=20_971_520)
    twilio_account_sid: str | None = None
    twilio_api_key: SecretStr | None = None
    twilio_api_secret: SecretStr | None = None
    twilio_turn_ttl_seconds: int = Field(default=3600, ge=1, le=86400)
    rate_limit_redis_url: SecretStr | None = None
    ice_servers_user_limit: int = Field(default=10, ge=1)
    ice_servers_global_limit: int = Field(default=120, ge=1)
    ice_servers_rate_window_seconds: int = Field(default=60, ge=1, le=86400)

    @field_validator("environment")
    @classmethod
    def supported_environment(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"development", "test", "production"}:
            raise ValueError("ENVIRONMENT must be development, test, or production")
        return normalized

    @field_validator("cors_origins")
    @classmethod
    def explicit_origins_only(cls, origins: list[str]) -> list[str]:
        if not origins or any("*" in origin for origin in origins):
            raise ValueError("CORS_ORIGINS must contain explicit origins and cannot include '*'")
        for origin in origins:
            parsed = urlsplit(origin)
            if (
                parsed.scheme not in {"http", "https"}
                or not parsed.hostname
                or parsed.username
                or parsed.password
                or parsed.path not in {"", "/"}
                or parsed.query
                or parsed.fragment
            ):
                raise ValueError("CORS_ORIGINS entries must be explicit origins without paths or credentials")
        return origins

    @field_validator("api_prefix")
    @classmethod
    def normalized_api_prefix(cls, prefix: str) -> str:
        if not prefix.startswith("/") or prefix == "/":
            raise ValueError("API_PREFIX must be a non-root path beginning with '/'")
        return prefix.rstrip("/")

    @field_validator("jwt_algorithms")
    @classmethod
    def safe_jwt_algorithms(cls, algorithms: list[str]) -> list[str]:
        allowed = {"ES256", "RS256"}
        if not algorithms or any(algorithm not in allowed for algorithm in algorithms):
            raise ValueError("JWT_ALGORITHMS may contain only ES256 and RS256")
        return algorithms

    @model_validator(mode="after")
    def supabase_jwks_matches_project(self) -> "Settings":
        project_url = self.supabase_url
        issuer = self.jwt_issuer
        jwks_url = self.jwt_jwks_url

        twilio_values = (
            self.twilio_account_sid,
            self.twilio_api_key.get_secret_value() if self.twilio_api_key else None,
            self.twilio_api_secret.get_secret_value() if self.twilio_api_secret else None,
        )
        configured_twilio_values = [bool(value and value.strip()) for value in twilio_values]
        if any(configured_twilio_values) and not all(configured_twilio_values):
            raise ValueError("TWILIO_ACCOUNT_SID, TWILIO_API_KEY, and TWILIO_API_SECRET must be configured together")

        if (
            project_url.username
            or project_url.password
            or project_url.path not in ("", "/")
            or project_url.query
            or project_url.fragment
        ):
            raise ValueError("SUPABASE_URL must be a project origin without a path or query")
        if self.environment == "production":
            if not self.rate_limit_redis_url or not self.rate_limit_redis_url.get_secret_value().strip():
                raise ValueError("RATE_LIMIT_REDIS_URL is required in production")
            if project_url.scheme != "https":
                raise ValueError("SUPABASE_URL must use HTTPS in production")
            if any(urlsplit(origin).scheme != "https" for origin in self.cors_origins):
                raise ValueError("CORS_ORIGINS must use HTTPS in production")
            if any(urlsplit(origin).hostname in {"localhost", "127.0.0.1", "::1"} for origin in self.cors_origins):
                raise ValueError("CORS_ORIGINS cannot contain loopback origins in production")
        if jwks_url.scheme != "https":
            raise ValueError("JWT_JWKS_URL must use HTTPS")
        if jwks_url.username or jwks_url.password or issuer.username or issuer.password:
            raise ValueError("JWT_ISSUER and JWT_JWKS_URL cannot contain URL credentials")
        if (
            issuer.scheme != project_url.scheme
            or issuer.host != project_url.host
            or issuer.port != project_url.port
        ):
            raise ValueError("JWT_ISSUER must use the configured Supabase project origin")
        if issuer.path.rstrip("/") != "/auth/v1" or issuer.query or issuer.fragment:
            raise ValueError("JWT_ISSUER must use the Supabase /auth/v1 path")
        if jwks_url.host != project_url.host or jwks_url.port != project_url.port:
            raise ValueError("JWT_JWKS_URL must use the configured Supabase project host")
        if jwks_url.path != "/auth/v1/.well-known/jwks.json" or jwks_url.query or jwks_url.fragment:
            raise ValueError("JWT_JWKS_URL must use the Supabase JWKS path")
        if self.rate_limit_redis_url:
            raw_redis_url = self.rate_limit_redis_url.get_secret_value()
            try:
                redis_url = urlsplit(raw_redis_url)
                redis_port = redis_url.port
            except ValueError:
                raise ValueError("RATE_LIMIT_REDIS_URL must be a valid redis:// or rediss:// URL") from None
            path = redis_url.path
            authority = redis_url.netloc.rsplit("@", maxsplit=1)[-1]
            database_path_valid = (
                path in {"", "/"}
                or (
                    path.startswith("/")
                    and path[1:].isascii()
                    and path[1:].isdigit()
                )
            )
            if (
                raw_redis_url != raw_redis_url.strip()
                or redis_url.scheme not in {"redis", "rediss"}
                or not _valid_redis_hostname(redis_url.hostname)
                or authority.endswith(":")
                or (redis_port is not None and not 1 <= redis_port <= 65535)
                or not database_path_valid
                or redis_url.fragment
            ):
                raise ValueError("RATE_LIMIT_REDIS_URL must be a valid redis:// or rediss:// URL")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
