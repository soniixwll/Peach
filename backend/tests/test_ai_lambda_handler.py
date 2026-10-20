import json
from datetime import datetime
from decimal import Decimal

from app.ai import lambda_handler
from app.ai.agenda import ParsedAgenda, ParseResult


def event(token: str | None, body: object, method: str = "POST") -> dict:
    headers = {"content-type": "application/json"}
    if token:
        headers["authorization"] = f"Bearer {token}"
    return {
        "requestContext": {"http": {"method": method}},
        "headers": headers,
        "body": json.dumps(body),
    }


def result() -> ParseResult:
    agenda = ParsedAgenda(
        title="Planning",
        start_at=datetime.fromisoformat("2026-10-21T10:00:00+03:00"),
        duration_minutes=60,
        participant_count=4,
    )
    return ParseResult(
        agenda=agenda,
        model="us.amazon.nova-micro-v1:0",
        prompt_version="agenda-v1",
        input_tokens=10,
        output_tokens=20,
        latency_ms=50,
        cost_usd=Decimal("0.00000315"),
    )


def test_missing_token_returns_401() -> None:
    response = lambda_handler.handler(event(None, {"text": "Agenda"}), None)
    assert response["statusCode"] == 401
    assert response["headers"]["www-authenticate"] == "Bearer"


def test_non_post_returns_405(access_token: str) -> None:
    assert lambda_handler.handler(event(access_token, {}, "GET"), None)["statusCode"] == 405


def test_too_long_returns_413_before_bedrock(monkeypatch, access_token: str) -> None:
    called = False

    def parse(*args, **kwargs):
        nonlocal called
        called = True

    monkeypatch.setattr(lambda_handler, "parse_agenda_with_telemetry", parse)
    response = lambda_handler.handler(event(access_token, {"text": "x" * 10_001}), None)
    assert response["statusCode"] == 413
    assert called is False


def test_success_returns_suggestion_and_safe_telemetry(
    monkeypatch, caplog, access_token: str
) -> None:
    monkeypatch.setattr(lambda_handler, "parse_agenda_with_telemetry", lambda *a, **k: result())
    with caplog.at_level("INFO"):
        response = lambda_handler.handler(
            event(access_token, {"text": "Agenda", "tz": "UTC"}), None
        )
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["model"] == "us.amazon.nova-micro-v1:0"
    assert body["agenda"]["title"] == "Planning"
    telemetry = json.loads(caplog.messages[-1])
    assert telemetry["event"] == "agenda_parsed"
    assert set(telemetry) == {
        "event",
        "user",
        "model",
        "prompt_version",
        "input_tokens",
        "output_tokens",
        "latency_ms",
        "cost_usd",
    }
