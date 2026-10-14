import csv
import io
import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting
from app.reports.weekly import build_weekly_report


def _meeting(
    number: int,
    title: str,
    start_at: datetime,
    duration_minutes: int,
    participant_count: int,
) -> Meeting:
    return Meeting(
        id=uuid.UUID(int=number),
        title=title,
        start_at=start_at,
        duration_minutes=duration_minutes,
        participant_count=participant_count,
    )


def _rows(report: bytes) -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(report.decode("utf-8"))))


def _summary(rows: list[dict[str, str]]) -> dict[str, str]:
    return {row["metric"]: row["value"] for row in rows if row["section"] == "summary"}


def _longest(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    return [row for row in rows if row["section"] == "longest_meeting"]


async def test_valid_iso_week_and_csv_bytes(session: AsyncSession) -> None:
    report = await build_weekly_report("2026-W40", session=session)
    assert isinstance(report, bytes)
    summary = _summary(_rows(report))
    assert summary["requested_week"] == "2026-W40"
    assert summary["previous_week"] == "2026-W39"


async def test_empty_week_has_zero_totals_and_no_longest_meetings(
    session: AsyncSession,
) -> None:
    rows = _rows(await build_weekly_report("2099-W01", session=session))
    summary = _summary(rows)
    assert summary["meeting_count_requested_week"] == "0"
    assert summary["total_duration_hours_requested_week"] == "0.00"
    assert summary["meeting_count_previous_week"] == "0"
    assert summary["total_duration_hours_previous_week"] == "0.00"
    assert summary["meeting_count_change"] == "0"
    assert summary["total_duration_hours_change"] == "0.00"
    assert _longest(rows) == []


async def test_previous_week_and_iso_year_boundary(session: AsyncSession) -> None:
    session.add(_meeting(1, "Previous year", datetime(2025, 12, 22, tzinfo=UTC), 90, 3))
    await session.flush()
    summary = _summary(_rows(await build_weekly_report("2026-W01", session=session)))
    assert summary["previous_week"] == "2025-W52"
    assert summary["meeting_count_previous_week"] == "1"
    assert summary["total_duration_hours_previous_week"] == "1.50"


async def test_half_open_monday_boundaries_totals_and_changes(
    session: AsyncSession,
) -> None:
    session.add_all(
        [
            _meeting(1, "Previous", datetime(2026, 9, 27, 23, 59, tzinfo=UTC), 30, 1),
            _meeting(2, "At start", datetime(2026, 9, 28, tzinfo=UTC), 60, 2),
            _meeting(3, "At end", datetime(2026, 10, 4, 23, 59, tzinfo=UTC), 90, 4),
            _meeting(4, "Next", datetime(2026, 10, 5, tzinfo=UTC), 120, 8),
        ]
    )
    await session.flush()
    summary = _summary(_rows(await build_weekly_report("2026-W40", session=session)))
    assert summary["meeting_count_requested_week"] == "2"
    assert summary["total_duration_hours_requested_week"] == "2.50"
    assert summary["meeting_count_previous_week"] == "1"
    assert summary["total_duration_hours_previous_week"] == "0.50"
    assert summary["meeting_count_change"] == "1"
    assert summary["total_duration_hours_change"] == "2.00"


async def test_five_longest_meetings_and_participant_counts(session: AsyncSession) -> None:
    durations = [15, 75, 30, 120, 45, 90]
    for number, duration in enumerate(durations, start=1):
        session.add(
            _meeting(
                number,
                f"Meeting {number}",
                datetime(2026, 9, 28, number, tzinfo=UTC),
                duration,
                number + 1,
            )
        )
    await session.flush()
    longest = _longest(_rows(await build_weekly_report("2026-W40", session=session)))
    assert [row["title"] for row in longest] == [
        "Meeting 4",
        "Meeting 6",
        "Meeting 2",
        "Meeting 5",
        "Meeting 3",
    ]
    assert [row["duration_minutes"] for row in longest] == ["120", "90", "75", "45", "30"]
    assert [row["participant_count"] for row in longest] == ["5", "7", "3", "6", "4"]


async def test_ties_are_ordered_by_start_then_id_and_output_is_deterministic(
    session: AsyncSession,
) -> None:
    same_start = datetime(2026, 9, 30, 12, tzinfo=UTC)
    session.add_all(
        [
            _meeting(3, "Later", datetime(2026, 10, 1, 12, tzinfo=UTC), 60, 1),
            _meeting(2, "Second ID", same_start, 60, 2),
            _meeting(1, "First ID", same_start, 60, 3),
        ]
    )
    await session.flush()
    first = await build_weekly_report("2026-W40", session=session)
    assert first == await build_weekly_report("2026-W40", session=session)
    longest = _longest(_rows(first))
    assert [row["title"] for row in longest] == ["First ID", "Second ID", "Later"]
    assert longest[0]["start"] == "2026-09-30T12:00:00Z"


@pytest.mark.parametrize(
    "week",
    ["", "2026-40", "2026-W4", "2026-W00", "2026-W54", "2021-W53", "W40-2026"],
)
async def test_invalid_week_is_rejected(week: str, session: AsyncSession) -> None:
    with pytest.raises(ValueError, match="ISO week"):
        await build_weekly_report(week, session=session)
