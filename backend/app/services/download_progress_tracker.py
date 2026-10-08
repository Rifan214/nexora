from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)


class DownloadProgressTracker:
    """Tracks and aggregates progress across one or more download streams.

    Prevents two major download progress regressions:
    1. HLS variable-bitrate (VBR) estimated total size fluctuations causing
       calculated progress to jump backwards within a stream (e.g. 40.5% -> 37.4% -> 41.9%).
    2. Multi-format downloads (video + audio, e.g. YouTube 312+234) where video
       completes at 99% and audio starts from a lower percentage (e.g. 0% or 6%),
       preventing progress from getting stuck at 99% or resetting backwards to 0%.
    """

    def __init__(self, format_selector: str = "") -> None:
        self._format_selector = format_selector or ""
        self._expected_streams = self._determine_expected_streams(self._format_selector)
        self._current_stream_index = 0
        self._current_stream_key: str | None = None
        self._stream_finished = False
        self._stream_max_progress: dict[int, float] = {}
        self._overall_max_progress = 0

    @staticmethod
    def _determine_expected_streams(format_selector: str) -> int:
        if not format_selector:
            return 1
        primary_selector = format_selector.split("/")[0].strip()
        if "+" in primary_selector:
            parts = [p.strip() for p in primary_selector.split("+") if p.strip()]
            return max(1, len(parts))
        return 1

    @property
    def expected_streams(self) -> int:
        return self._expected_streams

    @property
    def current_stream_index(self) -> int:
        return self._current_stream_index

    def get_stream_progress(self, stream_index: int) -> float:
        """Return the maximum recorded progress (0.0 to 100.0) for a specific stream."""
        return self._stream_max_progress.get(stream_index, 0.0)

    def update_stream_progress(self, stream_index: int, percent: float) -> int:
        """Directly update progress for a given stream index and return overall progress."""
        clamped_percent = max(0.0, min(100.0, float(percent)))
        prev = self._stream_max_progress.get(stream_index, 0.0)
        self._stream_max_progress[stream_index] = max(prev, clamped_percent)
        return self.get_overall_progress()

    @classmethod
    def _is_initialization_artifact(cls, payload: dict[str, Any], raw_pct: float) -> bool:
        """Detect yt-dlp FragmentFD initialization fragment artifact.

        During HLS downloads, FragmentFD downloads the initialization segment (frag 0/N, #EXT-X-MAP)
        where total_bytes_estimate temporarily equals downloaded_bytes (~1KiB), producing a false
        100.0% raw progress during 'downloading' status.
        This must be treated as a provisional initialization estimate artifact, not stream completion.
        """
        fragment_count = payload.get("fragment_count")
        if fragment_count is None and isinstance(payload.get("info_dict"), dict):
            fragment_count = payload["info_dict"].get("fragment_count")

        fragment_index = payload.get("fragment_index")
        if fragment_index is None and isinstance(payload.get("info_dict"), dict):
            fragment_index = payload["info_dict"].get("fragment_index")

        total_bytes_estimate = payload.get("total_bytes_estimate")
        downloaded_bytes = payload.get("downloaded_bytes")

        try:
            frag_count_val = int(fragment_count) if fragment_count is not None else None
        except (ValueError, TypeError):
            frag_count_val = None

        try:
            frag_idx_val = int(fragment_index) if fragment_index is not None else None
        except (ValueError, TypeError):
            frag_idx_val = None

        try:
            total_est_val = int(total_bytes_estimate) if total_bytes_estimate is not None else None
        except (ValueError, TypeError):
            total_est_val = None

        try:
            dl_bytes_val = int(downloaded_bytes) if downloaded_bytes is not None else None
        except (ValueError, TypeError):
            dl_bytes_val = None

        if (
            frag_count_val is not None
            and frag_count_val > 1
            and frag_idx_val is not None
            and frag_idx_val == 0
        ):
            if raw_pct >= 99.0:
                return True
            if (
                total_est_val is not None
                and dl_bytes_val is not None
                and dl_bytes_val >= total_est_val
            ):
                return True

        return False

    def update_from_payload(self, payload: dict[str, Any]) -> int:
        """Process a yt-dlp progress hook payload and return the aggregated overall progress [0..99]."""
        status = payload.get("status")
        stream_key = (
            payload.get("filename")
            or (payload.get("info_dict") or {}).get("format_id")
        )

        if status == "finished":
            self._stream_max_progress[self._current_stream_index] = 100.0
            self._stream_finished = True
            return self.get_overall_progress()

        if status != "downloading":
            return self.get_overall_progress()

        if self._stream_finished:
            self._current_stream_index += 1
            self._stream_finished = False
            self._current_stream_key = stream_key
        elif (
            self._current_stream_key is not None
            and stream_key is not None
            and stream_key != self._current_stream_key
        ):
            self._stream_max_progress[self._current_stream_index] = 100.0
            self._current_stream_index += 1
            self._current_stream_key = stream_key
        elif self._current_stream_key is None and stream_key is not None:
            self._current_stream_key = stream_key

        raw_pct = self._extract_percent(payload)

        # Detect provisional initialization fragment artifact (e.g. frag 0/43 reporting 100% of ~1KiB)
        # to prevent locking the stream to 100% or prematurely jumping overall progress to 85%.
        if self._is_initialization_artifact(payload, raw_pct):
            logger.debug(
                "Detected HLS initialization estimate artifact on fragment 0/%s (raw_pct=%.2f%%); treating as 0%%",
                payload.get("fragment_count"),
                raw_pct,
            )
            raw_pct = 0.0

        # Monotonic clamp within current stream: prevents backwards movement due to
        # HLS VBR total_bytes_estimate fluctuating across fragments.
        prev_stream_pct = self._stream_max_progress.get(self._current_stream_index, 0.0)
        clamped_stream_pct = max(prev_stream_pct, raw_pct)
        self._stream_max_progress[self._current_stream_index] = clamped_stream_pct

        return self.get_overall_progress()

    def get_overall_progress(self) -> int:
        """Compute the weighted aggregated overall progress [0..99], monotonically clamped."""
        total_streams = max(self._expected_streams, self._current_stream_index + 1)

        if total_streams <= 1:
            raw_overall = self._stream_max_progress.get(0, 0.0)
            overall = int(min(99, raw_overall))
        elif total_streams == 2:
            # Stream 0 (Video) contributes 0..85% of total download
            # Stream 1 (Audio) contributes 85..99% of total download (span 14%)
            s0 = self._stream_max_progress.get(0, 0.0)
            s1 = self._stream_max_progress.get(1, 0.0)
            contrib_0 = (s0 / 100.0) * 85.0
            contrib_1 = (s1 / 100.0) * 14.0
            overall = int(min(99, contrib_0 + contrib_1))
        else:
            slice_size = 99.0 / total_streams
            overall = int(
                min(
                    99,
                    sum(
                        (self._stream_max_progress.get(i, 0.0) / 100.0) * slice_size
                        for i in range(total_streams)
                    ),
                )
            )

        self._overall_max_progress = max(self._overall_max_progress, overall)
        return self._overall_max_progress

    @staticmethod
    def _extract_percent(payload: dict[str, Any]) -> float:
        total = payload.get("total_bytes") or payload.get("total_bytes_estimate")
        downloaded = payload.get("downloaded_bytes") or 0
        if total and total > 0:
            return max(0.0, min(100.0, (downloaded / total) * 100.0))
        if "_percent" in payload and payload["_percent"] is not None:
            return max(0.0, min(100.0, float(payload["_percent"])))
        pct_str = str(payload.get("_percent_str", "0")).strip().rstrip("%")
        try:
            return max(0.0, min(100.0, float(pct_str)))
        except (ValueError, TypeError):
            return 0.0
