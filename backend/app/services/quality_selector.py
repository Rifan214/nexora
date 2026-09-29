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

    def build_qualities(
        self,
        formats: Iterable[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> list[AvailableQuality]:
        return [
            selection.quality
            for selection in self.select_qualities(formats, platform=platform)
        ]

    def has_audio_available(
        self,
        formats: Iterable[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> bool:
        """Return whether yt-dlp exposed a usable standalone or progressive audio stream."""
        return any(
            isinstance(format_item, dict) and self._has_audio(format_item, platform=platform)
            for format_item in formats
        )

    def select_for_height(
        self,
        formats: Iterable[dict[str, Any]],
        height: int,
        *,
        platform: str | None = None,
    ) -> QualitySelection | None:
        for selection in self.select_qualities(formats, platform=platform):
            if selection.quality.height == height:
                return selection
        return None

    def select_qualities(
        self,
        formats: Iterable[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> list[QualitySelection]:
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

        audio_candidates = [item for item in usable_formats if self._is_audio_only(item, platform=platform)]
        best_audio = self._select_best_audio(audio_candidates, platform=platform)
        by_height: dict[int, list[dict[str, Any]]] = {}
        video_candidates: list[dict[str, Any]] = []

        for format_item in usable_formats:
            height = self._quality_height(format_item, platform=platform)
            if height is None:
                logger.debug(
                    "Quality format excluded from video candidates format_id=%s reason=missing_height",
                    self._format_id(format_item),
                )
                continue
            if not self._has_video(format_item, platform=platform):
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
                platform=platform,
            )
            if selection is not None:
                selections.append(selection)

        if not selections and platform == "twitter" and not audio_candidates:
            selections = self._select_x_video_only_qualities(usable_formats)

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

    def _select_x_video_only_qualities(
        self,
        formats: Iterable[dict[str, Any]],
    ) -> list[QualitySelection]:
        """Expose genuine X video-only media without weakening shared rules."""
        by_height: dict[int, list[dict[str, Any]]] = {}
        for format_item in formats:
            if not self._is_x_video_only_candidate(format_item):
                continue
            height = self._quality_height(format_item)
            if height is not None:
                by_height.setdefault(height, []).append(format_item)

        selections: list[QualitySelection] = []
        for height in sorted(by_height):
            selected_video = max(by_height[height], key=self._x_video_only_score)
            selection = self._build_selection(height, selected_video)
            selections.append(selection)
            logger.debug(
                "Quality resolution selected height=%s reason=x_video_only_fallback selector=%s",
                height,
                selection.selector,
            )
        return selections

    def _select_quality_for_height(
        self,
        *,
        height: int,
        video_candidates: list[dict[str, Any]],
        best_audio: dict[str, Any] | None,
        platform: str | None = None,
    ) -> QualitySelection | None:
        progressive = [item for item in video_candidates if self._is_progressive(item, platform=platform)]
        compatible_progressive = [item for item in progressive if self._is_highly_compatible_progressive(item, platform=platform)]

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

        adaptive_video = [item for item in video_candidates if not self._has_audio(item, platform=platform)]
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
    def _select_best_audio(
        cls,
        formats: Iterable[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> dict[str, Any] | None:
        audio_only = [item for item in formats if cls._is_audio_only(item, platform=platform)]
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
    def _is_progressive(cls, format_item: dict[str, Any], *, platform: str | None = None) -> bool:
        return cls._has_video(format_item, platform=platform) and cls._has_audio(format_item, platform=platform)

    @classmethod
    def _is_audio_only(cls, format_item: dict[str, Any], *, platform: str | None = None) -> bool:
        return cls._has_audio(format_item, platform=platform) and not cls._has_video(format_item, platform=platform)

    @classmethod
    def _is_instagram_progressive_candidate(cls, format_item: dict[str, Any]) -> bool:
        """Identify Instagram direct MP4 formats that carry multiplexed audio despite missing acodec metadata."""
        if cls._quality_height(format_item) is None:
            return False
        if not cls._has_codec(format_item.get("vcodec")):
            return False

        # Require HTTP/HTTPS transport
        protocol = str(format_item.get("protocol") or "").casefold()
        if protocol not in {"", "http", "https"}:
            return False

        # Require MP4 container / extension
        ext = str(format_item.get("ext") or "").casefold()
        video_ext = str(format_item.get("video_ext") or "").casefold()
        if ext not in {"", "mp4"} and video_ext not in {"", "mp4"}:
            return False

        # Ensure no explicit indication that stream is video-only
        audio_ext = str(format_item.get("audio_ext") or "").casefold()
        acodec = str(format_item.get("acodec") or "").casefold()
        if audio_ext == "none" and acodec == "none":
            return False

        return True

    @classmethod
    def _is_facebook_progressive_candidate(cls, format_item: dict[str, Any]) -> bool:
        """Identify Facebook direct progressive MP4 formats (sd, hd) that carry multiplexed audio."""
        fmt_id = str(format_item.get("format_id") or "").casefold()
        if fmt_id not in {"sd", "hd", "sd-0", "hd-0", "browser_native_sd", "browser_native_hd"}:
            return False

        # Require HTTP/HTTPS transport
        protocol = str(format_item.get("protocol") or "").casefold()
        if protocol not in {"", "http", "https"}:
            return False

        # Require MP4 container / extension
        ext = str(format_item.get("ext") or "").casefold()
        video_ext = str(format_item.get("video_ext") or "").casefold()
        if ext not in {"", "mp4"} and video_ext not in {"", "mp4"}:
            return False

        # Ensure no explicit indication that stream is video-only
        audio_ext = str(format_item.get("audio_ext") or "").casefold()
        acodec = str(format_item.get("acodec") or "").casefold()
        if audio_ext == "none" or acodec == "none":
            return False

        return True

    @classmethod
    def _is_hanime_multiplexed_candidate(cls, format_item: dict[str, Any]) -> bool:
        """Identify Hanime HLS formats that carry multiplexed video+audio."""
        if cls._quality_height(format_item) is None:
            return False

        protocol = str(format_item.get("protocol") or "").casefold()
        if not protocol.startswith("m3u8"):
            return False

        # Ensure no explicit indication that stream is video-only or audio-only
        vcodec = str(format_item.get("vcodec") or "").casefold()
        acodec = str(format_item.get("acodec") or "").casefold()
        if vcodec == "none" or acodec == "none":
            return False

        return True

    @classmethod
    def _is_x_video_only_candidate(cls, format_item: dict[str, Any]) -> bool:
        if cls._has_audio(format_item) or cls._quality_height(format_item) is None:
            return False
        if cls._has_video(format_item):
            return True

        # X direct MP4 renditions sometimes omit vcodec/acodec even though the
        # transport is a valid video-only stream. Require yt-dlp's explicit
        # video/audio extension markers and direct HTTP transport so malformed
        # or ambiguous formats do not enter the fallback.
        protocol = str(format_item.get("protocol") or "").casefold()
        video_codec = str(format_item.get("vcodec") or "").casefold()
        video_extension = str(format_item.get("video_ext") or "").casefold()
        audio_extension = str(format_item.get("audio_ext") or "").casefold()
        return (
            protocol in {"http", "https"}
            and video_codec == ""
            and video_extension not in {"", "none"}
            and audio_extension in {"", "none"}
        )

    @classmethod
    def _has_video(cls, format_item: dict[str, Any], *, platform: str | None = None) -> bool:
        if QualitySelector._has_codec(format_item.get("vcodec")):
            return True
        if platform == "facebook" and cls._is_facebook_progressive_candidate(format_item):
            return True
        if platform == "hanime" and cls._is_hanime_multiplexed_candidate(format_item):
            return True
        return False

    @classmethod
    def _has_audio(cls, format_item: dict[str, Any], *, platform: str | None = None) -> bool:
        if QualitySelector._has_codec(format_item.get("acodec")):
            return True

        if platform == "instagram" and cls._is_instagram_progressive_candidate(format_item):
            return True

        if platform == "facebook" and cls._is_facebook_progressive_candidate(format_item):
            return True

        if platform == "hanime" and cls._is_hanime_multiplexed_candidate(format_item):
            return True

        # X's HLS master playlists expose audio renditions with an explicit
        # audio extension but no acodec. yt-dlp can pair these renditions with
        # HLS video variants, so treat only this fully specified HLS shape as
        # audio. Do not broaden the rule to arbitrary video-less formats.
        return QualitySelector._is_hls_audio_rendition(format_item)

    @staticmethod
    def _is_hls_audio_rendition(format_item: dict[str, Any]) -> bool:
        protocol = str(format_item.get("protocol") or "").casefold()
        video_codec = str(format_item.get("vcodec") or "").casefold()
        video_extension = str(format_item.get("video_ext") or "").casefold()
        audio_extension = str(format_item.get("audio_ext") or "").casefold()
        return (
            protocol.startswith("m3u8")
            and video_codec == "none"
            and video_extension == "none"
            and audio_extension not in {"", "none"}
        )

    @staticmethod
    def _has_codec(value: Any) -> bool:
        return value not in (None, "", "none", "None")

    @classmethod
    def _quality_height(cls, format_item: dict[str, Any], *, platform: str | None = None) -> int | None:
        height = QualitySelector._int_or_none(format_item.get("height"))
        width = QualitySelector._int_or_none(format_item.get("width"))
        if height is not None and height > 0:
            if width is not None and width > 0:
                return min(width, height)
            return height

        # Conservative fallback for Facebook progressive formats lacking resolution metadata
        if platform == "facebook" and cls._is_facebook_progressive_candidate(format_item):
            fmt_id = str(format_item.get("format_id") or "").casefold()
            if "hd" in fmt_id:
                return 720
            if "sd" in fmt_id:
                return 480

        return None

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
    def _x_video_only_score(
        cls,
        format_item: dict[str, Any],
    ) -> tuple[int, tuple[int, float, float, int, str]]:
        protocol = str(format_item.get("protocol") or "").casefold()
        # Direct files need no HLS processing and match yt-dlp's preferred X
        # fallback when both direct and HLS variants represent one resolution.
        return (1 if protocol in {"http", "https"} else 0, cls._video_score(format_item))

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
    def _is_highly_compatible_progressive(
        cls,
        format_item: dict[str, Any],
        *,
        platform: str | None = None,
    ) -> bool:
        video_codec = str(format_item.get("vcodec") or "").casefold()
        audio_codec = str(format_item.get("acodec") or "").casefold()
        extension = str(format_item.get("ext") or "mp4").casefold()
        is_h264 = "avc" in video_codec or "h264" in video_codec
        if platform == "instagram" and cls._is_instagram_progressive_candidate(format_item) and is_h264:
            return True
        if platform == "facebook" and cls._is_facebook_progressive_candidate(format_item):
            return True
        if platform == "hanime" and cls._is_hanime_multiplexed_candidate(format_item):
            return True
        return extension == "mp4" and is_h264 and (
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
