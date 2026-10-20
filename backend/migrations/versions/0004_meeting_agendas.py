"""add meeting agendas and AI provenance

Revision ID: 0004
Revises: 0003
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "meetings",
        sa.Column(
            "agenda_items",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
    )
    op.add_column(
        "meetings",
        sa.Column(
            "action_items",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
    )
    op.add_column(
        "meetings",
        sa.Column("ai_suggestion", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    )
    op.add_column("meetings", sa.Column("ai_model", sa.String(length=120), nullable=True))
    op.add_column("meetings", sa.Column("ai_prompt_version", sa.String(length=32), nullable=True))


def downgrade() -> None:
    op.drop_column("meetings", "ai_prompt_version")
    op.drop_column("meetings", "ai_model")
    op.drop_column("meetings", "ai_suggestion")
    op.drop_column("meetings", "action_items")
    op.drop_column("meetings", "agenda_items")
