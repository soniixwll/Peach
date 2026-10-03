import json
import os
import time
from collections.abc import AsyncIterator
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import ASGITransport, AsyncClient
from jwt.algorithms import RSAAlgorithm
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool


def _test_database_url() -> str:
    """Never reuse the runtime database: the schema here is dropped and recreated.

    TEST_DATABASE_URL wins if set; otherwise the runtime URL is reused with a
    "_test" suffix on the database name.
    """
    explicit = os.environ.get("TEST_DATABASE_URL")
    if explicit:
        return explicit

    runtime = os.environ.get("DATABASE_URL", "postgresql+asyncpg://peach:peach@db:5432/peach")
    base, _, database = runtime.rpartition("/")
    return f"{base}/{database}_test"


os.environ["APP_ENV"] = "test"
os.environ["DATABASE_URL"] = _test_database_url()

TEST_ISSUER = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_test"
TEST_CLIENT_ID = "test-public-client"
TEST_KID = "test-access-key"
TEST_PRIVATE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
TEST_JWK = json.loads(RSAAlgorithm.to_jwk(TEST_PRIVATE_KEY.public_key()))
TEST_JWK.update({"kid": TEST_KID, "alg": "RS256", "use": "sig"})
TEST_JWKS_JSON = json.dumps({"keys": [TEST_JWK]}, separators=(",", ":"))
os.environ["COGNITO_ISSUER"] = TEST_ISSUER
os.environ["COGNITO_CLIENT_ID"] = TEST_CLIENT_ID
os.environ["COGNITO_JWKS_JSON"] = TEST_JWKS_JSON

from app.db import Base, get_session  # noqa: E402
from app.main import create_app  # noqa: E402


@pytest.fixture
def token_factory():
    def _make_token(
        *,
        claims: dict[str, Any] | None = None,
        kid: str = TEST_KID,
        private_key=TEST_PRIVATE_KEY,
    ) -> str:
        now = int(time.time())
        payload: dict[str, Any] = {
            "sub": "test-user",
            "iss": TEST_ISSUER,
            "client_id": TEST_CLIENT_ID,
            "token_use": "access",
            "scope": "openid email profile",
            "iat": now,
            "exp": now + 300,
        }
        payload.update(claims or {})
        payload = {key: value for key, value in payload.items() if value is not None}
        return jwt.encode(payload, private_key, algorithm="RS256", headers={"kid": kid})

    return _make_token


@pytest.fixture
def access_token(token_factory) -> str:
    return token_factory()


async def _ensure_test_database(url: str) -> None:
    """Create the test database if it is not there yet."""
    from sqlalchemy import text

    database = url.rsplit("/", 1)[-1]
    admin_url = url.rsplit("/", 1)[0] + "/postgres"
    admin = create_async_engine(admin_url, poolclass=NullPool, isolation_level="AUTOCOMMIT")
    try:
        async with admin.connect() as conn:
            exists = await conn.scalar(
                text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": database}
            )
            if not exists:
                await conn.execute(text(f'CREATE DATABASE "{database}"'))
    finally:
        await admin.dispose()


@pytest.fixture(scope="session")
async def engine() -> AsyncIterator:
    url = os.environ["DATABASE_URL"]
    await _ensure_test_database(url)
    engine = create_async_engine(url, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session(engine) -> AsyncIterator[AsyncSession]:
    """One connection per test, wrapped in a transaction that is always rolled back."""
    connection = await engine.connect()
    transaction = await connection.begin()
    factory = async_sessionmaker(bind=connection, expire_on_commit=False, class_=AsyncSession)
    async with factory() as session:
        yield session
    await transaction.rollback()
    await connection.close()


@pytest.fixture
async def anonymous_client(session: AsyncSession) -> AsyncIterator[AsyncClient]:
    app = create_app()

    async def _override() -> AsyncIterator[AsyncSession]:
        yield session

    app.dependency_overrides[get_session] = _override
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


@pytest.fixture
async def client(anonymous_client: AsyncClient, access_token: str) -> AsyncIterator[AsyncClient]:
    anonymous_client.headers["Authorization"] = f"Bearer {access_token}"
    yield anonymous_client
