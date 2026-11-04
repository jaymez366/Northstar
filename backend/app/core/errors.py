import logging

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, __: RequestValidationError) -> JSONResponse:
        return JSONResponse(status_code=422, content={"error": {"code": "validation_error", "message": "Request validation failed"}})

    @app.exception_handler(HTTPException)
    async def http_error(_: Request, exc: HTTPException) -> JSONResponse:
        safe_errors = {
            400: ("bad_request", "Invalid request"),
            401: ("unauthorized", "Authentication required or invalid"),
            403: ("forbidden", "Access denied"),
            404: ("not_found", "Resource not found"),
            405: ("method_not_allowed", "Method not allowed"),
            409: ("conflict", "Request conflicts with current state"),
            413: ("request_too_large", "Request body is too large"),
            422: ("validation_error", "Request validation failed"),
            429: ("rate_limited", "Too many requests"),
        }
        code, message = safe_errors.get(exc.status_code, ("request_failed", "Request could not be completed"))
        headers = {
            name: value
            for name, value in (exc.headers or {}).items()
            if name.lower() in {"www-authenticate", "retry-after"}
        }
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": code, "message": message}},
            headers=headers,
        )

    @app.exception_handler(Exception)
    async def unexpected_error(request: Request, _: Exception) -> JSONResponse:
        route = request.scope.get("route")
        route_template = getattr(route, "path", "unmatched")
        logger.error(
            "unhandled_request_error",
            extra={"event": "unhandled_request_error", "method": request.method, "route": route_template},
        )
        return JSONResponse(status_code=500, content={"error": {"code": "internal_error", "message": "An unexpected error occurred"}})
