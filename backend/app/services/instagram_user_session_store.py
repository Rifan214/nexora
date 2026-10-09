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

from app.models.instagram_auth import (
    InstagramAuthSession,
    InstagramAuthSource,
    InstagramAuthStatus,
)
from app.utils.storage import get_temp_storage_dir

logger = logging.getLogger("app.services.instagram_user_session_store")

_DEFAULT_SESSION_TTL_SECONDS = 3600  # 1 hour default ephemeral lifetime
_SAFE_SESSION_ID_PATTERN = re.compile(r"^[0-9a-fA-F]{16,64}$")
_SENSITIVE_METADATA_KEYS = {
    "sessionid",
    "ds_user_id",
    "csrftoken",
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


def _format_netscape_cookie_content(
    sessionid: str,
    ds_user_id: str | None = None,
    csrftoken: str | None = None,
) -> str:
    """Format an in-memory Netscape cookie jar string for yt-dlp Instagram extraction."""
    lines = [
        "# Netscape HTTP Cookie File\n",
        f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tsessionid\t{sessionid}\n",
    ]
    if ds_user_id:
        lines.append(f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tds_user_id\t{ds_user_id}\n")
    if csrftoken:
        lines.append(f".instagram.com\tTRUE\t/\tTRUE\t2147483647\tcsrftoken\t{csrftoken}\n")
    return "".join(lines)


@dataclass
class _EphemeralInstagramSessionRecord:
    session: InstagramAuthSession
    sessionid: str
    ds_user_id: str | None = None
    csrftoken: str | None = None
    temp_cookie_file: Path | None = None
    active_leases: int = 0

    def __repr__(self) -> str:
        return (
            f"_EphemeralInstagramSessionRecord(session_id={self.session.session_id!r}, "
            f"has_cookie_file={self.temp_cookie_file is not None}, "
            f"active_leases={self.active_leases})"
        )


class EphemeralInstagramUserSessionStore:
    """Process-local, in-memory ephemeral store for authenticated Instagram user sessions.

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
        self._sessions: dict[str, _EphemeralInstagramSessionRecord] = {}
        self._pending_release_records: dict[str, _EphemeralInstagramSessionRecord] = {}
        self._invalidated_ids: set[str] = set()
        self._expired_ids: set[str] = set()
        self._lock = threading.RLock()

        if cleanup_on_startup:
            self.cleanup_orphaned_cookie_files()

    def create_session(
        self,
        *,
        sessionid: str,
        ds_user_id: str | None = None,
        csrftoken: str | None = None,
        ttl_seconds: int = _DEFAULT_SESSION_TTL_SECONDS,
    ) -> InstagramAuthSession:
        """Register a new ephemeral Instagram session with server-generated session ID."""
        clean_sessionid = sessionid.strip()
        clean_ds_user_id = ds_user_id.strip() if ds_user_id else None
        clean_csrftoken = csrftoken.strip() if csrftoken else None

        if not clean_sessionid:
            raise ValueError("sessionid must not be empty or whitespace")
        if len(clean_sessionid) > 512:
            raise ValueError("sessionid exceeds maximum length of 512 characters")
        if clean_ds_user_id and len(clean_ds_user_id) > 512:
            raise ValueError("ds_user_id exceeds maximum length of 512 characters")
        if clean_csrftoken and len(clean_csrftoken) > 512:
            raise ValueError("csrftoken exceeds maximum length of 512 characters")

        now = self._now()
        expires_at = now + timedelta(seconds=max(1, ttl_seconds))
        session_id = secrets.token_hex(16)

        session = InstagramAuthSession(
            source=InstagramAuthSource.USER_SESSION,
            authenticated=True,
            status=InstagramAuthStatus.AVAILABLE,
            session_id=session_id,
            created_at=now,
            expires_at=expires_at,
            metadata={"source": "user_session"},
        )

        record = _EphemeralInstagramSessionRecord(
            session=session,
            sessionid=clean_sessionid,
            ds_user_id=clean_ds_user_id,
            csrftoken=clean_csrftoken,
        )

        with self._lock:
            self._sessions[session_id] = record
            self._invalidated_ids.discard(session_id)
            self._expired_ids.discard(session_id)

        logger.info(
            "Created ephemeral Instagram session session_id=%s expires_at=%s",
            session_id,
            expires_at.isoformat(),
        )
        return session

    def get_session(self, session_id: str) -> InstagramAuthSession:
        """Lookup session status by ID without exposing sensitive credentials."""
        if not _is_safe_session_id(session_id):
            return InstagramAuthSession(
                source=InstagramAuthSource.USER_SESSION,
                authenticated=False,
                status=InstagramAuthStatus.UNAVAILABLE,
                session_id=session_id,
                metadata={"source": "user_session", "reason": "invalid_session_id_format"},
            )

        with self._lock:
            if session_id in self._invalidated_ids:
                return InstagramAuthSession(
                    source=InstagramAuthSource.USER_SESSION,
                    authenticated=False,
                    status=InstagramAuthStatus.INVALID,
                    session_id=session_id,
                    metadata={"source": "user_session", "reason": "session_revoked"},
                )

            if session_id in self._expired_ids:
                return InstagramAuthSession(
                    source=InstagramAuthSource.USER_SESSION,
                    authenticated=False,
                    status=InstagramAuthStatus.EXPIRED,
                    session_id=session_id,
                    metadata={"source": "user_session", "reason": "session_expired"},
                )

            record = self._sessions.get(session_id)
            if record is None:
                return InstagramAuthSession(
                    source=InstagramAuthSource.USER_SESSION,
                    authenticated=False,
                    status=InstagramAuthStatus.UNAVAILABLE,
                    session_id=session_id,
                    metadata={"source": "user_session", "reason": "session_not_found"},
                )

            if record.session.is_expired(self._now()):
                self._expire_record_locked(session_id, record)
                return InstagramAuthSession(
                    source=InstagramAuthSource.USER_SESSION,
                    authenticated=False,
                    status=InstagramAuthStatus.EXPIRED,
                    session_id=session_id,
                    created_at=record.session.created_at,
                    expires_at=record.session.expires_at,
                    metadata={"source": "user_session", "reason": "session_expired"},
                )

            return record.session

    def has_session(self, session_id: str) -> bool:
        """Check whether a non-expired, available session exists."""
        session = self.get_session(session_id)
        return session.is_available and session.is_authenticated

    def get_cookie_file(self, session_id: str) -> Path | None:
        """Provide an ephemeral Netscape cookie file path for yt-dlp integration."""
        if not _is_safe_session_id(session_id):
            return None

        with self._lock:
            record = self._sessions.get(session_id)
            if record is None or record.session.is_expired(self._now()):
                if record is not None:
                    self._expire_record_locked(session_id, record)
                return None

            if record.temp_cookie_file is not None and record.temp_cookie_file.is_file():
                return record.temp_cookie_file

            file_path = self._create_temp_cookie_file_locked(record)
            record.temp_cookie_file = file_path
            return file_path

    def acquire_session_lease(self, session_id: str) -> Path | None:
        """Acquire an active lease on the session's cookie file.

        Increments lease counter so that sudden invalidation or expiration will not
        delete the underlying cookie file mid-download, preventing race conditions with yt-dlp.
        """
        if not _is_safe_session_id(session_id):
            return None

        with self._lock:
            record = self._sessions.get(session_id)
            if record is None or record.session.is_expired(self._now()):
                if record is not None:
                    self._expire_record_locked(session_id, record)
                return None

            if record.temp_cookie_file is None or not record.temp_cookie_file.is_file():
                record.temp_cookie_file = self._create_temp_cookie_file_locked(record)

            record.active_leases += 1
            logger.debug(
                "Acquired lease for Instagram session session_id=%s active_leases=%d",
                session_id,
                record.active_leases,
            )
            return record.temp_cookie_file

    def release_session_lease(self, session_id: str) -> None:
        """Release a previously acquired lease on the session's cookie file."""
        if not _is_safe_session_id(session_id):
            return

        with self._lock:
            record = self._sessions.get(session_id)
            if record is not None:
                record.active_leases = max(0, record.active_leases - 1)
                logger.debug(
                    "Released lease for Instagram session session_id=%s active_leases=%d",
                    session_id,
                    record.active_leases,
                )
                return

            pending = self._pending_release_records.get(session_id)
            if pending is not None:
                pending.active_leases = max(0, pending.active_leases - 1)
                logger.debug(
                    "Released pending lease for Instagram session session_id=%s remaining=%d",
                    session_id,
                    pending.active_leases,
                )
                if pending.active_leases == 0:
                    self._cleanup_temp_file_locked(pending)
                    self._pending_release_records.pop(session_id, None)

    def invalidate(self, session_id: str) -> None:
        """Explicitly invalidate a session, zeroing credentials and scheduling artifact removal."""
        if not _is_safe_session_id(session_id):
            return

        with self._lock:
            record = self._sessions.pop(session_id, None)
            self._invalidated_ids.add(session_id)

            if record is None:
                return

            # Zero out credentials in memory
            record.sessionid = ""
            record.ds_user_id = None
            record.csrftoken = None
            record.session.status = InstagramAuthStatus.INVALID
            record.session.authenticated = False

            if record.active_leases > 0:
                logger.info(
                    "Session invalidated with %d active lease(s); deferring file deletion session_id=%s",
                    record.active_leases,
                    session_id,
                )
                self._pending_release_records[session_id] = record
            else:
                self._cleanup_temp_file_locked(record)

        logger.info("Invalidated ephemeral Instagram user session session_id=%s", session_id)

    def cleanup_expired_sessions(self) -> int:
        """Scan and purge expired sessions. Returns count of purged sessions."""
        now = self._now()
        purged = 0

        with self._lock:
            expired_keys = [
                s_id for s_id, record in self._sessions.items()
                if record.session.is_expired(now)
            ]
            for s_id in expired_keys:
                record = self._sessions.pop(s_id)
                self._expire_record_locked(s_id, record)
                purged += 1

        if purged > 0:
            logger.info("Purged %d expired Instagram sessions", purged)
        return purged

    def cleanup_orphaned_cookie_files(self) -> int:
        """Remove any leftover temporary Instagram cookie files in the storage directory."""
        purged = 0
        try:
            target_dir = self._storage_dir / "sessions" / "instagram"
            if not target_dir.is_dir():
                return 0

            with self._lock:
                active_files = {
                    rec.temp_cookie_file.resolve()
                    for rec in self._sessions.values()
                    if rec.temp_cookie_file is not None
                }
                active_files.update(
                    rec.temp_cookie_file.resolve()
                    for rec in self._pending_release_records.values()
                    if rec.temp_cookie_file is not None
                )

            for item in target_dir.glob("ig_cookie_*.txt"):
                try:
                    if item.is_file() and item.resolve() not in active_files:
                        item.unlink(missing_ok=True)
                        purged += 1
                except OSError as err:
                    logger.warning("Failed to remove orphaned cookie file %s: %s", item, err)
        except Exception as err:
            logger.warning("Error scanning for orphaned Instagram cookie files: %s", err)

        if purged > 0:
            logger.info("Cleaned up %d orphaned Instagram cookie file(s)", purged)
        return purged

    # -------------------------------------------------------------------------
    # Internal Locked Helpers
    # -------------------------------------------------------------------------

    def _expire_record_locked(self, session_id: str, record: _EphemeralInstagramSessionRecord) -> None:
        self._expired_ids.add(session_id)
        record.sessionid = ""
        record.ds_user_id = None
        record.csrftoken = None
        record.session.status = InstagramAuthStatus.EXPIRED
        record.session.authenticated = False

        if record.active_leases > 0:
            self._pending_release_records[session_id] = record
        else:
            self._cleanup_temp_file_locked(record)

    def _create_temp_cookie_file_locked(self, record: _EphemeralInstagramSessionRecord) -> Path:
        target_dir = self._storage_dir / "sessions" / "instagram"
        target_dir.mkdir(parents=True, exist_ok=True)

        if os.name != "nt":
            try:
                os.chmod(target_dir, 0o700)
            except OSError:
                pass

        session_id = record.session.session_id or secrets.token_hex(8)
        file_path = target_dir / f"ig_cookie_{session_id}.txt"

        self._validate_session_path_containment(file_path, target_dir)

        cookie_content = _format_netscape_cookie_content(
            record.sessionid,
            ds_user_id=record.ds_user_id,
            csrftoken=record.csrftoken,
        )

        flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
        mode = 0o600

        fd = os.open(str(file_path), flags, mode)
        try:
            with open(fd, "w", encoding="utf-8", closefd=True) as f:
                f.write(cookie_content)
        except Exception:
            try:
                os.close(fd)
            except OSError:
                pass
            raise

        if os.name != "nt":
            try:
                os.chmod(file_path, 0o600)
            except OSError:
                pass

        return file_path

    def _cleanup_temp_file_locked(self, record: _EphemeralInstagramSessionRecord) -> None:
        if record.temp_cookie_file is not None:
            try:
                record.temp_cookie_file.unlink(missing_ok=True)
            except OSError as err:
                logger.warning(
                    "Failed to delete temp Instagram cookie file %s: %s",
                    record.temp_cookie_file,
                    err,
                )
            finally:
                record.temp_cookie_file = None

    def _validate_session_path_containment(self, candidate_path: Path, allowed_root: Path) -> None:
        try:
            resolved_candidate = candidate_path.resolve()
            resolved_root = allowed_root.resolve()
            resolved_candidate.relative_to(resolved_root)
        except (ValueError, RuntimeError) as err:
            raise SecurityError(
                f"Path traversal detected: {candidate_path} is outside {allowed_root}"
            ) from err


class SecurityError(Exception):
    """Raised when an internal security invariant (e.g., path containment) is violated."""
