from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import get_settings
from app.core.errors import install_error_handlers
from app.core.logging import configure_logging
from app.core.request_limits import RequestSizeLimitMiddleware
from app.services.rate_limit import (
    RateLimitStoreUnavailable,
    create_ice_server_rate_limiter,
    create_redis_client,
)


@asynccontextmanager
async def lifespan(application: FastAPI):
    settings = get_settings()
    configure_logging(settings.log_level)
    logging.getLogger(__name__).info(
        "application_start", extra={"event": "application_start"}
    )
    redis_client = None
    application.state.rate_limit_redis_client = None
    application.state.ice_server_rate_limiter = None
    try:
        if settings.rate_limit_redis_url:
            try:
                redis_client = create_redis_client(settings)
            except RateLimitStoreUnavailable:
                logging.getLogger(__name__).error(
                    "rate_limit_client_initialization_failed",
                    extra={"event": "rate_limit_client_initialization_failed"},
                )
                raise RuntimeError("Required rate-limit storage could not be initialized") from None
            application.state.rate_limit_redis_client = redis_client
            application.state.ice_server_rate_limiter = create_ice_server_rate_limiter(settings, redis_client)
        yield
    finally:
        try:
            if redis_client is not None:
                try:
                    await redis_client.aclose()
                except Exception:
                    logging.getLogger(__name__).warning(
                        "rate_limit_client_shutdown_failed",
                        extra={"event": "rate_limit_client_shutdown_failed"},
                    )
        finally:
            application.state.rate_limit_redis_client = None
            application.state.ice_server_rate_limiter = None


def create_app() -> FastAPI:
    settings = get_settings()
    application = FastAPI(title=settings.app_name, lifespan=lifespan)
    application.add_middleware(
        RequestSizeLimitMiddleware,
        max_body_bytes=settings.max_request_body_bytes,
    )
    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept"],
    )
    install_error_handlers(application)
    application.include_router(api_router, prefix=settings.api_prefix)
    return application


app = create_app()
