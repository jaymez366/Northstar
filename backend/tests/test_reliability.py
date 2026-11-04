from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient

from app.core.errors import install_error_handlers
from app.core.request_limits import RequestSizeLimitMiddleware


def make_app(max_body_bytes=1024):
    app = FastAPI()
    install_error_handlers(app)
    app.add_middleware(RequestSizeLimitMiddleware, max_body_bytes=max_body_bytes)

    @app.get("/bad-request")
    def bad_request():
        raise HTTPException(status_code=400, detail="private database detail")

    @app.get("/unexpected")
    def unexpected():
        raise RuntimeError("private password and database detail")

    @app.post("/echo")
    async def echo(request: Request):
        return {"length": len(await request.body())}

    return app


def test_http_errors_use_safe_consistent_body():
    with TestClient(make_app()) as client:
        response = client.get("/bad-request")

    assert response.status_code == 400
    assert response.json() == {"error": {"code": "bad_request", "message": "Invalid request"}}
    assert "private database detail" not in response.text


def test_unexpected_errors_hide_details_and_are_not_logged(caplog):
    with TestClient(make_app(), raise_server_exceptions=False) as client:
        response = client.get("/unexpected")

    assert response.status_code == 500
    assert response.json() == {
        "error": {"code": "internal_error", "message": "An unexpected error occurred"}
    }
    assert "private password" not in response.text
    assert "private password" not in caplog.text
    assert "private database detail" not in caplog.text


def test_oversized_request_body_is_rejected():
    with TestClient(make_app(max_body_bytes=8)) as client:
        response = client.post("/echo", content=b"0123456789")

    assert response.status_code == 413
    assert response.json() == {
        "error": {"code": "request_too_large", "message": "Request body is too large"}
    }


def test_request_body_at_limit_reaches_route():
    with TestClient(make_app(max_body_bytes=8)) as client:
        response = client.post("/echo", content=b"12345678")

    assert response.status_code == 200
    assert response.json() == {"length": 8}
