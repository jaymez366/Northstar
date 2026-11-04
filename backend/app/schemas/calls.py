from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, model_validator


NonEmptyText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4096)]


class IceServer(BaseModel):
    urls: NonEmptyText | list[NonEmptyText]
    username: NonEmptyText | None = None
    credential: NonEmptyText | None = Field(default=None, repr=False)

    @model_validator(mode="after")
    def credentials_for_turn_urls(self) -> "IceServer":
        urls = [self.urls] if isinstance(self.urls, str) else self.urls
        if not urls:
            raise ValueError("ICE server URLs cannot be empty")
        has_turn = any(url.lower().startswith(("turn:", "turns:")) for url in urls)
        if has_turn and (not self.username or not self.credential):
            raise ValueError("TURN ICE servers require temporary credentials")
        return self


class IceServersResponse(BaseModel):
    ice_servers: Annotated[list[IceServer], Field(min_length=1, max_length=32)]
    expires_at: datetime
