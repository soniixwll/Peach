"""create meetings table

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-14

"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "meetings",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("start_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column("participant_count", sa.Integer(), nullable=False),
        sa.CheckConstraint("duration_minutes > 0", name="ck_meetings_duration_positive"),
        sa.CheckConstraint(
            "participant_count >= 0", name="ck_meetings_participant_count_nonnegative"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_meetings_start_at", "meetings", ["start_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_meetings_start_at", table_name="meetings")
    op.drop_table("meetings")
