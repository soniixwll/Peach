import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.ai.agenda import ActionItem, AgendaItem, ParsedAgenda


class MeetingBase(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    start_at: datetime
    duration_minutes: int = Field(gt=0, le=1440)
    participant_count: int = Field(ge=0, le=10_000)
    agenda_items: list[AgendaItem] = Field(default_factory=list, max_length=50)
    action_items: list[ActionItem] = Field(default_factory=list, max_length=50)


class MeetingCreate(MeetingBase):
    ai_suggestion: ParsedAgenda | None = None
    ai_model: str | None = Field(default=None, max_length=120)
    ai_prompt_version: str | None = Field(default=None, max_length=32)

    @model_validator(mode="after")
    def complete_ai_provenance(self) -> MeetingCreate:
        values = (self.ai_suggestion, self.ai_model, self.ai_prompt_version)
        if any(value is not None for value in values) and not all(
            value is not None for value in values
        ):
            raise ValueError("AI suggestion, model, and prompt version must be supplied together")
        return self


class MeetingUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    start_at: datetime | None = None
    duration_minutes: int | None = Field(default=None, gt=0, le=1440)
    participant_count: int | None = Field(default=None, ge=0, le=10_000)
    agenda_items: list[AgendaItem] | None = Field(default=None, max_length=50)
    action_items: list[ActionItem] | None = Field(default=None, max_length=50)


class MeetingRead(MeetingBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    ai_suggestion: ParsedAgenda | None
    ai_model: str | None
    ai_prompt_version: str | None


class MeetingList(BaseModel):
    meetings: list[MeetingRead]
    total: int
