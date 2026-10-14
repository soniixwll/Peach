from email import policy
from email.parser import BytesParser
from io import BytesIO
from unittest.mock import Mock

import pytest

from app.reports import mailer_handler


def _s3_event(key: str = "reports/2026-W40.csv", bucket: str = "test-reports") -> dict:
    return {
        "Records": [
            {
                "eventSource": "aws:s3",
                "eventName": "ObjectCreated:Put",
                "s3": {"bucket": {"name": bucket}, "object": {"key": key}},
            }
        ]
    }


def test_bucket_key_week_and_url_encoding_are_parsed() -> None:
    report = mailer_handler._parse_s3_event(_s3_event("reports%2F2026-W40.csv"))
    assert report == mailer_handler.ReportObject(
        bucket="test-reports", key="reports/2026-W40.csv", week="2026-W40"
    )


@pytest.mark.parametrize(
    "key",
    [
        "other/2026-W40.csv",
        "reports/2026-W40.txt",
        "reports/nested/2026-W40.csv",
        "reports/2026-W54.csv",
    ],
)
def test_non_report_objects_are_rejected(key: str) -> None:
    with pytest.raises(ValueError, match="weekly report CSV|invalid ISO week"):
        mailer_handler._parse_s3_event(_s3_event(key))


def test_valid_event_downloads_and_sends_csv_attachment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    csv_bytes = b"section,metric,value\nsummary,requested_week,2026-W40\n"
    s3 = Mock()
    s3.get_object.return_value = {"Body": BytesIO(csv_bytes)}
    ses = Mock()
    ses.send_raw_email.return_value = {"MessageId": "test-message-id"}
    clients = {"s3": s3, "ses": ses}
    monkeypatch.setattr(mailer_handler.boto3, "client", lambda service: clients[service])
    monkeypatch.setenv("REPORT_SENDER_EMAIL", "sender@example.com")
    monkeypatch.setenv("REPORT_RECIPIENT_EMAIL", "recipient@example.com")

    result = mailer_handler.handler(_s3_event(), None)

    s3.get_object.assert_called_once_with(Bucket="test-reports", Key="reports/2026-W40.csv")
    call = ses.send_raw_email.call_args.kwargs
    assert call["Source"] == "sender@example.com"
    assert call["Destinations"] == ["recipient@example.com"]
    message = BytesParser(policy=policy.default).parsebytes(call["RawMessage"]["Data"])
    assert message["Subject"] == "Peach weekly report — 2026-W40"
    assert message["From"] == "sender@example.com"
    assert message["To"] == "recipient@example.com"
    attachment = next(message.iter_attachments())
    assert attachment.get_filename() == "peach-weekly-report-2026-W40.csv"
    assert attachment.get_content_type() == "text/csv"
    assert attachment.get_payload(decode=True) == csv_bytes
    assert result["message_id"] == "test-message-id"
    assert result["source"] == "s3"


def test_sender_and_recipient_are_required(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("REPORT_SENDER_EMAIL", raising=False)
    monkeypatch.delenv("REPORT_RECIPIENT_EMAIL", raising=False)
    with pytest.raises(RuntimeError, match="sender and recipient"):
        mailer_handler.handler(_s3_event(), None)


def test_failure_is_logged_and_propagated(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    s3 = Mock()
    s3.get_object.side_effect = RuntimeError("download failed")
    monkeypatch.setattr(mailer_handler.boto3, "client", lambda service: s3)
    monkeypatch.setenv("REPORT_SENDER_EMAIL", "sender@example.com")
    monkeypatch.setenv("REPORT_RECIPIENT_EMAIL", "recipient@example.com")

    with caplog.at_level("ERROR"), pytest.raises(RuntimeError, match="download failed"):
        mailer_handler.handler(_s3_event(), None)

    assert "weekly report email failed" in caplog.messages


def test_s3_trigger_and_success_are_logged(
    monkeypatch: pytest.MonkeyPatch, caplog: pytest.LogCaptureFixture
) -> None:
    s3 = Mock()
    s3.get_object.return_value = {"Body": BytesIO(b"csv")}
    ses = Mock()
    ses.send_raw_email.return_value = {"MessageId": "id"}
    clients = {"s3": s3, "ses": ses}
    monkeypatch.setattr(mailer_handler.boto3, "client", lambda service: clients[service])
    monkeypatch.setenv("REPORT_SENDER_EMAIL", "sender@example.com")
    monkeypatch.setenv("REPORT_RECIPIENT_EMAIL", "recipient@example.com")

    with caplog.at_level("INFO"):
        mailer_handler.handler(_s3_event(), None)

    assert "report-mailer triggered trigger=s3 key=reports/2026-W40.csv" in caplog.messages
    assert "weekly report email sent" in caplog.messages
