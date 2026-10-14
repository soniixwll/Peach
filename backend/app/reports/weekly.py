import csv
import io
import re
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionFactory
from app.models import Meeting

_ISO_WEEK = re.compile(r"^(?P<year>\d{4})-W(?P<week>\d{2})$")


def _week_bounds(week: str) -> tuple[datetime, datetime, str]:
    match = _ISO_WEEK.fullmatch(week)
    if match is None:
        raise ValueError("week must use ISO week format YYYY-Www, for example 2026-W40")
    try:
        monday = date.fromisocalendar(int(match["year"]), int(match["week"]), 1)
    except ValueError as exc:
        raise ValueError(f"invalid ISO week: {week}") from exc

    start = datetime.combine(monday, datetime.min.time(), tzinfo=UTC)
    previous = (monday - timedelta(days=7)).isocalendar()
    return start, start + timedelta(days=7), f"{previous.year:04d}-W{previous.week:02d}"


async def _totals(session: AsyncSession, start: datetime, end: datetime) -> tuple[int, int]:
    statement = select(
        func.count(Meeting.id), func.coalesce(func.sum(Meeting.duration_minutes), 0)
    ).where(Meeting.start_at >= start, Meeting.start_at < end)
    count, minutes = (await session.execute(statement)).one()
    return int(count), int(minutes)


def _hours(minutes: int) -> str:
    return f"{Decimal(minutes) / Decimal(60):.2f}"


def _utc_timestamp(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


async def _build(week: str, session: AsyncSession) -> bytes:
    start, end, previous_week = _week_bounds(week)
    current_count, current_minutes = await _totals(session, start, end)
    previous_count, previous_minutes = await _totals(session, start - timedelta(days=7), start)
    longest = (
        await session.scalars(
            select(Meeting)
            .where(Meeting.start_at >= start, Meeting.start_at < end)
            .order_by(Meeting.duration_minutes.desc(), Meeting.start_at.asc(), Meeting.id.asc())
            .limit(5)
        )
    ).all()

    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(
        [
            "section",
            "metric",
            "value",
            "title",
            "start",
            "duration_minutes",
            "participant_count",
        ]
    )
    summary = [
        ("requested_week", week),
        ("previous_week", previous_week),
        ("meeting_count_requested_week", current_count),
        ("total_duration_hours_requested_week", _hours(current_minutes)),
        ("meeting_count_previous_week", previous_count),
        ("total_duration_hours_previous_week", _hours(previous_minutes)),
        ("meeting_count_change", current_count - previous_count),
        ("total_duration_hours_change", _hours(current_minutes - previous_minutes)),
    ]
    for metric, value in summary:
        writer.writerow(["summary", metric, value, "", "", "", ""])

    for rank, meeting in enumerate(longest, start=1):
        writer.writerow(
            [
                "longest_meeting",
                "rank",
                rank,
                meeting.title,
                _utc_timestamp(meeting.start_at),
                meeting.duration_minutes,
                meeting.participant_count,
            ]
        )
    return output.getvalue().encode("utf-8")


async def build_weekly_report(week: str, *, session: AsyncSession | None = None) -> bytes:
    """Build a deterministic UTF-8 CSV report for an explicit ISO week."""
    if session is not None:
        return await _build(week, session)
    async with SessionFactory() as owned_session:
        return await _build(week, owned_session)
