import json
from functools import lru_cache
from typing import Annotated, Any

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings, get_settings

bearer_scheme = HTTPBearer(auto_error=False)


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or missing access token",
        headers={"WWW-Authenticate": "Bearer"},
    )


@lru_cache(maxsize=4)
def _public_keys(jwks_json: str) -> dict[str, Any]:
    """Parse a deployment-supplied JWKS once per warm Lambda environment."""
    jwks = json.loads(jwks_json)
    keys = jwks.get("keys") if isinstance(jwks, dict) else None
    if not isinstance(keys, list):
        raise ValueError("JWKS must contain a keys list")

    parsed: dict[str, Any] = {}
    for jwk in keys:
        if not isinstance(jwk, dict):
            continue
        kid = jwk.get("kid")
        if (
            not isinstance(kid, str)
            or jwk.get("kty") != "RSA"
            or jwk.get("alg") not in (None, "RS256")
            or jwk.get("use") not in (None, "sig")
        ):
            continue
        parsed[kid] = jwt.PyJWK.from_dict(jwk, algorithm="RS256").key
    if not parsed:
        raise ValueError("JWKS contains no usable RS256 signing keys")
    return parsed


def require_access_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, Any]:
    """Verify a Cognito access token and return its claims."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized()

    try:
        header = jwt.get_unverified_header(credentials.credentials)
        if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
            raise _unauthorized()

        key = _public_keys(settings.cognito_jwks_json).get(header["kid"])
        if key is None:
            raise _unauthorized()

        claims: dict[str, Any] = jwt.decode(
            credentials.credentials,
            key=key,
            algorithms=["RS256"],
            issuer=settings.cognito_issuer,
            options={
                "verify_aud": False,
                "require": ["exp", "iss", "client_id", "token_use"],
            },
        )
        if claims.get("client_id") != settings.cognito_client_id:
            raise _unauthorized()
        if claims.get("token_use") != "access":
            raise _unauthorized()
        return claims
    except HTTPException:
        raise
    except (jwt.PyJWTError, KeyError, TypeError, ValueError) as exc:
        raise _unauthorized() from exc
