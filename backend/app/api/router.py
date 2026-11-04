from fastapi import APIRouter

from app.api.routes.auth import router as auth_router
from app.api.routes.calls import router as calls_router
from app.api.routes.health import router as health_router

api_router = APIRouter()
api_router.include_router(auth_router, tags=["authentication"])
api_router.include_router(calls_router, tags=["calls"])
api_router.include_router(health_router, tags=["health"])
