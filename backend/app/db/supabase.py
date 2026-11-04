from fastapi import Depends
from supabase import Client, create_client

from app.core.config import Settings, get_settings
from app.services.auth import VerifiedUser, require_user


def get_user_supabase(
    user: VerifiedUser = Depends(require_user),
    settings: Settings = Depends(get_settings),
) -> Client:
    """Create an isolated public-key client scoped to a verified user's JWT.

    Supabase RLS remains the authorization boundary; never supply a service-role key
    here, and never use client-provided identity or role claims for authorization.
    """
    client = create_client(str(settings.supabase_url), settings.supabase_anon_key)
    client.postgrest.auth(user.access_token)
    return client
