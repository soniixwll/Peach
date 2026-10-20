from fastapi import APIRouter, Depends

from app.api.routes import health, items, meetings
from app.auth import require_access_token

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(health.router)
api_router.include_router(items.router, dependencies=[Depends(require_access_token)])
api_router.include_router(meetings.router, dependencies=[Depends(require_access_token)])
