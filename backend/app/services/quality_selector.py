from __future__ import annotations

from dataclasses import dataclass
import logging
from typing import Any, Iterable

from app.models.media import AvailableQuality

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class QualitySelection:
    """Internal format choice used to create a yt-dlp selector."""

    quality: AvailableQuality
    video_format_id: str
    audio_format_id: str | None = None

    @property
    def selector(self) -> str:
        if self.audio_format_id is None:
            return self.video_format_id
        return f"{self.video_format_id}+{self.audio_format_id}"


class QualitySelector:
    """Turns yt-dlp's raw format inventory into playable video qualities."""

    _QUALITY_LABELS = {
        144: "144p",
        240: "240p",
        360: "360p",
        480: "480p",
        720: "720p HD",
        1080: "1080p Full HD",
        1440: "1440p QHD",
        2160: "2160p 4K",
        4320: "4320p 8K",
    }

    def build_qualities(self, formats: Iterable[dict[str, Any]]) -> list[AvailableQuality]:
        return [selection.quality for selection in self.select_qualities(formats)]

    def select_for_height(
        self,
        formats: Iterable[dict[str, Any]],
        height: int,
    ) -> QualitySelection | None:
        for selection in self.select_qualities(formats):
            if selection.quality.height == height:
                return selection
        return None

    def select_qualities(self, formats: Iterable[dict[str, Any]]) -> list[QualitySelection]:
        raw_formats = list(formats)
        usable_formats: list[dict[str, Any]] = []
        logger.debug("Quality selection started raw_format_count=%s", len(raw_formats))

        for format_item in raw_formats:
            self._log_inspected_format(format_item)
            rejection_reason = self._unusable_reason(format_item)
            if rejection_reason is not None:
                logger.debug(
                    "Quality format rejected format_id=%s reason=%s",
                    self._format_id(format_item) if isinstance(format_item, dict) else None,
                    rejection_reason,
                )
                continue
            usable_formats.append(format_item)

        logger.debug(
            "Quality selection usable_format_count=%s format_ids=%s",
            len(usable_formats),
            [self._format_id(item) for item in usable_formats],
        )

        audio_candidates = [item for item in usable_formats if self._is_audio_only(item)]
        best_audio = self._select_best_audio(audio_candidates)
        by_height: dict[int, list[dict[str, Any]]] = {}
        video_candidates: list[dict[str, Any]] = []

        for format_item in usable_formats:
            height = self._height(format_item)
            if height is None:
                logger.debug(
                    "Quality format excluded from video candidates format_id=%s reason=missing_height",
                    self._format_id(format_item),
                )
                continue
            if not self._has_video(format_item):
                logger.debug(
                    "Quality format excluded from video candidates format_id=%s reason=missing_video_codec",
                    self._format_id(format_item),
                )
                continue
            video_candidates.append(format_item)
            by_height.setdefault(height, []).append(format_item)

        logger.debug(
            "Quality selection video_candidate_count=%s format_ids=%s",
            len(video_candidates),
            [self._format_id(item) for item in video_candidates],
        )
        logger.debug(
            "Quality selection audio_candidate_count=%s format_ids=%s selected_audio_format_id=%s",
            len(audio_candidates),
            [self._format_id(item) for item in audio_candidates],
            self._format_id(best_audio),
        )
        logger.debug(
            "Quality selection grouped_resolutions=%s",
            {height: [self._format_id(item) for item in items] for height, items in by_height.items()},
        )

        selections: list[QualitySelection] = []
        for height in sorted(by_height):
            selection = self._select_quality_for_height(
                height=height,
                video_candidates=by_height[height],
                best_audio=best_audio,
            )
            if selection is not None:
                selections.append(selection)

        logger.debug(
            "Quality selection completed selected_quality_count=%s selected_qualities=%s",
            len(selections),
            [
                {
                    "height": selection.quality.height,
                    "label": selection.quality.label,
                    "selector": selection.selector,
                }
                for selection in selections
            ],
        )
        return selections

    def _select_quality_for_height(
        self,
        *,
        height: int,
        video_candidates: list[dict[str, Any]],
        best_audio: dict[str, Any] | None,
    ) -> QualitySelection | None:
        progressive = [item for item in video_candidates if self._is_progressive(item)]
        compatible_progressive = [item for item in progressive if self._is_highly_compatible_progressive(item)]

        # A progressive H.264/AAC MP4 is deliberately preferred over an AV1/VP9
        # adaptive stream at the same height. It is substantially more compatible
        # and needs no merge. Adaptive streams also prioritize H.264 because it
        # has the broadest decoder support across Android, desktop, and iOS media
        # players. VP9 is the next-best fallback, with AV1 used only when needed.
        if compatible_progressive:
            selection = self._build_selection(height, max(compatible_progressive, key=self._video_score))
            logger.debug(
                "Quality resolution selected height=%s reason=compatible_progressive selector=%s",
                height,
                selection.selector,
            )
            return selection

        adaptive_video = [item for item in video_candidates if not self._has_audio(item)]
        if adaptive_video and best_audio is not None:
            selected_video = max(adaptive_video, key=self._video_score)
            selection = self._build_selection(height, selected_video, best_audio)
            logger.debug(
                "Quality resolution selected height=%s reason=adaptive_video_with_best_audio selector=%s",
                height,
                selection.selector,
            )
            return selection

        if progressive:
            selection = self._build_selection(height, max(progressive, key=self._video_score))
            logger.debug(
                "Quality resolution selected height=%s reason=progressive_fallback selector=%s",
                height,
                selection.selector,
            )
            return selection

        # An adaptive stream without an audio-only companion would create a
        # video-only file, so it is intentionally omitted from the public list.
        logger.debug(
            "Quality resolution rejected height=%s reason=no_playable_audio_pair format_ids=%s",
            height,
            [self._format_id(item) for item in video_candidates],
        )
        return None

    def _build_selection(
        self,
        height: int,
        video: dict[str, Any],
        audio: dict[str, Any] | None = None,
    ) -> QualitySelection:
        video_format_id = self._format_id(video)
        audio_format_id = self._format_id(audio) if audio is not None else None
        estimated_filesize = self._estimated_filesize(video, audio)
        extension = str(video.get("ext") or "mp4").strip().lower() or "mp4"
        quality = AvailableQuality(
            label=self._QUALITY_LABELS.get(height, f"{height}p"),
            height=height,
            extension=extension,
            estimated_filesize=estimated_filesize,
        )
        return QualitySelection(
            quality=quality,
            video_format_id=video_format_id,
            audio_format_id=audio_format_id,
        )

    @classmethod
    def _select_best_audio(cls, formats: Iterable[dict[str, Any]]) -> dict[str, Any] | None:
        audio_only = [item for item in formats if cls._is_audio_only(item)]
        if not audio_only:
            return None
        return max(audio_only, key=cls._audio_score)

    @classmethod
    def _is_usable(cls, format_item: dict[str, Any]) -> bool:
        return cls._unusable_reason(format_item) is None

    @classmethod
    def _unusable_reason(cls, format_item: Any) -> str | None:
        if not isinstance(format_item, dict):
            return "not_a_format_dictionary"
        if not cls._format_id(format_item):
            return "missing_format_id"
        if bool(format_item.get("has_drm")):
            return "drm_protected"
        return None

    @classmethod
    def _is_progressive(cls, format_item: dict[str, Any]) -> bool:
        return cls._has_video(format_item) and cls._has_audio(format_item)

    @classmethod
    def _is_audio_only(cls, format_item: dict[str, Any]) -> bool:
        return cls._has_audio(format_item) and not cls._has_video(format_item)

    @staticmethod
    def _has_video(format_item: dict[str, Any]) -> bool:
        return QualitySelector._has_codec(format_item.get("vcodec"))

    @staticmethod
    def _has_audio(format_item: dict[str, Any]) -> bool:
        return QualitySelector._has_codec(format_item.get("acodec"))

    @staticmethod
    def _has_codec(value: Any) -> bool:
        return value not in (None, "", "none", "None")

    @staticmethod
    def _height(format_item: dict[str, Any]) -> int | None:
        value = QualitySelector._int_or_none(format_item.get("height"))
        return value if value is not None and value > 0 else None

    @staticmethod
    def _format_id(format_item: dict[str, Any] | None) -> str:
        if format_item is None:
            return ""
        return str(format_item.get("format_id") or "").strip()

    @classmethod
    def _log_inspected_format(cls, format_item: Any) -> None:
        if not isinstance(format_item, dict):
            logger.debug(
                "Quality format inspected format_id=%s resolution=%s vcodec=%s acodec=%s ext=%s filesize=%s",
                None,
                None,
                None,
                None,
                None,
                None,
            )
            return

        logger.debug(
            "Quality format inspected format_id=%s resolution=%s vcodec=%s acodec=%s ext=%s filesize=%s",
            cls._format_id(format_item),
            format_item.get("resolution") or format_item.get("height"),
            format_item.get("vcodec"),
            format_item.get("acodec"),
            format_item.get("ext"),
            format_item.get("filesize") or format_item.get("filesize_approx"),
        )

    @classmethod
    def _video_score(cls, format_item: dict[str, Any]) -> tuple[int, float, float, int, str]:
        return (
            cls._video_codec_priority(format_item.get("vcodec")),
            cls._number_or_zero(format_item.get("fps")),
            cls._number_or_zero(format_item.get("tbr")),
            cls._filesize_or_zero(format_item),
            cls._format_id(format_item),
        )

    @classmethod
    def _audio_score(cls, format_item: dict[str, Any]) -> tuple[float, float, int, str]:
        # yt-dlp's bestaudio behavior is quality-first. Approximate that with the
        # reported audio bitrate, then sample rate and size when available.
        return (
            cls._number_or_zero(format_item.get("abr") or format_item.get("tbr")),
            cls._number_or_zero(format_item.get("asr")),
            cls._filesize_or_zero(format_item),
            cls._format_id(format_item),
        )

    @staticmethod
    def _video_codec_priority(value: Any) -> int:
        codec = str(value or "").casefold()
        # Playback compatibility takes precedence over compression efficiency.
        # H.264 is widely hardware-decoded, whereas VP9 and especially AV1 may
        # not be supported by a user's device or installed media player.
        if "avc" in codec or "h264" in codec:
            return 3
        if "vp09" in codec or codec.startswith("vp9"):
            return 2
        if "av01" in codec or codec.startswith("av1"):
            return 1
        return 0

    @classmethod
    def _is_highly_compatible_progressive(cls, format_item: dict[str, Any]) -> bool:
        video_codec = str(format_item.get("vcodec") or "").casefold()
        audio_codec = str(format_item.get("acodec") or "").casefold()
        extension = str(format_item.get("ext") or "").casefold()
        return extension == "mp4" and ("avc" in video_codec or "h264" in video_codec) and (
            "mp4a" in audio_codec or "aac" in audio_codec
        )

    @classmethod
    def _estimated_filesize(cls, video: dict[str, Any], audio: dict[str, Any] | None) -> int | None:
        video_size = cls._filesize(video)
        if audio is None:
            return video_size

        audio_size = cls._filesize(audio)
        if video_size is None or audio_size is None:
            return None
        return video_size + audio_size

    @classmethod
    def _filesize(cls, format_item: dict[str, Any]) -> int | None:
        return cls._int_or_none(format_item.get("filesize") or format_item.get("filesize_approx"))

    @classmethod
    def _filesize_or_zero(cls, format_item: dict[str, Any]) -> int:
        return cls._filesize(format_item) or 0

    @staticmethod
    def _int_or_none(value: Any) -> int | None:
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _number_or_zero(value: Any) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0
