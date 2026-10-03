from httpx import AsyncClient


async def test_liveness(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_readiness_reports_database(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/api/v1/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}
