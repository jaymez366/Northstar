from pydantic import BaseModel


class CurrentUserResponse(BaseModel):
    """Identity derived from the verified Supabase access token."""

    user_id: str
