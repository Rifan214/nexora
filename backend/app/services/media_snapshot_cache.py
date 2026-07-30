from __future__ import annotations

from collections import OrderedDict
from copy import deepcopy
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from threading import RLock
from typing import Any, Callable


@dataclass(frozen=True)
class MediaSnapshot:
    """A reusable yt-dlp extraction result keyed by its normalized source URL."""

    extracted_info: dict[str, Any]
    created_at: datetime
    expires_at: datetime


class MediaSnapshotCache:
    """A small in-memory LRU cache for recently analyzed media."""

    def __init__(
        self,
        *,
        capacity: int = 32,
        ttl_seconds: int = 300,
        now: Callable[[], datetime] | None = None,
    ) -> None:
        if capacity < 1:
            raise ValueError("capacity must be at least one")
        if ttl_seconds < 1:
            raise ValueError("ttl_seconds must be at least one")

        self._capacity = capacity
        self._ttl = timedelta(seconds=ttl_seconds)
        self._now = now or _utcnow
        self._entries: OrderedDict[str, MediaSnapshot] = OrderedDict()
        self._lock = RLock()

    def get(self, normalized_url: str) -> MediaSnapshot | None:
        """Return a defensive copy of an unexpired snapshot, if one exists."""
        with self._lock:
            self._evict_expired_locked()
            snapshot = self._entries.get(normalized_url)
            if snapshot is None:
                return None
            self._entries.move_to_end(normalized_url)
            return _copy_snapshot(snapshot)

    def put(self, normalized_url: str, extracted_info: dict[str, Any]) -> MediaSnapshot:
        """Store an extraction result and evict the least recently used entry if needed."""
        now = self._now()
        snapshot = MediaSnapshot(
            extracted_info=deepcopy(extracted_info),
            created_at=now,
            expires_at=now + self._ttl,
        )
        with self._lock:
            self._evict_expired_locked(now=now)
            self._entries[normalized_url] = snapshot
            self._entries.move_to_end(normalized_url)
            while len(self._entries) > self._capacity:
                self._entries.popitem(last=False)
        return _copy_snapshot(snapshot)

    def __len__(self) -> int:
        with self._lock:
            self._evict_expired_locked()
            return len(self._entries)

    def _evict_expired_locked(self, *, now: datetime | None = None) -> None:
        current_time = now or self._now()
        expired_keys = [
            key
            for key, snapshot in self._entries.items()
            if snapshot.expires_at <= current_time
        ]
        for key in expired_keys:
            self._entries.pop(key, None)


def _utcnow() -> datetime:
    return datetime.now(UTC)


def _copy_snapshot(snapshot: MediaSnapshot) -> MediaSnapshot:
    return MediaSnapshot(
        extracted_info=deepcopy(snapshot.extracted_info),
        created_at=snapshot.created_at,
        expires_at=snapshot.expires_at,
    )
