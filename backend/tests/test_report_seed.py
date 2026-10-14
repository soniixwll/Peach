from datetime import UTC, datetime

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting
from app.reports.seed import _sample_meetings, seed_report_meetings


def test_sample_data_is_deterministic() -> None:
    assert _sample_meetings("2026-W40") == _sample_meetings("2026-W40")
    assert len({meeting.id for meeting in _sample_meetings("2026-W40")}) == 10


def test_previous_week_crosses_iso_year_boundary() -> None:
    meetings = _sample_meetings("2026-W01")
    previous = [meeting for meeting in meetings if meeting.title.startswith("Previous")]
    assert len(previous) == 3
    assert min(meeting.start_at for meeting in previous) == datetime(2025, 12, 22, 9, tzinfo=UTC)


@pytest.mark.parametrize("week", ["", "2026-W00", "2026-W54", "2021-W53", "2026-40"])
async def test_invalid_week_is_rejected(week: str, session: AsyncSession) -> None:
    with pytest.raises(ValueError, match="ISO week"):
        await seed_report_meetings(week, session=session)


async def test_seed_creates_expected_current_and_previous_rows(session: AsyncSession) -> None:
    result = await seed_report_meetings("2026-W40", session=session)
    assert result == {"week": "2026-W40", "inserted": 10, "skipped": 0}

    current = (
        await session.scalars(
            select(Meeting)
            .where(
                Meeting.start_at >= datetime(2026, 9, 28, tzinfo=UTC),
                Meeting.start_at < datetime(2026, 10, 5, tzinfo=UTC),
            )
            .order_by(Meeting.duration_minutes.desc())
        )
    ).all()
    previous = (
        await session.scalars(
            select(Meeting).where(
                Meeting.start_at >= datetime(2026, 9, 21, tzinfo=UTC),
                Meeting.start_at < datetime(2026, 9, 28, tzinfo=UTC),
            )
        )
    ).all()

    assert len(current) == 7
    assert sum(meeting.duration_minutes for meeting in current) == 385
    assert [meeting.duration_minutes for meeting in current[:5]] == [120, 90, 60, 45, 30]
    assert [meeting.participant_count for meeting in current[:5]] == [8, 5, 12, 7, 6]
    assert len(previous) == 3
    assert sum(meeting.duration_minutes for meeting in previous) == 135


async def test_seeding_same_week_twice_is_idempotent(session: AsyncSession) -> None:
    first = await seed_report_meetings("2026-W40", session=session)
    second = await seed_report_meetings("2026-W40", session=session)
    count = await session.scalar(select(func.count()).select_from(Meeting))

    assert first == {"week": "2026-W40", "inserted": 10, "skipped": 0}
    assert second == {"week": "2026-W40", "inserted": 0, "skipped": 10}
    assert count == 10
