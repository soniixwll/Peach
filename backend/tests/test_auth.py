import json
import time

from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient

from app.auth import _public_keys
from app.config import get_settings
from tests.conftest import TEST_CLIENT_ID, TEST_ISSUER, TEST_JWKS_JSON


def _assert_unauthorized(response) -> None:
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


async def test_missing_authorization_returns_401(anonymous_client: AsyncClient) -> None:
    _assert_unauthorized(await anonymous_client.get("/api/v1/items"))


async def test_non_bearer_authorization_returns_401(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": "Basic credentials"}
    )
    _assert_unauthorized(response)


async def test_malformed_authorization_returns_401(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get("/api/v1/items", headers={"Authorization": "Bearer"})
    _assert_unauthorized(response)


async def test_malformed_jwt_returns_401(anonymous_client: AsyncClient) -> None:
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": "Bearer not-a-jwt"}
    )
    _assert_unauthorized(response)


async def test_invalid_signature_returns_401(anonymous_client, token_factory) -> None:
    other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    token = token_factory(private_key=other_key)
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_unknown_kid_returns_401(anonymous_client, token_factory) -> None:
    token = token_factory(kid="unknown-key")
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_wrong_issuer_returns_401(anonymous_client, token_factory) -> None:
    token = token_factory(claims={"iss": "https://issuer.invalid"})
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_wrong_client_id_returns_401(anonymous_client, token_factory) -> None:
    token = token_factory(claims={"client_id": "wrong-client"})
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_id_token_is_rejected(anonymous_client, token_factory) -> None:
    token = token_factory(claims={"token_use": "id", "client_id": None, "aud": TEST_CLIENT_ID})
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_expired_token_returns_401(anonymous_client, token_factory) -> None:
    token = token_factory(claims={"exp": int(time.time()) - 1})
    response = await anonymous_client.get(
        "/api/v1/items", headers={"Authorization": f"Bearer {token}"}
    )
    _assert_unauthorized(response)


async def test_valid_access_token_succeeds(client: AsyncClient) -> None:
    response = await client.get("/api/v1/items")
    assert response.status_code == 200


async def test_health_endpoints_remain_public(anonymous_client: AsyncClient) -> None:
    assert (await anonymous_client.get("/health")).status_code == 200
    assert (await anonymous_client.get("/api/v1/health/ready")).status_code == 200


def test_jwks_parsing_is_cached() -> None:
    _public_keys.cache_clear()
    first = _public_keys(TEST_JWKS_JSON)
    second = _public_keys(TEST_JWKS_JSON)
    assert first is second
    assert _public_keys.cache_info().misses == 1
    assert _public_keys.cache_info().hits == 1


def test_test_configuration_matches_jwks_fixture() -> None:
    settings = get_settings()
    assert settings.cognito_issuer == TEST_ISSUER
    assert settings.cognito_client_id == TEST_CLIENT_ID
    assert json.loads(settings.cognito_jwks_json)["keys"]
