import logging
import os
import re
from dataclasses import dataclass
from datetime import date
from email.message import EmailMessage
from typing import Any
from urllib.parse import unquote_plus

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

_REPORT_KEY = re.compile(r"^reports/(?P<week>\d{4}-W\d{2})\.csv$")


@dataclass(frozen=True)
class ReportObject:
    bucket: str
    key: str
    week: str


def _parse_s3_event(event: dict[str, Any]) -> ReportObject:
    records = event.get("Records")
    if not isinstance(records, list) or len(records) != 1:
        raise ValueError("S3 report event must contain exactly one record")

    record = records[0]
    if (
        not isinstance(record, dict)
        or record.get("eventSource") != "aws:s3"
        or not str(record.get("eventName", "")).startswith("ObjectCreated:")
    ):
        raise ValueError("unsupported report event record")

    try:
        bucket = record["s3"]["bucket"]["name"]
        encoded_key = record["s3"]["object"]["key"]
    except (KeyError, TypeError) as exc:
        raise ValueError("S3 report event is missing bucket or object key") from exc
    if not isinstance(bucket, str) or not bucket:
        raise ValueError("S3 report event has an invalid bucket")
    if not isinstance(encoded_key, str):
        raise ValueError("S3 report event has an invalid object key")

    key = unquote_plus(encoded_key)
    match = _REPORT_KEY.fullmatch(key)
    if match is None:
        raise ValueError("S3 object is not a weekly report CSV")
    week = match["week"]
    try:
        date.fromisocalendar(int(week[:4]), int(week[-2:]), 1)
    except ValueError as exc:
        raise ValueError("S3 report key contains an invalid ISO week") from exc
    return ReportObject(bucket=bucket, key=key, week=week)


def _build_email(
    report: ReportObject, csv_bytes: bytes, sender: str, recipient: str
) -> EmailMessage:
    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = f"Peach weekly report — {report.week}"
    message.set_content(f"Attached is the Peach weekly meetings report for {report.week}.\n")
    message.add_attachment(
        csv_bytes,
        maintype="text",
        subtype="csv",
        filename=f"peach-weekly-report-{report.week}.csv",
    )
    return message


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    report = _parse_s3_event(event)
    logger.info(
        "report-mailer triggered trigger=s3 key=%s",
        report.key,
        extra={"trigger_source": "s3", "week": report.week},
    )

    sender = os.environ.get("REPORT_SENDER_EMAIL")
    recipient = os.environ.get("REPORT_RECIPIENT_EMAIL")
    if not sender or not recipient:
        raise RuntimeError("report sender and recipient email must be configured")

    try:
        response = boto3.client("s3").get_object(Bucket=report.bucket, Key=report.key)
        csv_bytes = response["Body"].read()
        if not isinstance(csv_bytes, bytes):
            raise TypeError("S3 report body did not return bytes")
        message = _build_email(report, csv_bytes, sender, recipient)
        ses_response = boto3.client("ses").send_raw_email(
            Source=sender,
            Destinations=[recipient],
            RawMessage={"Data": message.as_bytes()},
        )
    except Exception:
        logger.exception("weekly report email failed", extra={"week": report.week})
        raise

    result = {
        "status": "ok",
        "source": "s3",
        "week": report.week,
        "bucket": report.bucket,
        "key": report.key,
        "size_bytes": len(csv_bytes),
        "message_id": ses_response.get("MessageId"),
    }
    logger.info(
        "weekly report email sent",
        extra={"week": report.week, "key": report.key, "size_bytes": len(csv_bytes)},
    )
    return result
