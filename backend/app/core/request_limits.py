"""Bound API request bodies without retaining them beyond request dispatch."""

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class RequestSizeLimitMiddleware:
    def __init__(self, app: ASGIApp, max_body_bytes: int) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        content_lengths = [
            value
            for key, value in scope.get("headers", [])
            if key.lower() == b"content-length"
        ]
        if content_lengths:
            try:
                declared_length = int(content_lengths[0])
            except ValueError:
                await self._error(scope, receive, send, 400, "invalid_request", "Invalid request")
                return
            if declared_length < 0:
                await self._error(scope, receive, send, 400, "invalid_request", "Invalid request")
                return
            if declared_length > self.max_body_bytes:
                await self._error(scope, receive, send, 413, "request_too_large", "Request body is too large")
                return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            if message["type"] != "http.request":
                continue
            body.extend(message.get("body", b""))
            if len(body) > self.max_body_bytes:
                await self._error(scope, receive, send, 413, "request_too_large", "Request body is too large")
                return
            if not message.get("more_body", False):
                break

        replayed = False

        async def replay_receive() -> Message:
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return {"type": "http.disconnect"}

        await self.app(scope, replay_receive, send)

    @staticmethod
    async def _error(
        scope: Scope,
        receive: Receive,
        send: Send,
        status_code: int,
        code: str,
        message: str,
    ) -> None:
        response = JSONResponse(
            status_code=status_code,
            content={"error": {"code": code, "message": message}},
        )
        await response(scope, receive, send)
