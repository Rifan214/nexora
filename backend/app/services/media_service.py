from __future__ import annotations

import logging
import threading
from typing import Any
from uuid import UUID

from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError, ExtractorError, YoutubeDLError

from app.core.config import get_settings
from app.core.exceptions import APIError
from app.models.job import DownloadJob, JobStatus
from app.models.media import AudioOption, MediaMetadata
from app.models.requests import MediaDownloadRequest
from app.services.cleanup_service import get_cleanup_service
from app.services.download_process_manager import (
    DownloadProcessManager,
    get_download_process_manager,
)
from app.services.job_manager import JobManager, build_job_download_url, get_job_manager
from app.services.quality_selector import QualitySelector
from app.utils.platforms import detect_platform_from_url
from app.utils.storage import build_download_outtmpl, find_downloaded_file, get_temp_storage_dir
from app.utils.validators import validate_http_url

logger = logging.getLogger(__name__)

_AUDIO_FORMAT_SELECTOR = "bestaudio/best"
_AUDIO_MP3_POSTPROCESSOR = {
    "key": "FFmpegExtractAudio",
    "preferredcodec": "mp3",
    "preferredquality": "0",
}


class MediaService:
    def __init__(self, *, process_manager: DownloadProcessManager | None = None) -> None:
        self._settings = get_settings()
        self._quality_selector = QualitySelector()
        self._process_manager = process_manager or get_download_process_manager()

    def get_metadata(self, url: str) -> MediaMetadata:
        normalized_url = validate_http_url(url)
        logger.info("Metadata extraction started url=%s", normalized_url)

        try:
            info = self._extract_info_or_raise_api_error(normalized_url)
            platform = self._detect_platform(info)
            if platform != "youtube":
                raise APIError(
                    code="UNSUPPORTED_PLATFORM",
                    message="Unsupported platform",
                    details=f"Platform '{platform}' is not supported in V1",
                    status_code=501,
                )

            metadata = self._build_metadata(info=info, platform=platform, url=normalized_url)
            logger.info("Metadata extraction completed url=%s platform=%s", normalized_url, platform)
            return metadata
        except APIError as exc:
            self._log_failure(normalized_url, exc.message, exc.details)
            raise
        except Exception as exc:
            api_error = APIError(
                code="METADATA_EXTRACTION_ERROR",
                message="Failed to extract media metadata",
                details="An unexpected error occurred while extracting media metadata",
                status_code=500,
            )
            self._log_failure(normalized_url, api_error.message, api_error.details, exc)
            raise api_error from None

    def create_download_job(self, request: MediaDownloadRequest) -> DownloadJob:
        normalized_url = validate_http_url(request.url)
        logger.info(
            "Download job request received url=%s media_type=%s quality_height=%s legacy_format_request=%s",
            normalized_url,
            request.media_type,
            request.quality_height,
            request.format_id is not None,
        )

        try:
            info = self._extract_info_or_raise_api_error(normalized_url)
            platform = self._detect_platform(info)
            if platform != "youtube":
                raise APIError(
                    code="UNSUPPORTED_PLATFORM",
                    message="Unsupported platform",
                    details=f"Platform '{platform}' is not supported in V1",
                    status_code=501,
                )

            formats = info.get("formats") or []
            if request.media_type == "audio":
                if not self._has_audio_available(formats):
                    raise APIError(
                        code="AUDIO_NOT_AVAILABLE",
                        message="Audio unavailable",
                        details="The requested media does not provide an audio stream",
                        status_code=409,
                    )
                format_selector = _AUDIO_FORMAT_SELECTOR
            elif request.quality_height is not None:
                selection = self._quality_selector.select_for_height(
                    formats,
                    request.quality_height,
                )
                if selection is None:
                    raise APIError(
                        code="QUALITY_NOT_AVAILABLE",
                        message="Requested quality unavailable",
                        details="The requested quality is no longer available for this media",
                        status_code=409,
                    )
                format_selector = selection.selector
            else:
                # Deprecated request support for clients released before V1.1.
                format_selector = request.format_id or ""
        except APIError as exc:
            self._log_failure(normalized_url, exc.message, exc.details)
            raise

        job_manager = get_job_manager()
        job = job_manager.create_job(
            media_url=normalized_url,
            platform=platform,
            title=str(info.get("title") or "Untitled media"),
            format_id=format_selector,
            output_type=request.media_type,
        )
        worker = threading.Thread(
            target=self._download_job_background,
            args=(job.job_id, normalized_url, format_selector, request.media_type),
            daemon=True,
            name=f"nexora-download-{job.job_id}",
        )
        self._process_manager.register_job(job.job_id, worker=worker)
        try:
            worker.start()
        except RuntimeError as exc:
            self._process_manager.finish_job(job.job_id)
            self._mark_download_failed(
                job.job_id,
                error_message="Unable to start the download worker",
                job_manager=job_manager,
            )
            raise APIError(
                code="DOWNLOAD_START_ERROR",
                message="Unable to start download",
                details="The backend could not start the download worker",
                status_code=500,
            ) from exc
        return job

    def _download_job_background(
        self,
        job_id: UUID,
        url: str,
        format_selector: str,
        output_type: str,
    ) -> None:
        job_manager = get_job_manager()
        self._process_manager.register_job(job_id, worker=threading.current_thread())

        try:
            self._process_manager.raise_if_cancelled(job_id)
            job_manager.update_progress(job_id, 0)
            initial_platform = detect_platform_from_url(url)
            if initial_platform != "youtube":
                error_message = (
                    f"Platform '{initial_platform}' is not supported in V1"
                )
                self._mark_download_failed(
                    job_id,
                    error_message=error_message,
                    job_manager=job_manager,
                )
                logger.warning(
                    "Download failed job_id=%s error=%s",
                    job_id,
                    error_message,
                )
                return

            self._process_manager.raise_if_cancelled(job_id)
            with self._process_manager.worker_context(job_id):
                extracted_info = self._extract_info(url)
            self._process_manager.raise_if_cancelled(job_id)
            detected_platform = self._detect_platform(extracted_info)
            if detected_platform != "youtube":
                self._mark_download_failed(
                    job_id,
                    error_message=f"Platform '{detected_platform}' is not supported in V1",
                    job_manager=job_manager,
                )
                return

            job_manager.update_job_metadata(
                job_id,
                title=str(extracted_info.get("title") or "Untitled media"),
                platform=detected_platform,
                format_id=format_selector,
                output_type=output_type,
            )
            logger.info("Download started job_id=%s media_type=%s url=%s", job_id, output_type, url)

            temp_dir = get_temp_storage_dir()
            output_template = build_download_outtmpl(job_id, temp_dir=temp_dir)

            ydl_options = self._build_download_options(
                job_id=job_id,
                format_selector=format_selector,
                output_type=output_type,
                output_template=output_template,
                temp_dir=temp_dir,
                job_manager=job_manager,
            )

            with self._process_manager.worker_context(job_id):
                with YoutubeDL(ydl_options) as youtube_dl:
                    self._process_manager.attach_downloader(job_id, youtube_dl)
                    try:
                        downloaded_info = youtube_dl.extract_info(url, download=True)
                    finally:
                        self._process_manager.detach_downloader(job_id, youtube_dl)

            self._process_manager.raise_if_cancelled(job_id)
            if not downloaded_info:
                raise FileNotFoundError("yt-dlp did not return download metadata")

            downloaded_file = find_downloaded_file(job_id, temp_dir=temp_dir)
            if downloaded_file is None or not downloaded_file.is_file():
                raise FileNotFoundError("Downloaded file was not found in storage/temp")

            self._process_manager.raise_if_cancelled(job_id)
            download_url = build_job_download_url(job_id)

            job_manager.mark_completed(job_id, download_url=download_url)
            logger.info("Download completed job_id=%s download_url=%s", job_id, download_url)
        except YoutubeDLError as exc:
            if not self._finalize_cancelled_if_requested(job_id, job_manager=job_manager):
                error_message = self._describe_download_error(exc)
                self._mark_download_failed(job_id, error_message=error_message, job_manager=job_manager)
                logger.warning("Download failed job_id=%s error=%s", job_id, error_message)
        except (OSError, FileNotFoundError, PermissionError) as exc:
            if not self._finalize_cancelled_if_requested(job_id, job_manager=job_manager):
                error_message = f"Filesystem error: {exc}"
                self._mark_download_failed(job_id, error_message=error_message, job_manager=job_manager)
                logger.warning("Download failed job_id=%s error=%s", job_id, error_message)
        except Exception as exc:
            if not self._finalize_cancelled_if_requested(job_id, job_manager=job_manager):
                error_message = "An unexpected error occurred while downloading the media"
                if self._settings.debug:
                    logger.exception("Download failed job_id=%s", job_id)
                else:
                    logger.warning("Download failed job_id=%s error=%s", job_id, error_message)
                self._mark_download_failed(job_id, error_message=error_message, job_manager=job_manager)
        finally:
            self._process_manager.finish_job(job_id)

    def _mark_download_failed(
        self,
        job_id: UUID,
        *,
        error_message: str,
        job_manager: JobManager,
    ) -> None:
        marked_failed = False
        try:
            job_manager.mark_failed(job_id, error_message=error_message)
            marked_failed = True
        except ValueError:
            if self._finalize_cancelled_if_requested(job_id, job_manager=job_manager):
                return
            raise
        finally:
            # Cleanup is deliberately best-effort so a cleanup failure cannot
            # hide the original download error or stop the worker.
            if marked_failed:
                get_cleanup_service().cleanup_failed_download(job_id, job_manager=job_manager)

    def _finalize_cancelled_if_requested(
        self,
        job_id: UUID,
        *,
        job_manager: JobManager,
    ) -> bool:
        job = job_manager.get_job(job_id)
        if job is not None and job.status in {
            JobStatus.completed,
            JobStatus.failed,
            JobStatus.expired,
        }:
            return False

        cancellation_requested = self._process_manager.is_cancellation_requested(job_id) or (
            job is not None and job.status in {JobStatus.cancelling, JobStatus.cancelled}
        )
        if not cancellation_requested:
            return False

        if job is not None and job.status in {JobStatus.pending, JobStatus.processing}:
            job_manager.mark_cancelling(job_id)
        get_cleanup_service().cleanup_cancelled_download(job_id, job_manager=job_manager)
        logger.info("Download cancelled job_id=%s", job_id)
        return True

    def _build_progress_hook(self, job_id, job_manager):
        last_progress = {"value": -1}

        def hook(payload: dict[str, Any]) -> None:
            self._process_manager.raise_if_cancelled(job_id)
            status = payload.get("status")
            if status != "downloading":
                if status == "finished":
                    logger.info("Download file transfer finished job_id=%s", job_id)
                return

            total = payload.get("total_bytes") or payload.get("total_bytes_estimate")
            downloaded = payload.get("downloaded_bytes") or 0
            if total:
                progress = int(min(99, max(0, (downloaded / total) * 100)))
            else:
                progress = min(99, self._parse_percent(payload.get("_percent_str", "0")))

            if progress != last_progress["value"]:
                last_progress["value"] = progress
                try:
                    job_manager.update_progress(job_id, progress)
                    logger.info("Download progress job_id=%s progress=%s", job_id, progress)
                except Exception:
                    return

        return hook

    def _build_postprocessor_hook(self, job_id: UUID):
        def hook(_: dict[str, Any]) -> None:
            self._process_manager.raise_if_cancelled(job_id)

        return hook

    def _build_download_options(
        self,
        *,
        job_id,
        format_selector: str,
        output_type: str,
        output_template: str,
        temp_dir,
        job_manager,
    ) -> dict[str, Any]:
        options: dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "skip_download": False,
            "cachedir": False,
            "format": format_selector,
            "outtmpl": output_template,
            "paths": {"home": str(temp_dir)},
            "progress_hooks": [self._build_progress_hook(job_id, job_manager)],
            "postprocessor_hooks": [self._build_postprocessor_hook(job_id)],
        }
        if output_type == "audio":
            # yt-dlp chooses its best audio stream, then FFmpeg produces a
            # playable MP3 at its highest VBR quality setting.
            options["postprocessors"] = [dict(_AUDIO_MP3_POSTPROCESSOR)]
        return options

    @staticmethod
    def _parse_percent(value: Any) -> int:
        text = str(value).strip().rstrip("%")
        if not text:
            return 0
        try:
            return int(float(text))
        except (TypeError, ValueError):
            return 0

    @staticmethod
    def _describe_download_error(exc: Exception) -> str:
        message = str(exc)
        lowered = message.casefold()

        if any(token in lowered for token in ("http error 403", "forbidden", "access denied")):
            return "The media source rejected the download request"

        if any(token in lowered for token in ("requested format is not available", "format not available", "format unavailable")):
            return "Requested quality is no longer available"
        if any(token in lowered for token in ("ffmpeg is not installed", "ffmpeg not found", "ffmpeg unavailable")):
            return "FFmpeg is required to process this download but is unavailable"
        if any(token in lowered for token in ("cancelled", "canceled")):
            return "Download cancelled"
        if any(token in lowered for token in ("timeout", "timed out", "network", "connection", "http error", "unable to download webpage")):
            return "Network interruption while downloading"
        return "yt-dlp failed to download the media"

    def _extract_info(self, url: str) -> dict[str, Any]:
        ydl_options = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "skip_download": True,
            "cachedir": False,
        }

        with YoutubeDL(ydl_options) as youtube_dl:
            active_job_id = self._process_manager.current_job_id()
            if active_job_id is not None:
                self._process_manager.attach_downloader(active_job_id, youtube_dl)
            try:
                extracted_info = youtube_dl.extract_info(url, download=False)
            finally:
                if active_job_id is not None:
                    self._process_manager.detach_downloader(active_job_id, youtube_dl)

        if not isinstance(extracted_info, dict):
            raise APIError(
                code="METADATA_EXTRACTION_ERROR",
                message="Failed to extract media metadata",
                details="yt-dlp returned an unexpected response",
                status_code=500,
            )

        if extracted_info.get("_type") == "playlist" or extracted_info.get("entries"):
            raise APIError(
                code="PLAYLIST_NOT_SUPPORTED",
                message="Unsupported media type",
                details="Playlists are not supported in this version",
                status_code=501,
            )

        return extracted_info

    def _extract_info_or_raise_api_error(self, url: str) -> dict[str, Any]:
        try:
            return self._extract_info(url)
        except APIError:
            raise
        except (DownloadError, ExtractorError) as exc:
            raise self._map_yt_dlp_error(exc) from None
        except Exception as exc:
            raise APIError(
                code="METADATA_EXTRACTION_ERROR",
                message="Failed to extract media metadata",
                details="An unexpected error occurred while extracting media metadata",
                status_code=500,
            ) from exc

    @staticmethod
    def _detect_platform(info: dict[str, Any]) -> str:
        extractor_key = str(info.get("extractor_key") or info.get("ie_key") or "").casefold()
        extractor_name = str(info.get("extractor") or "").casefold()
        haystack = f"{extractor_key} {extractor_name}".strip()

        if "youtube" in haystack or "youtu" in haystack:
            return "youtube"
        if "tiktok" in haystack:
            return "tiktok"
        if "twitter" in haystack:
            return "twitter"
        if "instagram" in haystack:
            return "instagram"
        if "facebook" in haystack:
            return "facebook"
        if "vimeo" in haystack:
            return "vimeo"
        return "unknown"

    def _build_metadata(self, *, info: dict[str, Any], platform: str, url: str) -> MediaMetadata:
        formats = info.get("formats") or []
        video_qualities = self._quality_selector.build_qualities(formats)
        return MediaMetadata(
            platform=platform,
            title=str(info.get("title") or "Untitled media"),
            uploader=info.get("uploader"),
            uploader_url=info.get("uploader_url"),
            thumbnail_url=self._select_thumbnail(info),
            duration_seconds=self._int_or_none(info.get("duration")),
            webpage_url=str(info.get("webpage_url") or url),
            extractor=str(info.get("extractor") or ""),
            extractor_key=str(info.get("extractor_key") or info.get("ie_key") or ""),
            upload_date=info.get("upload_date"),
            view_count=self._int_or_none(info.get("view_count")),
            like_count=self._int_or_none(info.get("like_count")),
            description=info.get("description"),
            video_qualities=video_qualities,
            audio_options=self._build_audio_options(formats),
        )

    @classmethod
    def _build_audio_options(cls, formats: list[dict[str, Any]]) -> list[AudioOption]:
        if not cls._has_audio_available(formats):
            return []
        return [AudioOption(label="MP3", extension="mp3")]

    @staticmethod
    def _has_audio_available(formats: list[dict[str, Any]]) -> bool:
        for format_item in formats:
            if not isinstance(format_item, dict):
                continue
            audio_codec = str(format_item.get("acodec") or "").strip().casefold()
            if audio_codec and audio_codec != "none":
                return True
        return False

    @staticmethod
    def _select_thumbnail(info: dict[str, Any]) -> str | None:
        thumbnail = info.get("thumbnail")
        if thumbnail:
            return str(thumbnail)

        thumbnails = info.get("thumbnails") or []
        for thumbnail_item in reversed(thumbnails):
            url = thumbnail_item.get("url")
            if url:
                return str(url)

        return None

    @staticmethod
    def _int_or_none(value: Any) -> int | None:
        if value is None:
            return None
        try:
            return int(value)
        except (TypeError, ValueError):
            return None


    @staticmethod
    def _map_yt_dlp_error(exc: Exception) -> APIError:
        message = str(exc)
        lowered = message.casefold()

        if any(token in lowered for token in ("private", "members-only", "sign in")):
            return APIError(
                code="VIDEO_PRIVATE",
                message="Private video",
                details="The requested video is private and cannot be accessed",
                status_code=403,
            )

        if any(token in lowered for token in ("removed", "unavailable", "not available", "not found")):
            return APIError(
                code="VIDEO_UNAVAILABLE",
                message="Video unavailable",
                details="The requested video is unavailable or has been removed",
                status_code=404,
            )

        if any(token in lowered for token in ("timeout", "timed out", "network", "connection", "http error", "unable to download webpage")):
            return APIError(
                code="NETWORK_FAILURE",
                message="Network failure",
                details="Unable to reach the media source",
                status_code=502,
            )

        return APIError(
            code="YTDLP_EXTRACTION_ERROR",
            message="Failed to extract media metadata",
            details="yt-dlp could not extract metadata from the provided URL",
            status_code=500,
        )

    def _log_failure(self, url: str, message: str, details: str, exc: Exception | None = None) -> None:
        if self._settings.debug and exc is not None:
            logger.exception("Metadata extraction failed url=%s message=%s details=%s", url, message, details)
        else:
            logger.warning("Metadata extraction failed url=%s message=%s details=%s", url, message, details)
