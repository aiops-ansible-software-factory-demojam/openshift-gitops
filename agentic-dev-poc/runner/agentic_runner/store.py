"""SQLite persistence for one active run and its artifacts."""

from __future__ import annotations

import sqlite3
import threading
from pathlib import Path
from typing import Any

from .models import ACTIVE_STATES, RunRecord


class Store:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.Lock()
        path.parent.mkdir(parents=True, exist_ok=True)
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA foreign_keys=ON")
        self._init()

    def _init(self) -> None:
        self._db.executescript("""
            CREATE TABLE IF NOT EXISTS runs (
              id TEXT PRIMARY KEY,
              idempotency_key TEXT NOT NULL UNIQUE,
              request_hash TEXT NOT NULL,
              source_execution_id TEXT NOT NULL,
              prompt TEXT NOT NULL,
              state TEXT NOT NULL,
              terminal INTEGER NOT NULL,
              error TEXT NOT NULL DEFAULT '',
              cleanup_state TEXT NOT NULL,
              sandbox_name TEXT NOT NULL,
              config_hash TEXT NOT NULL,
              image TEXT NOT NULL,
              policy_hash TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deadline_at TEXT NOT NULL,
              provision_deadline_at TEXT NOT NULL,
              agent_deadline_at TEXT NOT NULL DEFAULT '',
              collect_deadline_at TEXT NOT NULL DEFAULT '',
              agent_exit_code INTEGER,
              summary TEXT NOT NULL DEFAULT '',
              validation_json TEXT NOT NULL DEFAULT '',
              result_json TEXT NOT NULL DEFAULT '',
              cancel_requested INTEGER NOT NULL DEFAULT 0,
              execution_claimed INTEGER NOT NULL DEFAULT 0,
              artifacts_expired INTEGER NOT NULL DEFAULT 0,
              expired_at TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS artifacts (
              id TEXT NOT NULL,
              run_id TEXT NOT NULL,
              name TEXT NOT NULL,
              path TEXT NOT NULL,
              size INTEGER NOT NULL,
              sha256 TEXT NOT NULL,
              content_type TEXT NOT NULL,
              created_at TEXT NOT NULL,
              PRIMARY KEY (run_id, id),
              FOREIGN KEY (run_id) REFERENCES runs(id) ON DELETE CASCADE
            );
            """)
        run_columns = {
            row["name"] for row in self._db.execute("PRAGMA table_info(runs)")
        }
        if "execution_claimed" not in run_columns:
            self._db.execute(
                "ALTER TABLE runs ADD COLUMN execution_claimed INTEGER NOT NULL DEFAULT 0"
            )
        if "artifacts_expired" not in run_columns:
            self._db.execute(
                "ALTER TABLE runs ADD COLUMN artifacts_expired INTEGER NOT NULL DEFAULT 0"
            )
        if "expired_at" not in run_columns:
            self._db.execute(
                "ALTER TABLE runs ADD COLUMN expired_at TEXT NOT NULL DEFAULT ''"
            )
        artifact_pk = [
            row["name"]
            for row in self._db.execute("PRAGMA table_info(artifacts)")
            if row["pk"]
        ]
        if artifact_pk == ["id"]:
            self._db.executescript("""
                ALTER TABLE artifacts RENAME TO artifacts_legacy;
                CREATE TABLE artifacts (
                  id TEXT NOT NULL,
                  run_id TEXT NOT NULL,
                  name TEXT NOT NULL,
                  path TEXT NOT NULL,
                  size INTEGER NOT NULL,
                  sha256 TEXT NOT NULL,
                  content_type TEXT NOT NULL,
                  created_at TEXT NOT NULL,
                  PRIMARY KEY (run_id, id),
                  FOREIGN KEY (run_id) REFERENCES runs(id) ON DELETE CASCADE
                );
                INSERT INTO artifacts
                  (id, run_id, name, path, size, sha256, content_type, created_at)
                SELECT id, run_id, name, path, size, sha256, content_type, created_at
                FROM artifacts_legacy;
                DROP TABLE artifacts_legacy;
                """)
        self._db.commit()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    def reserve_run(self, fields: dict[str, Any]) -> str:
        """Insert a run unless the idempotency key exists or the slot is taken.

        Returns ``created``, ``replay``, or ``conflict``. The check and insert
        share one lock so two callers cannot both take the single slot.
        """
        columns = ", ".join(fields)
        marks = ", ".join("?" for _ in fields)
        with self._lock:
            existing = self._db.execute(
                "SELECT request_hash FROM runs WHERE idempotency_key = ?",
                (fields["idempotency_key"],),
            ).fetchone()
            if existing is not None:
                if existing["request_hash"] != fields["request_hash"]:
                    return "conflict"
                return "replay"
            blocker = self._db.execute(
                """
                SELECT id FROM runs
                WHERE state IN ({})
                   OR cleanup_state != 'complete'
                LIMIT 1
                """.format(",".join("?" for _ in ACTIVE_STATES)),
                tuple(ACTIVE_STATES),
            ).fetchone()
            if blocker is not None:
                return "busy"
            self._db.execute(
                f"INSERT INTO runs ({columns}) VALUES ({marks})",
                tuple(fields.values()),
            )
            self._db.commit()
            return "created"

    def get(self, run_id: str) -> RunRecord | None:
        with self._lock:
            row = self._db.execute(
                "SELECT * FROM runs WHERE id = ?", (run_id,)
            ).fetchone()
        return _row(row) if row else None

    def get_by_idempotency(self, key: str) -> RunRecord | None:
        with self._lock:
            row = self._db.execute(
                "SELECT * FROM runs WHERE idempotency_key = ?", (key,)
            ).fetchone()
        return _row(row) if row else None

    def claim_execution(self, run_id: str, updated_at: str) -> bool:
        """Claim a newly accepted run exactly once before launching a worker."""
        with self._lock:
            cursor = self._db.execute(
                """
                UPDATE runs
                SET execution_claimed = 1, state = 'claimed', updated_at = ?
                WHERE id = ? AND state = 'accepted' AND execution_claimed = 0 AND terminal = 0
                """,
                (updated_at, run_id),
            )
            self._db.commit()
            return cursor.rowcount == 1

    def start_execution(self, run_id: str, updated_at: str) -> bool:
        """Move the single claimed worker into provisioning exactly once."""
        with self._lock:
            cursor = self._db.execute(
                """
                UPDATE runs
                SET state = 'provisioning', updated_at = ?
                WHERE id = ? AND state = 'claimed' AND execution_claimed = 1 AND terminal = 0
                """,
                (updated_at, run_id),
            )
            self._db.commit()
            return cursor.rowcount == 1

    def has_blocker(self) -> RunRecord | None:
        with self._lock:
            row = self._db.execute(
                """
                SELECT * FROM runs
                WHERE state IN ({})
                   OR cleanup_state != 'complete'
                ORDER BY created_at
                LIMIT 1
                """.format(",".join("?" for _ in ACTIVE_STATES)),
                tuple(ACTIVE_STATES),
            ).fetchone()
        return _row(row) if row else None

    def update(self, run_id: str, **fields: Any) -> RunRecord:
        if not fields:
            found = self.get(run_id)
            if found is None:
                raise KeyError(run_id)
            return found
        assignments = ", ".join(f"{key} = ?" for key in fields)
        with self._lock:
            self._db.execute(
                f"UPDATE runs SET {assignments} WHERE id = ?",
                (*fields.values(), run_id),
            )
            self._db.commit()
            row = self._db.execute(
                "SELECT * FROM runs WHERE id = ?", (run_id,)
            ).fetchone()
        if row is None:
            raise KeyError(run_id)
        return _row(row)

    def list_needs_reconcile(self) -> list[RunRecord]:
        with self._lock:
            rows = self._db.execute("""
                SELECT * FROM runs
                WHERE terminal = 0 OR cleanup_state != 'complete'
                ORDER BY created_at
                """).fetchall()
        return [_row(row) for row in rows]

    def list_expired(self, older_than: str) -> list[RunRecord]:
        with self._lock:
            rows = self._db.execute(
                """SELECT * FROM runs
                   WHERE created_at < ? AND terminal = 1 AND artifacts_expired = 0""",
                (older_than,),
            ).fetchall()
        return [_row(row) for row in rows]

    def add_artifact(self, fields: dict[str, Any]) -> None:
        columns = ", ".join(fields)
        marks = ", ".join("?" for _ in fields)
        with self._lock:
            self._db.execute(
                f"INSERT INTO artifacts ({columns}) VALUES ({marks})",
                tuple(fields.values()),
            )
            self._db.commit()

    def get_artifact(self, run_id: str, artifact_id: str) -> sqlite3.Row | None:
        with self._lock:
            return self._db.execute(
                "SELECT * FROM artifacts WHERE run_id = ? AND id = ?",
                (run_id, artifact_id),
            ).fetchone()

    def list_artifacts(self, run_id: str) -> list[sqlite3.Row]:
        with self._lock:
            return list(
                self._db.execute(
                    "SELECT * FROM artifacts WHERE run_id = ? ORDER BY name",
                    (run_id,),
                )
            )

    def delete_artifacts(self, run_id: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM artifacts WHERE run_id = ?", (run_id,))
            self._db.commit()

    def delete_run(self, run_id: str) -> None:
        with self._lock:
            self._db.execute("DELETE FROM runs WHERE id = ?", (run_id,))
            self._db.commit()

    def expire_run(self, run_id: str, expired_at: str) -> None:
        """Remove payload/artifact data but retain the idempotency tombstone."""
        with self._lock:
            self._db.execute("DELETE FROM artifacts WHERE run_id = ?", (run_id,))
            self._db.execute(
                """UPDATE runs
                   SET prompt = '', source_execution_id = '', summary = '',
                       validation_json = '', result_json = '', artifacts_expired = 1,
                       expired_at = ?, updated_at = ?
                   WHERE id = ?""",
                (expired_at, expired_at, run_id),
            )
            self._db.commit()


def _row(row: sqlite3.Row) -> RunRecord:
    return RunRecord(
        id=row["id"],
        idempotency_key=row["idempotency_key"],
        request_hash=row["request_hash"],
        source_execution_id=row["source_execution_id"],
        prompt=row["prompt"],
        state=row["state"],
        terminal=bool(row["terminal"]),
        error=row["error"],
        cleanup_state=row["cleanup_state"],
        sandbox_name=row["sandbox_name"],
        config_hash=row["config_hash"],
        image=row["image"],
        policy_hash=row["policy_hash"],
        created_at=row["created_at"],
        updated_at=row["updated_at"],
        deadline_at=row["deadline_at"],
        provision_deadline_at=row["provision_deadline_at"],
        agent_deadline_at=row["agent_deadline_at"],
        collect_deadline_at=row["collect_deadline_at"],
        agent_exit_code=row["agent_exit_code"],
        summary=row["summary"],
        validation_json=row["validation_json"],
        result_json=row["result_json"],
        cancel_requested=bool(row["cancel_requested"]),
        execution_claimed=bool(row["execution_claimed"]),
        artifacts_expired=bool(row["artifacts_expired"]),
        expired_at=row["expired_at"],
    )
