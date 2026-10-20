import base64
import json
import logging
from datetime import UTC, date, datetime
from typing import Any

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import HTTPException

from app.ai.agenda import MAX_AGENDA_LENGTH, AgendaParseError, parse_agenda_with_telemetry
from app.auth import verify_access_token
from app.config import get_settings

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=str, separators=(",", ":")),
    }


def _bearer_token(headers: dict[str, Any]) -> str | None:
    value = next((str(v) for key, v in headers.items() if key.lower() == "authorization"), None)
    if not value:
        return None
    scheme, separator, token = value.partition(" ")
    if separator and scheme.lower() == "bearer" and token.strip():
        return token.strip()
    return None


def _body(event: dict[str, Any]) -> dict[str, Any]:
    raw = event.get("body")
    if not isinstance(raw, str):
        raise ValueError("Request body must be JSON")
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw, validate=True).decode("utf-8")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("Request body must be a JSON object")
    return value


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    method = event.get("requestContext", {}).get("http", {}).get("method")
    if method == "OPTIONS":
        return _response(204, {})
    if method != "POST":
        return _response(405, {"detail": "Method not allowed"})

    settings = get_settings()
    token = _bearer_token(event.get("headers") or {})
    if token is None:
        return {
            **_response(401, {"detail": "Invalid or missing access token"}),
            "headers": {
                "content-type": "application/json",
                "www-authenticate": "Bearer",
            },
        }
    try:
        claims = verify_access_token(token, settings)
    except HTTPException:
        return {
            **_response(401, {"detail": "Invalid or missing access token"}),
            "headers": {
                "content-type": "application/json",
                "www-authenticate": "Bearer",
            },
        }

    try:
        payload = _body(event)
    except (ValueError, json.JSONDecodeError, UnicodeError) as exc:
        return _response(422, {"detail": str(exc)})

    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        return _response(422, {"detail": "text must be a non-empty string"})
    if len(text) > MAX_AGENDA_LENGTH:
        return _response(413, {"detail": f"text exceeds {MAX_AGENDA_LENGTH} characters"})

    tz = payload.get("tz", "UTC")
    today_value = payload.get("today")
    try:
        today = (
            date.fromisoformat(today_value)
            if isinstance(today_value, str)
            else datetime.now(UTC).date()
        )
        if not isinstance(tz, str):
            raise ValueError("tz must be a timezone name")
        result = parse_agenda_with_telemetry(
            text,
            today,
            tz,
            model=settings.parser_model,
        )
    except (AgendaParseError, ValueError) as exc:
        return _response(422, {"detail": str(exc)})
    except BotoCoreError, ClientError:
        logger.exception("agenda parser Bedrock request failed")
        return _response(502, {"detail": "Agenda parsing service is unavailable"})

    logger.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": claims.get("sub", "unknown"),
                "model": result.model,
                "prompt_version": result.prompt_version,
                "input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens,
                "latency_ms": result.latency_ms,
                "cost_usd": str(result.cost_usd),
            },
            separators=(",", ":"),
        )
    )
    suggestion = result.agenda.model_dump(mode="json")
    return _response(
        200,
        {
            "agenda": suggestion,
            "ai_suggestion": suggestion,
            "model": result.model,
            "prompt_version": result.prompt_version,
        },
    )
