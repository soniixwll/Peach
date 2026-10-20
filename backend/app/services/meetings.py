import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Meeting
from app.schemas import MeetingCreate, MeetingUpdate


async def list_meetings(
    session: AsyncSession, *, limit: int, offset: int
) -> tuple[list[Meeting], int]:
    total = await session.scalar(select(func.count()).select_from(Meeting)) or 0
    result = await session.execute(
        select(Meeting).order_by(Meeting.start_at.desc(), Meeting.id).limit(limit).offset(offset)
    )
    return list(result.scalars()), total


async def get_meeting(session: AsyncSession, meeting_id: uuid.UUID) -> Meeting | None:
    return await session.get(Meeting, meeting_id)


async def create_meeting(session: AsyncSession, payload: MeetingCreate) -> Meeting:
    values = payload.model_dump()
    values["agenda_items"] = [item.model_dump(mode="json") for item in payload.agenda_items]
    values["action_items"] = [item.model_dump(mode="json") for item in payload.action_items]
    if payload.ai_suggestion is not None:
        values["ai_suggestion"] = payload.ai_suggestion.model_dump(mode="json")
    meeting = Meeting(**values)
    session.add(meeting)
    await session.flush()
    await session.refresh(meeting)
    return meeting


async def update_meeting(
    session: AsyncSession, meeting: Meeting, payload: MeetingUpdate
) -> Meeting:
    values = payload.model_dump(exclude_unset=True)
    if payload.agenda_items is not None:
        values["agenda_items"] = [item.model_dump(mode="json") for item in payload.agenda_items]
    if payload.action_items is not None:
        values["action_items"] = [item.model_dump(mode="json") for item in payload.action_items]
    for field, value in values.items():
        setattr(meeting, field, value)
    await session.flush()
    await session.refresh(meeting)
    return meeting


async def delete_meeting(session: AsyncSession, meeting: Meeting) -> None:
    await session.delete(meeting)
    await session.flush()
