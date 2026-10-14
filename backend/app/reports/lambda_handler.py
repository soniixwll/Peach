import asyncio
import json
import logging
import os
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

import boto3

from app.reports.weekly import build_weekly_report

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ReportRequest:
    source: str
    week: str


def _previous_iso_week(today: date | None = None) -> str:
    current = today or datetime.now(UTC).date()
    previous = (current - timedelta(days=current.isoweekday() - 1 + 7)).isocalendar()
    return f"{previous.year:04d}-W{previous.week:02d}"


def _parse_request(payload: dict[str, Any], *, today: date | None = None) -> ReportRequest:
    source = payload.get("source")
    if source not in {"schedule", "manual"}:
        raise ValueError("unsupported report trigger source")

    supplied_week = payload.get("week")
    if supplied_week is not None and not isinstance(supplied_week, str):
        raise ValueError("week must be a string or null")
    if source == "manual" and not supplied_week:
        raise ValueError("manual report trigger requires a week")
    week = supplied_week if supplied_week is not None else _previous_iso_week(today)
    return ReportRequest(source=source, week=week)


def _parse_event(event: dict[str, Any], *, today: date | None = None) -> ReportRequest:
    if "Records" not in event:
        return _parse_request(event, today=today)

    records = event.get("Records")
    if not isinstance(records, list) or len(records) != 1:
        raise ValueError("SQS report event must contain exactly one record")
    record = records[0]
    if not isinstance(record, dict) or record.get("eventSource") != "aws:sqs":
        raise ValueError("unsupported report event record")
    body = record.get("body")
    if not isinstance(body, str):
        raise ValueError("SQS report message body must be a JSON string")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        raise ValueError("SQS report message body is not valid JSON") from exc
    if not isinstance(payload, dict):
        raise ValueError("SQS report message body must be a JSON object")
    return _parse_request(payload, today=today)


async def _build_and_upload(request: ReportRequest, bucket: str, s3_client: Any) -> dict[str, Any]:
    report = await build_weekly_report(request.week)
    key = f"reports/{request.week}.csv"
    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=report,
        ContentType="text/csv; charset=utf-8",
    )
    return {
        "status": "ok",
        "source": request.source,
        "week": request.week,
        "bucket": bucket,
        "key": key,
        "size_bytes": len(report),
    }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    logger.info("report invocation received")
    request = _parse_event(event)
    logger.info(
        "report trigger received",
        extra={"trigger_source": request.source, "requested_week": request.week},
    )
    bucket = os.environ.get("REPORTS_BUCKET")
    if not bucket:
        raise RuntimeError("REPORTS_BUCKET is not configured")

    try:
        result = asyncio.run(_build_and_upload(request, bucket, boto3.client("s3")))
    except Exception:
        logger.exception("weekly report build failed", extra={"week": request.week})
        raise

    logger.info(
        "weekly report stored",
        extra={"week": request.week, "key": result["key"], "size_bytes": result["size_bytes"]},
    )
    return result
