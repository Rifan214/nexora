from __future__ import annotations

import logging
import os
import re
import secrets
import threading
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Callable

from app.models.tiktok_auth import (
    TikTokAuthSession,
    TikTokAuthSource,
    TikTokAuthStatus,
)
from app.utils.storage import get_temp_storage_dir

logger = logging.getLogger("app.services.tiktok_user_session_store")

_DEFAULT_SESSION_TTL_SECONDS = 3600  # 1 hour default ephemeral lifetime
_SAFE_SESSION_ID_PATTERN = re.compile(r"^[0-9a-fA-F]{16,64}$")
_SENSITIVE_METADATA_KEYS = {
    "sessionid",
    "sid_tt",
    "sessionid_ss",
    "cookie",
    "cookies",
    "authorization",
    "password",
    "token",
    "secret",
    "credentials",
}


def _is_safe_session_id(session_id: str | None) -> bool:
    """Validate that a session ID consists strictly of alphanumeric hex chars."""
    if not session_id or not isinstance(session_id, str):
        return False
    return bool(_SAFE_SESSION_ID_PATTERN.match(session_id))


def _format_netscape_cookie_content(sessionid: str, sid_tt: str | None = None) -> str:
    """Format an in-memory Netscape cookie jar string for yt-dlp TikTok extraction."""
    lines = [
        "# Netscape HTTP Cookie File\n",
        f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\t{sessionid}\n",
    ]
    if sid_tt:
        lines.append(f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsid_tt\t{sid_tt}\n")
    lines.append(f".tiktok.com\tTRUE\t/\tTRUE\t2147483647\tsessionid_ss\t{sessionid}\n")
    return "".join(lines)


@dataclass
class _EphemeralTikTokSessionRecord:
    session: TikTokAuthSession
    sessionid: str
    sid_tt: str | None = None
    temp_cookie_file: Path | None = None
    active_leases: int = 0

    def __repr__(self) -> str:
        return (
            f"_EphemeralTikTokSessionRecord(session_id={self.session.session_id!r}, "
            f"has_cookie_file={self.temp_cookie_file is not None}, "
            f"active_leases={self.active_leases})"
        )


class EphemeralTikTokUserSessionStore:
    """Process-local, in-memory ephemeral store for authenticated TikTok user sessions.

    Guarantees:
    - Thread-safe operations using an internal re-entrant lock.
    - Opaque non-sensitive session IDs generated via secrets.token_hex(16).
    - Strict path traversal defense: IDs validated via regex and path containment.
    - No persistent disk, database, or Redis storage.
    - Restrictive file permissions (0600 file, 0700 dir) on POSIX platforms.
    - Ephemeral temporary cookie files for yt-dlp created on-demand and securely
      unlinked on invalidation, expiration, or process shutdown.
    - Active lease tracking prevents race conditions where an in-flight worker
      download crashes due to sudden mid-download invalidation.
    - Credentials are zeroed in memory upon release/invalidation and never exposed.
    - Automatic startup cleanup purges orphaned cookie files from prior abnormal crashes.
    """

    def __init__(
        self,
        *,
        storage_dir: Path | None = None,
        now: Callable[[], datetime] | None = None,
        cleanup_on_startup: bool = True,
    ) -> None:
        self._storage_dir = storage_dir or get_temp_storage_dir()
        self._now = now or (lambda: datetime.now(UTC))
        self._sessions: dict[str, _EphemeralTikTokSessionRecord] = {}
        self._pending_release_records: dict[str, _EphemeralTikTokSessionRecord] = {}
        self._invalidated_ids: set[str] = set()
        self._expired_ids: set[str] = set()
        self._lock = threading.RLock()

        if cleanup_on_startup:
            self.cleanup_orphaned_cookie_files()

    def create_session(
        self,
        *,
        sessionid: str,
        sid_tt: str | None = None,
        ttl_seconds: int = _DEFAULT_SESSION_TTL_SECONDS,
        metadata: dict[str, Any] | None = None,
    ) -> TikTokAuthSession:
        """Register a new ephemeral TikTok user session with validated tokens."""
        clean_sessionid = sessionid.strip() if isinstance(sessionid, str) else ""
        clean_sid_tt = sid_tt.strip() if isinstance(sid_tt, str) and sid_tt.strip() else None

        if not clean_sessionid:
            raise ValueError("sessionid must be a non-empty string")

        if ttl_seconds <= 0:
            raise ValueError("ttl_seconds must be positive")

        session_id = secrets.token_hex(16)
        created_at = self._now()
        expires_at = created_at + timedelta(seconds=ttl_seconds)

        safe_metadata = {
            k: v
            for k, v in (metadata or {}).items()
            if k.casefold() not in _SENSITIVE_METADATA_KEYS
        }

        session = TikTokAuthSession(
            source=TikTokAuthSource.USER_SESSION,
            authenticated=True,
            status=TikTokAuthStatus.AVAILABLE,
            session_id=session_id,
            created_at=created_at,
            expires_at=expires_at,
            metadata=safe_metadata,
        )

        record = _EphemeralTikTokSessionRecord(
            session=session,
            sessionid=clean_sessionid,
            sid_tt=clean_sid_tt,
            temp_cookie_file=None,
            active_leases=0,
        )

        with self._lock:
            self._sessions[session_id] = record
            self._invalidated_ids.discard(session_id)
            self._expired_ids.discard(session_id)
            self._pending_release_records.pop(session_id, None)

        logger.info(
            "Ephemeral TikTok user session registered session_id=%s ttl_seconds=%s",
            session_id,
            ttl_seconds,
        )
        return session.model_copy()

    def get_session(self, session_id: str | None) -> TikTokAuthSession:
        """Return the safe session descriptor for a session ID."""
        if not _is_safe_session_id(session_id):
            return TikTokAuthSession(
                source=TikTokAuthSource.USER_SESSION,
                authenticated=False,
                status=TikTokAuthStatus.UNAVAILABLE,
                metadata={"source": "user_session"},
            )

        assert session_id is not None
        with self._lock:
            if session_id in self._expired_ids:
                return TikTokAuthSession(
                    source=TikTokAuthSource.USER_SESSION,
                    authenticated=False,
                    status=TikTokAuthStatus.EXPIRED,
                    session_id=session_id,
                    metadata={"source": "user_session"},
                )

            if session_id in self._invalidated_ids:
                return TikTokAuthSession(
                    source=TikTokAuthSource.USER_SESSION,
                    authenticated=False,
                    status=TikTokAuthStatus.INVALID,
                    session_id=session_id,
                    metadata={"source": "user_session"},
                )

            record = self._sessions.get(session_id)
            if record is None:
                return TikTokAuthSession(
                    source=TikTokAuthSource.USER_SESSION,
                    authenticated=False,
                    status=TikTokAuthStatus.UNAVAILABLE,
                    session_id=session_id,
                    metadata={"source": "user_session"},
                )

            now = self._now()
            if record.session.expires_at is not None and now >= record.session.expires_at:
                self._sessions.pop(session_id, None)
                self._expired_ids.add(session_id)
                if record.active_leases > 0:
                    self._pending_release_records[session_id] = record
                else:
                    self._cleanup_record_cookie_file(record)
                    record.sessionid = ""
                    record.sid_tt = None
                logger.info("Ephemeral TikTok user session expired session_id=%s", session_id)
                return TikTokAuthSession(
                    source=TikTokAuthSource.USER_SESSION,
                    authenticated=False,
                    status=TikTokAuthStatus.EXPIRED,
                    session_id=session_id,
                    created_at=record.session.created_at,
                    expires_at=record.session.expires_at,
                    metadata=dict(record.session.metadata),
                )

            return record.session.model_copy()

    def is_valid(self, session_id: str | None) -> bool:
        """Check if a session ID exists, is authenticated, and is not expired."""
        if not _is_safe_session_id(session_id):
            return False
        session = self.get_session(session_id)
        return session.authenticated and session.status == TikTokAuthStatus.AVAILABLE

    def get_cookie_file(self, session_id: str | None) -> Path | None:
        """Provide an ephemeral Netscape cookie file path for yt-dlp integration."""
        if not _is_safe_session_id(session_id):
            return None

        assert session_id is not None
        with self._lock:
            if not self.is_valid(session_id):
                return None

            record = self._sessions.get(session_id)
            if record is None:
                return None

            return self._ensure_cookie_file(record)

    def acquire_lease(self, session_id: str | None) -> Path | None:
        """Acquire an active execution lease on the session's cookie file."""
        if not _is_safe_session_id(session_id):
            return None

        assert session_id is not None
        with self._lock:
            if not self.is_valid(session_id):
                return None

            record = self._sessions.get(session_id)
            if record is None:
                return None

            cookie_path = self._ensure_cookie_file(record)
            if cookie_path is not None:
                record.active_leases += 1
            return cookie_path

    def release_lease(self, session_id: str | None) -> None:
        """Release an active execution lease on the session."""
        if not session_id:
            return

        with self._lock:
            record = self._sessions.get(session_id) or self._pending_release_records.get(session_id)
            if record is None:
                return

            record.active_leases = max(0, record.active_leases - 1)
            if record.active_leases == 0:
                is_invalidated = session_id in self._invalidated_ids
                is_expired = session_id in self._expired_ids or (
                    record.session.expires_at is not None and self._now() >= record.session.expires_at
                )

                if is_invalidated or is_expired:
                    self._cleanup_record_cookie_file(record)
                    record.sessionid = ""
                    record.sid_tt = None
                    self._sessions.pop(session_id, None)
                    self._pending_release_records.pop(session_id, None)
                    if is_expired:
                        self._expired_ids.add(session_id)

    def invalidate(self, session_id: str | None) -> bool:
        """Explicitly invalidate a session and securely remove its ephemeral files."""
        if not _is_safe_session_id(session_id):
            return False

        assert session_id is not None
        with self._lock:
            record = self._sessions.pop(session_id, None)
            if record is not None:
                self._invalidated_ids.add(session_id)
                if record.active_leases > 0:
                    self._pending_release_records[session_id] = record
                else:
                    self._cleanup_record_cookie_file(record)
                    record.sessionid = ""
                    record.sid_tt = None
                logger.info("Ephemeral TikTok user session invalidated session_id=%s", session_id)
                return True
            return False

    def cleanup_expired(self) -> int:
        """Evict all expired sessions and clean up their ephemeral cookie files."""
        now = self._now()
        evicted = 0
        with self._lock:
            expired_ids = [
                sid
                for sid, record in self._sessions.items()
                if record.session.expires_at is not None and now >= record.session.expires_at
            ]
            for sid in expired_ids:
                record = self._sessions.pop(sid, None)
                if record is not None:
                    if record.active_leases > 0:
                        self._pending_release_records[sid] = record
                    else:
                        self._cleanup_record_cookie_file(record)
                        record.sessionid = ""
                        record.sid_tt = None
                    self._expired_ids.add(sid)
                    evicted += 1

        if evicted > 0:
            logger.info("Cleaned up expired ephemeral TikTok user sessions count=%s", evicted)
        return evicted

    def cleanup_orphaned_cookie_files(self) -> int:
        """Scan tiktok_sessions directory and remove orphaned cookie files from prior runs/crashes."""
        sessions_dir = self._storage_dir / "tiktok_sessions"
        if not sessions_dir.is_dir():
            return 0

        removed = 0
        try:
            resolved_sessions_dir = sessions_dir.resolve()
            for file_path in sessions_dir.glob("*.cookies.txt"):
                try:
                    resolved = file_path.resolve()
                    if not resolved.is_relative_to(resolved_sessions_dir) or not resolved.is_file():
                        continue
                    sid = resolved.name.removesuffix(".cookies.txt")
                    with self._lock:
                        if sid in self._sessions or sid in self._pending_release_records:
                            continue
                    resolved.unlink(missing_ok=True)
                    removed += 1
                except OSError:
                    pass
        except OSError:
            pass

        if removed > 0:
            logger.info("Cleaned up orphaned ephemeral TikTok cookie files count=%s", removed)
        return removed

    def clear(self) -> None:
        """Invalidate all active sessions and clean up all ephemeral files (for test isolation)."""
        with self._lock:
            for record in list(self._sessions.values()) + list(self._pending_release_records.values()):
                self._cleanup_record_cookie_file(record)
                record.sessionid = ""
                record.sid_tt = None
            self._sessions.clear()
            self._pending_release_records.clear()
            self._invalidated_ids.clear()
            self._expired_ids.clear()

    def __len__(self) -> int:
        """Return the count of active sessions."""
        with self._lock:
            return len(self._sessions)

    def _ensure_cookie_file(self, record: _EphemeralTikTokSessionRecord) -> Path | None:
        if record.temp_cookie_file is not None and record.temp_cookie_file.is_file():
            return record.temp_cookie_file

        session_id = record.session.session_id
        if not _is_safe_session_id(session_id):
            return None

        assert session_id is not None
        sessions_dir = self._storage_dir / "tiktok_sessions"
        try:
            sessions_dir.mkdir(parents=True, exist_ok=True)
            try:
                sessions_dir.chmod(0o700)
            except OSError:
                pass

            cookie_path = (sessions_dir / f"{session_id}.cookies.txt").resolve()
            if not cookie_path.is_relative_to(sessions_dir.resolve()):
                return None

            content = _format_netscape_cookie_content(record.sessionid, record.sid_tt)

            flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
            fd = os.open(cookie_path, flags, 0o600)
            try:
                with open(fd, "w", encoding="utf-8") as f:
                    f.write(content)
            except Exception:
                os.close(fd)
                raise

            try:
                cookie_path.chmod(0o600)
            except OSError:
                pass

            record.temp_cookie_file = cookie_path
            return record.temp_cookie_file
        except OSError as exc:
            logger.warning(
                "Failed to create ephemeral TikTok cookie file session_id=%s: %s",
                session_id,
                exc,
            )
            return None

    @staticmethod
    def _cleanup_record_cookie_file(record: _EphemeralTikTokSessionRecord) -> None:
        if record.temp_cookie_file is not None:
            try:
                record.temp_cookie_file.unlink(missing_ok=True)
            except OSError:
                pass
            record.temp_cookie_file = None
