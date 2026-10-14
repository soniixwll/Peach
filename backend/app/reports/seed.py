import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionFactory
from app.models import Meeting
from app.reports.weekly import _week_bounds

_SEED_NAMESPACE = uuid.UUID("0d020937-da29-5f18-92b8-98e638fab841")


@dataclass(frozen=True)
class SampleMeeting:
    id: uuid.UUID
    title: str
    start_at: datetime
    duration_minutes: int
    participant_count: int


def _meeting_id(week: str, name: str) -> uuid.UUID:
    return uuid.uuid5(_SEED_NAMESPACE, f"{week}:{name}")


def _sample_meetings(week: str) -> list[SampleMeeting]:
    start, _, previous_week = _week_bounds(week)
    previous_start = start - timedelta(days=7)
    current_specs = [
        ("Planning", 0, 9, 120, 8),
        ("Architecture review", 1, 10, 90, 5),
        ("Product demo", 2, 14, 60, 12),
        ("Team standup", 3, 9, 30, 6),
        ("Retrospective", 4, 15, 45, 7),
        ("One-on-one", 5, 11, 25, 2),
        ("Quick sync", 6, 16, 15, 3),
    ]
    previous_specs = [
        ("Previous planning", 0, 9, 60, 5),
        ("Previous demo", 2, 14, 45, 8),
        ("Previous sync", 4, 11, 30, 3),
    ]

    meetings = [
        SampleMeeting(
            id=_meeting_id(week, title),
            title=title,
            start_at=start + timedelta(days=day, hours=hour),
            duration_minutes=duration,
            participant_count=participants,
        )
        for title, day, hour, duration, participants in current_specs
    ]
    meetings.extend(
        SampleMeeting(
            id=_meeting_id(previous_week, title),
            title=title,
            start_at=previous_start + timedelta(days=day, hours=hour),
            duration_minutes=duration,
            participant_count=participants,
        )
        for title, day, hour, duration, participants in previous_specs
    )
    return meetings


async def _seed(week: str, session: AsyncSession) -> dict[str, int | str]:
    meetings = _sample_meetings(week)
    statement = (
        insert(Meeting)
        .values(
            [
                {
                    "id": meeting.id,
                    "title": meeting.title,
                    "start_at": meeting.start_at,
                    "duration_minutes": meeting.duration_minutes,
                    "participant_count": meeting.participant_count,
                }
                for meeting in meetings
            ]
        )
        .on_conflict_do_nothing(index_elements=[Meeting.id])
        .returning(Meeting.id)
    )
    inserted = len((await session.scalars(statement)).all())
    return {
        "week": week,
        "inserted": inserted,
        "skipped": len(meetings) - inserted,
    }


async def seed_report_meetings(
    week: str, *, session: AsyncSession | None = None
) -> dict[str, int | str]:
    """Idempotently insert deterministic current- and previous-week sample rows."""
    if session is not None:
        return await _seed(week, session)

    async with SessionFactory() as owned_session:
        result = await _seed(week, owned_session)
        await owned_session.commit()
        return result
