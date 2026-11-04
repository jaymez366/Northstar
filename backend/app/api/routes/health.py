from fastapi import APIRouter

from app.schemas.health import HealthResponse, ReadinessResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
def health_check() -> HealthResponse:
    return HealthResponse(status="ok")


@router.get("/ready", response_model=ReadinessResponse)
def readiness_check() -> ReadinessResponse:
    """Report that the API process is serving requests; no remote probes run."""
    return ReadinessResponse(status="ready")
