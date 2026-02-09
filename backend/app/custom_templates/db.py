import aiosqlite
import json
import os
import sqlite3
from datetime import datetime
from typing import Optional, Dict, Any
import logging
from contextlib import asynccontextmanager

logger = logging.getLogger(__name__)


class CustomTemplateSummaryDB:
    """Database operations for custom template summaries"""

    def __init__(self, db_path: str = None):
        if db_path is None:
            db_path = os.getenv('DATABASE_PATH', 'meeting_minutes.db')
        self.db_path = db_path
        self._init_table()

    def _init_table(self):
        """Initialize the custom_template_summaries table"""
        # Ensure directory exists
        db_dir = os.path.dirname(self.db_path)
        if db_dir:
            os.makedirs(db_dir, exist_ok=True)

        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS custom_template_summaries (
                    meeting_id TEXT PRIMARY KEY,
                    template_id TEXT,
                    status TEXT NOT NULL DEFAULT 'pending',
                    result TEXT,
                    error TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS meeting_notes (
                    meeting_id TEXT PRIMARY KEY,
                    notes TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            conn.commit()
            logger.info("custom_template_summaries and meeting_notes tables initialized")

    @asynccontextmanager
    async def _get_connection(self):
        """Get an async database connection"""
        conn = await aiosqlite.connect(self.db_path)
        conn.row_factory = aiosqlite.Row
        try:
            yield conn
        finally:
            await conn.close()

    async def create_summary(self, meeting_id: str, template_id: str) -> Dict[str, Any]:
        """Create or reset a custom template summary entry with pending status"""
        now = datetime.utcnow().isoformat()

        async with self._get_connection() as conn:
            # Check if entry exists
            cursor = await conn.execute(
                "SELECT meeting_id FROM custom_template_summaries WHERE meeting_id = ?",
                (meeting_id,)
            )
            existing = await cursor.fetchone()

            if existing:
                # Reset existing entry
                await conn.execute("""
                    UPDATE custom_template_summaries
                    SET template_id = ?, status = 'pending', result = NULL, error = NULL, updated_at = ?
                    WHERE meeting_id = ?
                """, (template_id, now, meeting_id))
                logger.info(f"Reset custom template summary for meeting {meeting_id}")
            else:
                # Create new entry
                await conn.execute("""
                    INSERT INTO custom_template_summaries
                    (meeting_id, template_id, status, created_at, updated_at)
                    VALUES (?, ?, 'pending', ?, ?)
                """, (meeting_id, template_id, now, now))
                logger.info(f"Created custom template summary for meeting {meeting_id}")

            await conn.commit()

            return {
                "meeting_id": meeting_id,
                "template_id": template_id,
                "status": "pending",
                "created_at": now,
                "updated_at": now
            }

    async def save_summary(
        self,
        meeting_id: str,
        result: Dict[str, Any],
        template_id: Optional[str] = None
    ) -> bool:
        """Save a completed custom template summary"""
        now = datetime.utcnow().isoformat()
        result_json = json.dumps(result)

        async with self._get_connection() as conn:
            # Check if entry exists
            cursor = await conn.execute(
                "SELECT meeting_id FROM custom_template_summaries WHERE meeting_id = ?",
                (meeting_id,)
            )
            existing = await cursor.fetchone()

            if existing:
                # Update existing entry
                await conn.execute("""
                    UPDATE custom_template_summaries
                    SET result = ?, status = 'completed', error = NULL, updated_at = ?
                    WHERE meeting_id = ?
                """, (result_json, now, meeting_id))
            else:
                # Insert new entry (upsert behavior)
                await conn.execute("""
                    INSERT INTO custom_template_summaries
                    (meeting_id, template_id, status, result, created_at, updated_at)
                    VALUES (?, ?, 'completed', ?, ?, ?)
                """, (meeting_id, template_id, result_json, now, now))

            await conn.commit()
            logger.info(f"Saved custom template summary for meeting {meeting_id}")
            return True

    async def get_summary(self, meeting_id: str) -> Optional[Dict[str, Any]]:
        """Get a custom template summary by meeting ID"""
        async with self._get_connection() as conn:
            cursor = await conn.execute("""
                SELECT meeting_id, template_id, status, result, error, created_at, updated_at
                FROM custom_template_summaries
                WHERE meeting_id = ?
            """, (meeting_id,))
            row = await cursor.fetchone()

            if not row:
                return None

            result = None
            if row['result']:
                try:
                    result = json.loads(row['result'])
                except json.JSONDecodeError:
                    logger.error(f"Failed to parse result JSON for meeting {meeting_id}")

            return {
                "meeting_id": row['meeting_id'],
                "template_id": row['template_id'],
                "status": row['status'],
                "result": result,
                "error": row['error'],
                "created_at": row['created_at'],
                "updated_at": row['updated_at']
            }

    async def delete_summary(self, meeting_id: str) -> bool:
        """Delete a custom template summary"""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "DELETE FROM custom_template_summaries WHERE meeting_id = ?",
                (meeting_id,)
            )
            await conn.commit()
            return cursor.rowcount > 0

    async def has_custom_summary(self, meeting_id: str) -> bool:
        """Check if a meeting has a custom template summary"""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "SELECT 1 FROM custom_template_summaries WHERE meeting_id = ? AND status = 'completed'",
                (meeting_id,)
            )
            row = await cursor.fetchone()
            return row is not None

    # Meeting Notes

    async def save_notes(self, meeting_id: str, notes: str) -> Dict[str, Any]:
        """Save or update notes for a meeting"""
        now = datetime.utcnow().isoformat()

        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "SELECT meeting_id FROM meeting_notes WHERE meeting_id = ?",
                (meeting_id,)
            )
            existing = await cursor.fetchone()

            if existing:
                await conn.execute("""
                    UPDATE meeting_notes SET notes = ?, updated_at = ?
                    WHERE meeting_id = ?
                """, (notes, now, meeting_id))
            else:
                await conn.execute("""
                    INSERT INTO meeting_notes (meeting_id, notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?)
                """, (meeting_id, notes, now, now))

            await conn.commit()
            return {"meeting_id": meeting_id, "notes": notes, "updated_at": now}

    async def get_notes(self, meeting_id: str) -> Optional[Dict[str, Any]]:
        """Get notes for a meeting"""
        async with self._get_connection() as conn:
            cursor = await conn.execute(
                "SELECT meeting_id, notes, created_at, updated_at FROM meeting_notes WHERE meeting_id = ?",
                (meeting_id,)
            )
            row = await cursor.fetchone()
            if not row:
                return None
            return {
                "meeting_id": row['meeting_id'],
                "notes": row['notes'],
                "created_at": row['created_at'],
                "updated_at": row['updated_at'],
            }
