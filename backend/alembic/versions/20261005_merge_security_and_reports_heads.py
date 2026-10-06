"""Merge security_sessions and reports/review branches into a single head.

Revision ID: merge_security_reports
Revises: c7a1e4f2b9d6, security_sessions
Create Date: 2026-10-05
"""
from typing import Union

revision: str = 'merge_security_reports'
down_revision: Union[str, tuple] = ('c7a1e4f2b9d6', 'security_sessions')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
