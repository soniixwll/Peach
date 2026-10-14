from datetime import date
from unittest.mock import Mock

import pytest

from app.reports import lambda_handler


def _sqs_event(body: str) -> dict:
    return {"Records": [{"eventSource": "aws:sqs", "body": body}]}


def test_explicit_week_builds_and_uploads_to_deterministic_key(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_build(week: str) -> bytes:
        assert week == "2026-W40"
        return b"report-bytes"

    s3 = Mock()
    monkeypatch.setattr(lambda_handler, "build_weekly_report", fake_build)
    monkeypatch.setattr(lambda_handler.boto3, "client", lambda service: s3)
    monkeypatch.setenv("REPORTS_BUCKET", "test-reports")

    result = lambda_handler.handler(_sqs_event('{"source":"manual","week":"2026-W40"}'), None)

    s3.put_object.assert_called_once_with(
        Bucket="test-reports",
        Key="reports/2026-W40.csv",
        Body=b"report-bytes",
        ContentType="text/csv; charset=utf-8",
    )
    assert result == {
        "status": "ok",
        "source": "manual",
        "week": "2026-W40",
        "bucket": "test-reports",
        "key": "reports/2026-W40.csv",
        "size_bytes": 12,
    }


@pytest.mark.parametrize("include_null", [False, True])
def test_missing_or_null_week_uses_previous_iso_week(
    include_null: bool, monkeypatch: pytest.MonkeyPatch
) -> None:
    event = {"source": "schedule"}
    if include_null:
        event["week"] = None
    monkeypatch.setattr(lambda_handler, "_previous_iso_week", lambda today=None: "2026-W39")
    assert lambda_handler._parse_event(event).week == "2026-W39"


def test_scheduled_sqs_event_uses_previous_week(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(lambda_handler, "_previous_iso_week", lambda today=None: "2026-W39")
    request = lambda_handler._parse_event(_sqs_event('{"source":"schedule"}'))
    assert request == lambda_handler.ReportRequest(source="schedule", week="2026-W39")


def test_manual_sqs_event_uses_explicit_week() -> None:
    request = lambda_handler._parse_event(_sqs_event('{"source":"manual","week":"2026-W40"}'))
    assert request == lambda_handler.ReportRequest(source="manual", week="2026-W40")


@pytest.mark.parametrize("body", ["not-json", "[]", '{"source":'])
def test_malformed_sqs_body_is_rejected(body: str) -> None:
    with pytest.raises(ValueError, match="SQS report message body"):
        lambda_handler._parse_event(_sqs_event(body))


def test_multiple_sqs_records_are_rejected() -> None:
    event = _sqs_event('{"source":"schedule"}')
    event["Records"].append(event["Records"][0])
    with pytest.raises(ValueError, match="exactly one record"):
        lambda_handler._parse_event(event)


@pytest.mark.parametrize("payload", [{"source": "manual"}, {"source": "manual", "week": None}])
def test_manual_trigger_requires_week(payload: dict) -> None:
    with pytest.raises(ValueError, match="requires a week"):
        lambda_handler._parse_event(payload)


def test_previous_iso_week_crosses_year_boundary() -> None:
    assert lambda_handler._previous_iso_week(date(2026, 1, 1)) == "2025-W52"


def test_trigger_is_logged(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    async def fake_build(week: str) -> bytes:
        return b"csv"

    monkeypatch.setattr(lambda_handler, "build_weekly_report", fake_build)
    monkeypatch.setattr(lambda_handler.boto3, "client", lambda service: Mock())
    monkeypatch.setenv("REPORTS_BUCKET", "test-reports")

    with caplog.at_level("INFO"):
        lambda_handler.handler({"source": "schedule", "week": "2026-W40"}, None)

    assert "report trigger received" in caplog.messages
    assert "weekly report stored" in caplog.messages


def test_upload_failure_is_logged_and_propagated(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    async def fake_build(week: str) -> bytes:
        return b"csv"

    s3 = Mock()
    s3.put_object.side_effect = RuntimeError("upload failed")
    monkeypatch.setattr(lambda_handler, "build_weekly_report", fake_build)
    monkeypatch.setattr(lambda_handler.boto3, "client", lambda service: s3)
    monkeypatch.setenv("REPORTS_BUCKET", "test-reports")

    with caplog.at_level("ERROR"), pytest.raises(RuntimeError, match="upload failed"):
        lambda_handler.handler(_sqs_event('{"source":"manual","week":"2026-W40"}'), None)

    assert "weekly report build failed" in caplog.messages


def test_invalid_source_is_rejected() -> None:
    with pytest.raises(ValueError, match="unsupported report trigger"):
        lambda_handler._parse_event({"source": "sqs"})


def test_missing_bucket_fails_before_aws_call(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REPORTS_BUCKET", raising=False)
    with pytest.raises(RuntimeError, match="REPORTS_BUCKET"):
        lambda_handler.handler({"source": "schedule", "week": "2026-W40"}, None)
