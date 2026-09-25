from __future__ import annotations

import logging
import random
import re
import threading
import time
from contextlib import contextmanager
from copy import deepcopy
from dataclasses import dataclass, field
from http.cookiejar import LoadError, MozillaCookieJar
from pathlib import Path
from typing import Any, Callable, Iterator
from urllib.parse import parse_qs, quote, urlencode, urlsplit, urlunsplit
from uuid import UUID

from yt_dlp import YoutubeDL
from yt_dlp.utils import DownloadError, ExtractorError, YoutubeDLError

from app.core.config import get_settings
from app.core.exceptions import APIError
from app.models.job import DownloadJob, JobStatus
from app.models.media import AudioOption, MediaMetadata, PlaylistItem, PlaylistMetadata
from app.models.requests import MediaDownloadRequest
from app.services.cleanup_service import get_cleanup_service
from app.services.download_process_manager import (
    DownloadProcessManager,
    get_download_process_manager,
)
from app.services.download_metadata_diagnostics import build_download_metadata_diagnostic_report
from app.services.job_manager import JobManager, build_job_download_url, get_job_manager
from app.services.media_snapshot_cache import MediaSnapshotCache
from app.services.queue_manager import QueueManager, get_queue_manager
from app.services.resume_state_manager import ResumeStateManager, get_resume_state_manager
from app.services.quality_selector import QualitySelector
from app.models.resume_state import ResumeState
from app.models.x_auth import XAuthSource
from app.services.x_auth_manager import XAuthManager
from app.utils.platforms import (
    detect_platform_from_url,
    is_facebook_media_url,
    is_instagram_media_url,
    is_reddit_media_url,
    is_x_status_url,
    normalize_media_url,
)
from app.utils.storage import build_download_outtmpl, find_downloaded_file, get_temp_storage_dir
from app.utils.validators import validate_http_url

logger = logging.getLogger(__name__)

_AUDIO_FORMAT_SELECTOR = "bestaudio/best"
_AUDIO_MP3_POSTPROCESSOR = {
    "key": "FFmpegExtractAudio",
    "preferredcodec": "mp3",
    "preferredquality": "0",
}
_SUPPORTED_MEDIA_PLATFORMS = frozenset({"youtube", "tiktok", "twitter", "instagram", "facebook", "reddit"})
_PLATFORMS_REQUIRING_TRANSPORT_REFRESH = frozenset({"youtube", "twitter", "instagram", "facebook", "reddit"})
_X_AUTHENTICATED_RETRY_ERROR_CODES = frozenset(
    {
        "X_MEDIA_NOT_AVAILABLE",
        "X_EXTRACTION_UNAVAILABLE",
        "VIDEO_PRIVATE",
    }
)
_X_MEDIA_NOT_AVAILABLE_MESSAGE = (
    "Unable to access downloadable media from this X post. "
    "The post may be restricted, require login, or temporarily unavailable."
)
_INSTAGRAM_AUTHENTICATED_RETRY_ERROR_CODES = frozenset(
    {
        "INSTAGRAM_MEDIA_NOT_AVAILABLE",
        "INSTAGRAM_EXTRACTION_UNAVAILABLE",
        "VIDEO_PRIVATE",
    }
)
_INSTAGRAM_MEDIA_NOT_AVAILABLE_MESSAGE = (
    "Unable to access downloadable media from this Instagram post. "
    "The post may be restricted, require login, or temporarily unavailable."
)
_FACEBOOK_AUTHENTICATED_RETRY_ERROR_CODES = frozenset(
    {
        "FACEBOOK_MEDIA_NOT_AVAILABLE",
        "FACEBOOK_EXTRACTION_UNAVAILABLE",
        "VIDEO_PRIVATE",
    }
)
_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE = (
    "Unable to access downloadable media from this Facebook post. "
    "The post may be restricted, require login, or temporarily unavailable."
)
_REDDIT_AUTHENTICATED_RETRY_ERROR_CODES = frozenset(
    {
        "REDDIT_MEDIA_NOT_AVAILABLE",
        "REDDIT_EXTRACTION_UNAVAILABLE",
        "VIDEO_PRIVATE",
    }
)
_REDDIT_MEDIA_NOT_AVAILABLE_MESSAGE = (
    "Unable to access downloadable media from this Reddit post. "
    "The post may be restricted, require login, or temporarily unavailable."
)
_YOUTUBE_MIX_SEED_PATTERN = re.compile(r"^RD(?P<seed>[A-Za-z0-9_-]{11})$")
_YOUTUBE_MIX_FAILURE_MARKERS = (
    "playlist type is unviewable",
    "channel/playlist does not exist and the url redirected to youtube.com home page",
)
_YOUTUBE_MIX_UNAVAILABLE_MESSAGE = (
    "This YouTube Mix could not be resolved. Open the Mix and copy its watch URL."
)
_TIKTOK_RETRY_DELAYS_SECONDS = (0.25, 0.5, 1.0)
_TIKTOK_MAX_EXTRACTION_ATTEMPTS = len(_TIKTOK_RETRY_DELAYS_SECONDS) + 1
_TIKTOK_TRANSIENT_EXTRACTION_MARKERS = (
    "unable to extract universal data for rehydration",
    "unexpected response from webpage request",
    "unable to extract challenge data",
    "incomplete rehydration",
    "timed out",
    "timeout",
)
_TIKTOK_PERMANENT_EXTRACTION_MARKERS = (
    "private",
    "login required",
    "requiring login",
    "sign in",
    "removed",
    "not available",
    "not found",
    "permission to view",
    "ip address is blocked",
)
_DOWNLOAD_TRANSPORT_FIELDS = frozenset(
    {
        "formats",
        "url",
        "http_headers",
        "cookies",
        "protocol",
        "manifest_url",
        "fragments",
        "__x_forwarded_for_ip",
        "_format_sort_fields",
        "id",
        "extractor",
        "extractor_key",
        "webpage_url",
        "original_url",
    }
)
_PROCESSED_DOWNLOAD_FIELDS = frozenset(
    {
        "requested_formats",
        "requested_downloads",
        "__real_download",
        "_filename",
        "filepath",
        "__files_to_move",
        "__finaldir",
    }
)
_AUTHENTICATED_SNAPSHOT_SENSITIVE_KEYS = frozenset(
    {
        "authorization",
        "auth_token",
        "c_user",
        "cookie",
        "cookies",
        "csrftoken",
        "csv",
        "ct0",
        "datr",
        "ds_user_id",
        "edgebucket",
        "fr",
        "ig_did",
        "loid",
        "mid",
        "presence",
        "proxy-authorization",
        "reddit_session",
        "rur",
        "sb",
        "session_tracker",
        "sessionid",
        "set-cookie",
        "token_v2",
        "wd",
        "x-csrf-token",
        "xs",
    }
)


def _payload_path(value: Any) -> str | None:
    return str(value) if isinstance(value, (str, Path)) and value else None


@dataclass
class _MetadataExtractionGate:
    lock: threading.Lock = field(default_factory=threading.Lock)
    users: int = 0


class MediaService:
    def __init__(
        self,
        *,
        process_manager: DownloadProcessManager | None = None,
        job_manager: JobManager | None = None,
        queue_manager: QueueManager | None = None,
        snapshot_cache: MediaSnapshotCache | None = None,
        resume_state_manager: ResumeStateManager | None = None,
        sleep: Callable[[float], None] | None = None,
        retry_jitter: Callable[[float, float], float] | None = None,
        x_auth_manager: XAuthManager | None = None,
    ) -> None:
        self._settings = get_settings()
        self._x_auth_manager = x_auth_manager or XAuthManager(
            service_account_cookie_file=lambda: self._settings.x_auth_cookie_file
        )
        self._quality_selector = QualitySelector()
        self._process_manager = process_manager or get_download_process_manager()
        self._job_manager = job_manager
        self._queue_manager = queue_manager
        self._snapshot_cache = snapshot_cache if snapshot_cache is not None else MediaSnapshotCache()
        self._resume_state_manager = resume_state_manager or get_resume_state_manager()
        self._sleep = sleep or time.sleep
        self._retry_jitter = retry_jitter or random.uniform
        self._metadata_extraction_gates: dict[str, _MetadataExtractionGate] = {}
        self._metadata_extraction_gates_lock = threading.RLock()

    @property
    def x_auth_manager(self) -> XAuthManager:
        return self._x_auth_manager

    def get_metadata(
        self,
        url: str,
        *,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> MediaMetadata:
        normalized_url = self._normalize_source_url(url)
        logger.info("Metadata extraction started url=%s", normalized_url)

        try:
            info, platform, _, source_url = self._get_or_extract_supported_info(
                normalized_url,
                auth_source=auth_source,
                auth_session_id=auth_session_id,
            )

            metadata = self._build_metadata(info=info, platform=platform, url=source_url)
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

    def get_playlist_metadata(self, url: str) -> PlaylistMetadata:
        """Extract a flat playlist preview without resolving item formats."""
        normalized_url = validate_http_url(url)
        logger.info("Playlist metadata extraction started url=%s", normalized_url)

        try:
            if detect_platform_from_url(normalized_url) == "tiktok":
                raise APIError(
                    code="TIKTOK_PLAYLIST_NOT_SUPPORTED",
                    message="TikTok playlist import is unavailable",
                    details="TikTok playlist import is not supported. Paste individual TikTok video URLs instead.",
                    status_code=501,
                )
            info, _ = self._extract_playlist_info_with_youtube_mix_fallback(normalized_url)
            platform = self._detect_platform(info)
            if platform == "tiktok":
                raise APIError(
                    code="TIKTOK_PLAYLIST_NOT_SUPPORTED",
                    message="TikTok playlist import is unavailable",
                    details="TikTok playlist import is not supported. Paste individual TikTok video URLs instead.",
                    status_code=501,
                )
            self._ensure_supported_media_platform(platform)

            items = self._build_playlist_items(info)
            metadata = PlaylistMetadata(
                title=str(info.get("title") or "Untitled playlist"),
                total_count=len(items),
                items=items,
            )
            logger.info(
                "Playlist metadata extraction completed url=%s item_count=%s",
                normalized_url,
                metadata.total_count,
            )
            return metadata
        except APIError as exc:
            self._log_failure(normalized_url, exc.message, exc.details)
            raise
        except Exception as exc:
            api_error = APIError(
                code="PLAYLIST_EXTRACTION_ERROR",
                message="Failed to extract playlist metadata",
                details="An unexpected error occurred while extracting playlist metadata",
                status_code=500,
            )
            self._log_failure(normalized_url, api_error.message, api_error.details, exc)
            raise api_error from None

    def create_download_job(
        self,
        request: MediaDownloadRequest,
        *,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> DownloadJob:
        normalized_url = self._normalize_source_url(request.url)
        logger.info(
            "Download job request received url=%s media_type=%s quality_height=%s legacy_format_request=%s",
            normalized_url,
            request.media_type,
            request.quality_height,
            request.format_id is not None,
        )

        try:
            info, platform, authenticated, source_url = self._get_or_extract_supported_info(
                normalized_url,
                auth_source=auth_source,
                auth_session_id=auth_session_id,
            )

            formats = info.get("formats") or []
            if request.media_type == "audio":
                if not self._has_audio_available(formats, platform=platform):
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
                    platform=platform,
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

        job_manager = self._get_job_manager()
        job = job_manager.create_job(
            media_url=source_url,
            platform=platform,
            title=str(info.get("title") or "Untitled media"),
            format_id=format_selector,
            output_type=request.media_type,
        )
        snapshot = self._snapshot_cache.get(normalized_url, session_id=auth_session_id)
        if snapshot is None:
            snapshot = self._snapshot_cache.get(normalized_url)
        resolved_auth_source = snapshot.auth_source if snapshot else auth_source
        resolved_auth_session_id = snapshot.session_id if snapshot else auth_session_id

        self._get_queue_manager().enqueue(
            job.job_id,
            starter=lambda: self._start_download_worker(
                job_id=job.job_id,
                url=source_url,
                format_selector=format_selector,
                output_type=request.media_type,
                download_info=deepcopy(info),
                authenticated=authenticated,
                auth_source=resolved_auth_source,
                auth_session_id=resolved_auth_session_id,
            ),
        )
        return job

    def _start_download_worker(
        self,
        *,
        job_id: UUID,
        url: str,
        format_selector: str,
        output_type: str,
        download_info: dict[str, Any] | None = None,
        authenticated: bool = False,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> None:
        worker = threading.Thread(
            target=self._download_job_background,
            args=(
                job_id,
                url,
                format_selector,
                output_type,
                download_info,
                authenticated,
                auth_source,
                auth_session_id,
            ),
            daemon=True,
            name=f"nexora-download-{job_id}",
        )
        self._process_manager.register_job(job_id, worker=worker)
        try:
            worker.start()
        except RuntimeError:
            self._process_manager.finish_job(job_id)
            raise

    def _download_job_background(
        self,
        job_id: UUID,
        url: str,
        format_selector: str,
        output_type: str,
        download_info: dict[str, Any] | None = None,
        authenticated: bool = False,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> None:
        job_manager = self._get_job_manager()
        self._process_manager.register_job(job_id, worker=threading.current_thread())

        session_lease_acquired = False
        try:
            self._process_manager.raise_if_cancelled(job_id)
            job_manager.update_progress(job_id, 0)
            initial_platform = detect_platform_from_url(url)
            if initial_platform not in _SUPPORTED_MEDIA_PLATFORMS:
                error_message = "This media platform is not supported."
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
            auth_cookie_file = (
                self._require_auth_cookie_file(
                    initial_platform,
                    source=auth_source,
                    session_id=auth_session_id,
                )
                if authenticated
                else None
            )
            if auth_cookie_file is not None and initial_platform == "twitter":
                self._x_auth_manager.acquire_session_lease(
                    source=auth_source,
                    session_id=auth_session_id,
                )
                session_lease_acquired = True
            if download_info is not None:
                extracted_info = download_info
            else:
                with self._process_manager.worker_context(job_id):
                    extracted_info = (
                        self._extract_info(url, cookie_file=auth_cookie_file)
                        if auth_cookie_file is not None
                        else self._extract_info(url)
                    )
            self._process_manager.raise_if_cancelled(job_id)
            detected_platform = self._detect_platform(extracted_info)
            if detected_platform not in _SUPPORTED_MEDIA_PLATFORMS:
                self._mark_download_failed(
                    job_id,
                    error_message="This media platform is not supported.",
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
            resume_state = self._prepare_resume_state(
                job_id=job_id,
                source_url=url,
                output_template=output_template,
                temp_dir=temp_dir,
            )
            if resume_state is None:
                self._create_resume_state(
                    job_id=job_id,
                    source_url=url,
                    output_template=output_template,
                    format_selector=format_selector,
                    extractor=str(extracted_info.get("extractor_key") or detected_platform),
                )

            ydl_options = self._build_download_options(
                job_id=job_id,
                format_selector=format_selector,
                output_type=output_type,
                output_template=output_template,
                temp_dir=temp_dir,
                job_manager=job_manager,
                resume_state_manager=self._resume_state_manager,
                continue_download=resume_state is not None,
                cookie_file=auth_cookie_file,
            )

            with self._process_manager.worker_context(job_id):
                with YoutubeDL(ydl_options) as youtube_dl:
                    self._process_manager.attach_downloader(job_id, youtube_dl)
                    try:
                        downloaded_info = self._process_download_with_youtube_dl(
                            youtube_dl,
                            job_id=job_id,
                            url=url,
                            output_type=output_type,
                            format_selector=format_selector,
                            download_info=download_info,
                            detected_platform=detected_platform,
                        )
                    except YoutubeDLError:
                        if resume_state is None:
                            raise
                        logger.debug("Resume failed; falling back to full download job_id=%s", job_id)
                        self._invalidate_resume_state(job_id, temp_dir=temp_dir)
                        self._create_resume_state(
                            job_id=job_id,
                            source_url=url,
                            output_template=output_template,
                            format_selector=format_selector,
                            extractor=str(extracted_info.get("extractor_key") or detected_platform),
                        )
                        fallback_options = self._build_download_options(
                            job_id=job_id,
                            format_selector=format_selector,
                            output_type=output_type,
                            output_template=output_template,
                            temp_dir=temp_dir,
                            job_manager=job_manager,
                            resume_state_manager=self._resume_state_manager,
                            continue_download=False,
                            cookie_file=auth_cookie_file,
                        )
                        with YoutubeDL(fallback_options) as fallback_youtube_dl:
                            self._process_manager.attach_downloader(job_id, fallback_youtube_dl)
                            try:
                                downloaded_info = self._process_download_with_youtube_dl(
                                    fallback_youtube_dl,
                                    job_id=job_id,
                                    url=url,
                                    output_type=output_type,
                                    format_selector=format_selector,
                                    download_info=download_info,
                                    detected_platform=detected_platform,
                                )
                            finally:
                                self._process_manager.detach_downloader(job_id, fallback_youtube_dl)
                        logger.debug("Full download fallback completed job_id=%s", job_id)
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
            self._delete_resume_state(job_id)
            if resume_state is not None:
                logger.debug("Resume completed successfully job_id=%s", job_id)
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
            if session_lease_acquired:
                self._x_auth_manager.release_session_lease(
                    source=auth_source,
                    session_id=auth_session_id,
                )
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

    def _get_job_manager(self) -> JobManager:
        return self._job_manager or get_job_manager()

    def _get_queue_manager(self) -> QueueManager:
        return self._queue_manager or get_queue_manager()

    def _create_resume_state(
        self,
        *,
        job_id: UUID,
        source_url: str,
        output_template: str,
        format_selector: str,
        extractor: str,
    ) -> None:
        try:
            self._resume_state_manager.save(
                ResumeState(
                    job_id=job_id,
                    source_url=source_url,
                    output_path=output_template,
                    temporary_file_path=f"{output_template}.part",
                    media_format=format_selector,
                    extractor=extractor,
                )
            )
        except (OSError, ValueError):
            logger.exception("Resume state creation failed job_id=%s", job_id)

    def _delete_resume_state(self, job_id: UUID) -> None:
        try:
            self._resume_state_manager.delete(job_id)
        except OSError:
            logger.exception("Resume state deletion failed job_id=%s", job_id)

    def _prepare_resume_state(
        self,
        *,
        job_id: UUID,
        source_url: str,
        output_template: str,
        temp_dir: Path,
    ) -> ResumeState | None:
        resume_state = self._resume_state_manager.load(job_id)
        if resume_state is None:
            return None

        logger.debug("Resume state found job_id=%s", job_id)
        if self._is_resume_state_valid(
            resume_state,
            source_url=source_url,
            output_template=output_template,
            temp_dir=temp_dir,
        ):
            logger.debug("Resume validation passed job_id=%s", job_id)
            logger.debug("Starting resumed download job_id=%s", job_id)
            return resume_state

        logger.debug("Resume validation failed job_id=%s", job_id)
        self._invalidate_resume_state(job_id, temp_dir=temp_dir)
        return None

    @staticmethod
    def _is_resume_state_valid(
        state: ResumeState,
        *,
        source_url: str,
        output_template: str,
        temp_dir: Path,
    ) -> bool:
        if state.source_url != source_url or state.downloaded_bytes <= 0:
            return False

        try:
            storage_dir = temp_dir.resolve()
            temporary_file = Path(state.temporary_file_path).resolve()
            output_file = Path(state.output_path).resolve()
        except OSError:
            return False

        if not temporary_file.is_relative_to(storage_dir) or not output_file.is_relative_to(storage_dir):
            return False
        if not temporary_file.is_file() or temporary_file.stat().st_size <= 0:
            return False

        expected_prefix = f"{Path(output_template).stem}."
        return output_file.name.startswith(expected_prefix)

    def _invalidate_resume_state(self, job_id: UUID, *, temp_dir: Path) -> None:
        self._delete_resume_state(job_id)
        for artifact in temp_dir.glob(f"{job_id}.*"):
            if artifact.name.casefold().endswith((".part", ".ytdl")):
                try:
                    artifact.unlink(missing_ok=True)
                except OSError:
                    logger.warning("Resume artifact cleanup failed job_id=%s", job_id)

    def _process_download_with_youtube_dl(
        self,
        youtube_dl: YoutubeDL,
        *,
        job_id: UUID,
        url: str,
        output_type: str,
        format_selector: str,
        download_info: dict[str, Any] | None,
        detected_platform: str,
    ) -> dict[str, Any]:
        if download_info is None:
            return youtube_dl.extract_info(url, download=True)

        resolved_download_info = download_info
        if detected_platform in _PLATFORMS_REQUIRING_TRANSPORT_REFRESH:
            resolved_download_info, legacy_download_info = self._refresh_download_transport_info(
                youtube_dl,
                url=url,
                snapshot=download_info,
            )
            settings = self._settings
            logger.info(
                "Diagnostics checkpoint reached enabled=%s",
                settings.download_metadata_diagnostics,
            )
            self._log_download_metadata_diagnostics(
                job_id=job_id,
                output_type=output_type,
                format_selector=format_selector,
                legacy_info=legacy_download_info,
                snapshot_info=resolved_download_info,
            )
        # Snapshots may have passed through yt-dlp processing before they were
        # cached. Runtime fields can hold expired transport URLs, so never pass
        # them into a later process_ie_result call for any platform.
        resolved_download_info = self._sanitize_processed_download_fields(resolved_download_info)
        return youtube_dl.process_ie_result(resolved_download_info, download=True)

    def _get_or_extract_supported_info(
        self,
        normalized_url: str,
        *,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> tuple[dict[str, Any], str, bool, str]:
        cached_result = self._get_cached_supported_info(
            normalized_url,
            auth_session_id=auth_session_id,
        )
        if cached_result is not None:
            return cached_result

        if detect_platform_from_url(normalized_url) != "tiktok":
            return self._extract_and_cache_supported_info(
                normalized_url,
                auth_source=auth_source,
                auth_session_id=auth_session_id,
            )

        # A single in-flight TikTok extraction owns retries for this URL. Other
        # callers wait, then reuse its snapshot instead of creating retry bursts.
        with self._metadata_extraction_gate(normalized_url):
            cached_result = self._get_cached_supported_info(
                normalized_url,
                auth_session_id=auth_session_id,
            )
            if cached_result is not None:
                return cached_result
            return self._extract_and_cache_supported_info(
                normalized_url,
                auth_source=auth_source,
                auth_session_id=auth_session_id,
            )

    def _get_cached_supported_info(
        self,
        normalized_url: str,
        *,
        auth_session_id: str | None = None,
    ) -> tuple[dict[str, Any], str, bool, str] | None:
        snapshot = self._snapshot_cache.get(normalized_url, session_id=auth_session_id)
        if snapshot is None:
            return None

        info = snapshot.extracted_info
        platform = self._detect_platform(info)
        if snapshot.authenticated:
            if platform == "twitter":
                if snapshot.auth_source == "user_session":
                    if not self._x_auth_manager.is_authenticated_available(
                        source=XAuthSource.USER_SESSION,
                        session_id=snapshot.session_id,
                    ):
                        self._snapshot_cache.delete(normalized_url, session_id=snapshot.session_id)
                        return None
                elif self._auth_cookie_file(platform) is None:
                    self._snapshot_cache.delete(normalized_url)
                    return None
            elif self._auth_cookie_file(platform) is None:
                self._snapshot_cache.delete(normalized_url)
                return None

        self._ensure_supported_media_platform(platform)
        self._ensure_platform_media_is_downloadable(info, platform)
        source_url = self._cached_source_url(
            normalized_url,
            info=info,
            platform=platform,
        )
        return info, platform, snapshot.authenticated, source_url

    def _extract_and_cache_supported_info(
        self,
        normalized_url: str,
        *,
        auth_source: str = "guest",
        auth_session_id: str | None = None,
    ) -> tuple[dict[str, Any], str, bool, str]:

        try:
            info, source_url = self._extract_info_with_youtube_mix_fallback(normalized_url)
            platform = self._detect_platform(info)
            self._ensure_supported_media_platform(platform)
            self._ensure_platform_media_is_downloadable(info, platform)
            authenticated = False
            snapshot_auth_source = "guest"
            snapshot_session_id = None
        except APIError as guest_error:
            if auth_source == "user_session" and auth_session_id:
                authenticated_result = self._try_authenticated_x_extraction(
                    normalized_url,
                    guest_error=guest_error,
                    source=auth_source,
                    session_id=auth_session_id,
                )
                if authenticated_result is None:
                    raise
                info, platform = authenticated_result
                authenticated = True
                snapshot_auth_source = "user_session"
                snapshot_session_id = auth_session_id
                source_url = normalized_url
            else:
                authenticated_result = (
                    self._try_authenticated_x_extraction(
                        normalized_url,
                        guest_error=guest_error,
                    )
                    or self._try_authenticated_instagram_extraction(
                        normalized_url,
                        guest_error=guest_error,
                    )
                    or self._try_authenticated_facebook_extraction(
                        normalized_url,
                        guest_error=guest_error,
                    )
                    or self._try_authenticated_reddit_extraction(
                        normalized_url,
                        guest_error=guest_error,
                    )
                )
                if authenticated_result is None:
                    raise
                info, platform = authenticated_result
                authenticated = True
                snapshot_auth_source = "service_account"
                snapshot_session_id = None
                source_url = normalized_url

        self._snapshot_cache.put(
            normalized_url,
            info,
            authenticated=authenticated,
            auth_source=snapshot_auth_source,
            session_id=snapshot_session_id,
        )
        return info, platform, authenticated, source_url

    @contextmanager
    def _metadata_extraction_gate(self, normalized_url: str) -> Iterator[None]:
        with self._metadata_extraction_gates_lock:
            gate = self._metadata_extraction_gates.get(normalized_url)
            if gate is None:
                gate = _MetadataExtractionGate()
                self._metadata_extraction_gates[normalized_url] = gate
            gate.users += 1

        gate.lock.acquire()
        try:
            yield
        finally:
            gate.lock.release()
            with self._metadata_extraction_gates_lock:
                gate.users -= 1
                if gate.users == 0 and self._metadata_extraction_gates.get(normalized_url) is gate:
                    self._metadata_extraction_gates.pop(normalized_url, None)

    def _extract_info_with_youtube_mix_fallback(
        self,
        url: str,
    ) -> tuple[dict[str, Any], str]:
        original_error: APIError | None = None
        candidate: tuple[str, str, str] | None = None
        try:
            return self._extract_info_or_raise_api_error(url), url
        except APIError as exc:
            candidate = self._youtube_mix_candidate(url, error=exc)
            if candidate is None:
                raise
            original_error = exc

        assert original_error is not None and candidate is not None
        playlist_id, seed_id, watch_url = candidate
        playlist_info = self._extract_validated_youtube_mix_playlist(
            watch_url,
            playlist_id=playlist_id,
            seed_id=seed_id,
            original_error=original_error,
        )
        try:
            info = self._extract_info(watch_url)
        except APIError:
            raise self._youtube_mix_unavailable_error() from None
        except (DownloadError, ExtractorError):
            raise self._youtube_mix_unavailable_error() from None

        if not self._is_valid_youtube_mix_media(info, seed_id=seed_id):
            raise self._youtube_mix_unavailable_error()

        logger.info(
            "YouTube Mix seed fallback succeeded playlist_id=%s seed_id=%s entry_count=%s",
            playlist_id,
            seed_id,
            len(playlist_info.get("entries") or []),
        )
        return info, watch_url

    def _extract_playlist_info_with_youtube_mix_fallback(
        self,
        url: str,
    ) -> tuple[dict[str, Any], str]:
        original_error: APIError | None = None
        candidate: tuple[str, str, str] | None = None
        try:
            return self._extract_playlist_info_or_raise_api_error(url), url
        except APIError as exc:
            candidate = self._youtube_mix_candidate(url, error=exc)
            if candidate is None:
                raise
            original_error = exc

        assert original_error is not None and candidate is not None
        playlist_id, seed_id, watch_url = candidate
        info = self._extract_validated_youtube_mix_playlist(
            watch_url,
            playlist_id=playlist_id,
            seed_id=seed_id,
            original_error=original_error,
        )
        logger.info(
            "YouTube Mix seed fallback succeeded playlist_id=%s seed_id=%s entry_count=%s",
            playlist_id,
            seed_id,
            len(info.get("entries") or []),
        )
        return info, watch_url

    def _extract_validated_youtube_mix_playlist(
        self,
        watch_url: str,
        *,
        playlist_id: str,
        seed_id: str,
        original_error: APIError,
    ) -> dict[str, Any]:
        logger.info(
            "YouTube Mix seed fallback attempted playlist_id=%s seed_id=%s",
            playlist_id,
            seed_id,
        )
        try:
            info = self._extract_playlist_info(watch_url)
        except APIError:
            raise self._youtube_mix_unavailable_error() from None
        except (DownloadError, ExtractorError):
            raise self._youtube_mix_unavailable_error() from None

        if not self._is_valid_youtube_mix_playlist(
            info,
            playlist_id=playlist_id,
            seed_id=seed_id,
        ):
            raise self._youtube_mix_unavailable_error() from original_error
        return info

    @staticmethod
    def _youtube_mix_candidate(
        url: str,
        *,
        error: APIError,
    ) -> tuple[str, str, str] | None:
        if error.code != "YOUTUBE_MIX_UNAVAILABLE":
            return None

        parsed = urlsplit(url)
        hostname = (parsed.hostname or "").casefold()
        if hostname not in {"youtube.com", "www.youtube.com", "m.youtube.com"}:
            return None
        if parsed.path.rstrip("/") != "/playlist":
            return None

        playlist_ids = parse_qs(parsed.query).get("list") or []
        if len(playlist_ids) != 1:
            return None
        playlist_id = playlist_ids[0]
        match = _YOUTUBE_MIX_SEED_PATTERN.fullmatch(playlist_id)
        if match is None:
            return None

        seed_id = match.group("seed")
        query = urlencode(
            {
                "v": seed_id,
                "list": playlist_id,
                "start_radio": "1",
            }
        )
        watch_url = urlunsplit(("https", "www.youtube.com", "/watch", query, ""))
        return playlist_id, seed_id, watch_url

    @classmethod
    def _cached_source_url(
        cls,
        original_url: str,
        *,
        info: dict[str, Any],
        platform: str,
    ) -> str:
        if platform != "youtube":
            return original_url

        parsed = urlsplit(original_url)
        playlist_ids = parse_qs(parsed.query).get("list") or []
        if parsed.path.rstrip("/") != "/playlist" or len(playlist_ids) != 1:
            return original_url
        match = _YOUTUBE_MIX_SEED_PATTERN.fullmatch(playlist_ids[0])
        if match is None or str(info.get("id") or "") != match.group("seed"):
            return original_url

        query = urlencode(
            {
                "v": match.group("seed"),
                "list": playlist_ids[0],
                "start_radio": "1",
            }
        )
        return urlunsplit(("https", "www.youtube.com", "/watch", query, ""))

    @classmethod
    def _is_valid_youtube_mix_playlist(
        cls,
        info: dict[str, Any],
        *,
        playlist_id: str,
        seed_id: str,
    ) -> bool:
        returned_playlist_id = str(info.get("id") or info.get("playlist_id") or "")
        entries = [entry for entry in info.get("entries") or [] if isinstance(entry, dict)]
        if returned_playlist_id != playlist_id or not entries:
            return False

        first_usable_entry = next(
            (entry for entry in entries if cls._playlist_entry_webpage_url(entry) is not None),
            None,
        )
        return (
            first_usable_entry is not None
            and str(first_usable_entry.get("id") or "") == seed_id
        )

    @staticmethod
    def _is_valid_youtube_mix_media(info: dict[str, Any], *, seed_id: str) -> bool:
        return (
            str(info.get("id") or "") == seed_id
            and bool(info.get("formats"))
            and MediaService._detect_platform(info) == "youtube"
        )

    @staticmethod
    def _youtube_mix_unavailable_error() -> APIError:
        return APIError(
            code="YOUTUBE_MIX_UNAVAILABLE",
            message="YouTube Mix unavailable",
            details=_YOUTUBE_MIX_UNAVAILABLE_MESSAGE,
            status_code=422,
        )

    def _try_authenticated_x_extraction(
        self,
        normalized_url: str,
        *,
        guest_error: APIError,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> tuple[dict[str, Any], str] | None:
        if (
            detect_platform_from_url(normalized_url) != "twitter"
            or guest_error.code not in _X_AUTHENTICATED_RETRY_ERROR_CODES
        ):
            return None

        provider = self._x_auth_manager.get_authenticated_provider(source=source, session_id=session_id)
        if provider is None:
            return None

        cookie_file = self._x_auth_manager.acquire_session_lease(source=source, session_id=session_id)
        if cookie_file is None:
            return None

        logger.info(
            "X authenticated fallback enabled=true attempted=true source=%s",
            provider.source.value,
        )
        try:
            info = self._extract_info_or_raise_api_error(
                normalized_url,
                cookie_file=cookie_file,
            )
            info = self._sanitize_authenticated_snapshot_info(info)
            platform = self._detect_platform(info)
            self._ensure_supported_media_platform(platform)
            self._ensure_platform_media_is_downloadable(info, platform)
        except APIError:
            logger.warning(
                "X authenticated fallback enabled=true attempted=true succeeded=false"
            )
            return None
        finally:
            self._x_auth_manager.release_session_lease(source=source, session_id=session_id)

        logger.info("X authenticated fallback enabled=true attempted=true succeeded=true")
        return info, platform

    def _x_auth_cookie_file(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        return self._x_auth_manager.get_cookie_file(source=source, session_id=session_id)

    def _require_x_auth_cookie_file(
        self,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path:
        return self._x_auth_manager.require_authenticated_cookie_file(source=source, session_id=session_id)

    def _try_authenticated_instagram_extraction(
        self,
        normalized_url: str,
        *,
        guest_error: APIError,
    ) -> tuple[dict[str, Any], str] | None:
        if (
            detect_platform_from_url(normalized_url) != "instagram"
            or guest_error.code not in _INSTAGRAM_AUTHENTICATED_RETRY_ERROR_CODES
        ):
            return None

        cookie_file = self._instagram_auth_cookie_file()
        if cookie_file is None:
            return None

        logger.info("Instagram authenticated fallback enabled=true attempted=true")
        try:
            info = self._extract_info_or_raise_api_error(
                normalized_url,
                cookie_file=cookie_file,
            )
            info = self._sanitize_authenticated_snapshot_info(info)
            platform = self._detect_platform(info)
            self._ensure_supported_media_platform(platform)
            self._ensure_platform_media_is_downloadable(info, platform)
        except APIError:
            logger.warning(
                "Instagram authenticated fallback enabled=true attempted=true succeeded=false"
            )
            return None

        logger.info("Instagram authenticated fallback enabled=true attempted=true succeeded=true")
        return info, platform

    def _instagram_auth_cookie_file(self) -> Path | None:
        configured_path = self._settings.instagram_auth_cookie_file.strip()
        if not configured_path:
            return None

        cookie_file = Path(configured_path).expanduser()
        try:
            if not cookie_file.is_file():
                raise FileNotFoundError
            cookie_jar = MozillaCookieJar(str(cookie_file))
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            cookie_names = {cookie.name for cookie in cookie_jar}
            if "sessionid" in cookie_names or "csrftoken" in cookie_names or "ds_user_id" in cookie_names:
                return cookie_file
        except (LoadError, OSError):
            logger.warning(
                "Instagram authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
            )
            return None

        logger.warning(
            "Instagram authenticated fallback enabled=true attempted=false reason=cookie_file_invalid"
        )
        return None

    def _require_instagram_auth_cookie_file(self) -> Path:
        cookie_file = self._instagram_auth_cookie_file()
        if cookie_file is None:
            raise DownloadError("Authenticated Instagram session unavailable")
        return cookie_file

    def _try_authenticated_facebook_extraction(
        self,
        normalized_url: str,
        *,
        guest_error: APIError,
    ) -> tuple[dict[str, Any], str] | None:
        if (
            detect_platform_from_url(normalized_url) != "facebook"
            or guest_error.code not in _FACEBOOK_AUTHENTICATED_RETRY_ERROR_CODES
        ):
            return None

        cookie_file = self._facebook_auth_cookie_file()
        if cookie_file is None:
            return None

        logger.info("Facebook authenticated fallback enabled=true attempted=true")
        try:
            info = self._extract_info_or_raise_api_error(
                normalized_url,
                cookie_file=cookie_file,
            )
            info = self._sanitize_authenticated_snapshot_info(info)
            platform = self._detect_platform(info)
            self._ensure_supported_media_platform(platform)
            self._ensure_platform_media_is_downloadable(info, platform)
        except APIError:
            logger.warning(
                "Facebook authenticated fallback enabled=true attempted=true succeeded=false"
            )
            return None

        logger.info("Facebook authenticated fallback enabled=true attempted=true succeeded=true")
        return info, platform

    def _facebook_auth_cookie_file(self) -> Path | None:
        configured_path = self._settings.facebook_auth_cookie_file.strip()
        if not configured_path:
            return None

        cookie_file = Path(configured_path).expanduser()
        try:
            if not cookie_file.is_file():
                raise FileNotFoundError
            cookie_jar = MozillaCookieJar(str(cookie_file))
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            cookie_names = {cookie.name for cookie in cookie_jar}
            if any(name in cookie_names for name in ("c_user", "xs", "fr", "datr", "sb")):
                return cookie_file
        except (LoadError, OSError):
            logger.warning(
                "Facebook authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
            )
            return None

        logger.warning(
            "Facebook authenticated fallback enabled=true attempted=false reason=cookie_file_invalid"
        )
        return None

    def _require_facebook_auth_cookie_file(self) -> Path:
        cookie_file = self._facebook_auth_cookie_file()
        if cookie_file is None:
            raise DownloadError("Authenticated Facebook session unavailable")
        return cookie_file

    def _try_authenticated_reddit_extraction(
        self,
        normalized_url: str,
        *,
        guest_error: APIError,
    ) -> tuple[dict[str, Any], str] | None:
        if (
            detect_platform_from_url(normalized_url) != "reddit"
            or guest_error.code not in _REDDIT_AUTHENTICATED_RETRY_ERROR_CODES
        ):
            return None

        cookie_file = self._reddit_auth_cookie_file()
        if cookie_file is None:
            return None

        logger.info("Reddit authenticated fallback enabled=true attempted=true")
        try:
            info = self._extract_info_or_raise_api_error(
                normalized_url,
                cookie_file=cookie_file,
            )
            info = self._sanitize_authenticated_snapshot_info(info)
            platform = self._detect_platform(info)
            self._ensure_supported_media_platform(platform)
            self._ensure_platform_media_is_downloadable(info, platform)
        except APIError:
            logger.warning(
                "Reddit authenticated fallback enabled=true attempted=true succeeded=false"
            )
            return None

        logger.info("Reddit authenticated fallback enabled=true attempted=true succeeded=true")
        return info, platform

    def _reddit_auth_cookie_file(self) -> Path | None:
        configured_path = self._settings.reddit_auth_cookie_file.strip()
        if not configured_path:
            return None

        cookie_file = Path(configured_path).expanduser()
        try:
            if not cookie_file.is_file():
                raise FileNotFoundError
            cookie_jar = MozillaCookieJar(str(cookie_file))
            cookie_jar.load(ignore_discard=True, ignore_expires=True)
            cookie_names = {cookie.name for cookie in cookie_jar}
            if any(name in cookie_names for name in ("reddit_session", "token_v2", "session_tracker", "loid", "csv", "edgebucket")):
                return cookie_file
        except (LoadError, OSError):
            logger.warning(
                "Reddit authenticated fallback enabled=true attempted=false reason=cookie_file_unavailable"
            )
            return None

        logger.warning(
            "Reddit authenticated fallback enabled=true attempted=false reason=cookie_file_invalid"
        )
        return None

    def _require_reddit_auth_cookie_file(self) -> Path:
        cookie_file = self._reddit_auth_cookie_file()
        if cookie_file is None:
            raise DownloadError("Authenticated Reddit session unavailable")
        return cookie_file

    def _auth_cookie_file(
        self,
        platform: str,
        *,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path | None:
        if platform == "twitter":
            return self._x_auth_cookie_file(source=source, session_id=session_id)
        if platform == "instagram":
            return self._instagram_auth_cookie_file()
        if platform == "facebook":
            return self._facebook_auth_cookie_file()
        if platform == "reddit":
            return self._reddit_auth_cookie_file()
        return None

    def _require_auth_cookie_file(
        self,
        platform: str,
        *,
        source: XAuthSource | str | None = None,
        session_id: str | None = None,
    ) -> Path:
        if platform == "twitter":
            return self._require_x_auth_cookie_file(source=source, session_id=session_id)
        if platform == "instagram":
            return self._require_instagram_auth_cookie_file()
        if platform == "facebook":
            return self._require_facebook_auth_cookie_file()
        if platform == "reddit":
            return self._require_reddit_auth_cookie_file()
        raise DownloadError(f"Authenticated session unavailable for platform: {platform}")

    @classmethod
    def _sanitize_authenticated_snapshot_info(cls, info: dict[str, Any]) -> dict[str, Any]:
        sanitized = cls._remove_authenticated_snapshot_secrets(deepcopy(info))
        return sanitized if isinstance(sanitized, dict) else {}

    @classmethod
    def _remove_authenticated_snapshot_secrets(cls, value: Any) -> Any:
        if isinstance(value, dict):
            return {
                key: cls._remove_authenticated_snapshot_secrets(item)
                for key, item in value.items()
                if str(key).casefold() not in _AUTHENTICATED_SNAPSHOT_SENSITIVE_KEYS
            }
        if isinstance(value, list):
            return [cls._remove_authenticated_snapshot_secrets(item) for item in value]
        if isinstance(value, tuple):
            return tuple(cls._remove_authenticated_snapshot_secrets(item) for item in value)
        return value

    @staticmethod
    def _refresh_download_transport_info(
        youtube_dl: YoutubeDL,
        *,
        url: str,
        snapshot: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Refresh transient stream data without replacing cached presentation metadata."""
        refreshed_info = youtube_dl.extract_info(url, download=False, process=False)
        if not isinstance(refreshed_info, dict):
            raise DownloadError("yt-dlp did not return download metadata")

        resolved_info = deepcopy(snapshot)
        for field in _DOWNLOAD_TRANSPORT_FIELDS:
            if field in refreshed_info:
                resolved_info[field] = deepcopy(refreshed_info[field])
        return resolved_info, refreshed_info

    @staticmethod
    def _sanitize_processed_download_fields(info: dict[str, Any]) -> dict[str, Any]:
        """Discard cached yt-dlp runtime state before processing fresh streams."""
        sanitized_info = deepcopy(info)
        for field in _PROCESSED_DOWNLOAD_FIELDS:
            sanitized_info.pop(field, None)
        return sanitized_info

    def _log_download_metadata_diagnostics(
        self,
        *,
        job_id: UUID,
        output_type: str,
        format_selector: str,
        legacy_info: dict[str, Any],
        snapshot_info: dict[str, Any],
    ) -> None:
        if not self._settings.download_metadata_diagnostics:
            return

        report = build_download_metadata_diagnostic_report(
            legacy_info=legacy_info,
            snapshot_info=snapshot_info,
        )
        logger.info(
            "Download metadata diagnostic job_id=%s media_type=%s format_selector=%s report=%s",
            job_id,
            output_type,
            format_selector,
            report.as_log_payload(),
        )

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

    def _build_progress_hook(self, job_id, job_manager, resume_state_manager: ResumeStateManager):
        last_progress = {"value": -1}
        last_resume_progress: dict[str, tuple[int, int | None] | None] = {"value": None}

        def hook(payload: dict[str, Any]) -> None:
            self._process_manager.raise_if_cancelled(job_id)
            status = payload.get("status")
            if status != "downloading":
                if status == "finished":
                    logger.info("Download file transfer finished job_id=%s", job_id)
                return

            total = payload.get("total_bytes") or payload.get("total_bytes_estimate")
            downloaded = payload.get("downloaded_bytes") or 0
            resume_progress = (downloaded, total)
            if resume_progress != last_resume_progress["value"]:
                last_resume_progress["value"] = resume_progress
                try:
                    resume_state_manager.update_progress(
                        job_id,
                        downloaded,
                        total,
                        output_path=_payload_path(payload.get("filename")),
                        temporary_file_path=_payload_path(payload.get("tmpfilename")),
                    )
                except (OSError, ValueError):
                    logger.warning("Resume progress update failed job_id=%s", job_id)
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
        resume_state_manager: ResumeStateManager,
        continue_download: bool,
        cookie_file: Path | None = None,
    ) -> dict[str, Any]:
        options: dict[str, Any] = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "skip_download": False,
            "cachedir": False,
            "continuedl": continue_download,
            "nopart": False,
            "format": format_selector,
            "outtmpl": output_template,
            "paths": {"home": str(temp_dir)},
            "progress_hooks": [self._build_progress_hook(job_id, job_manager, resume_state_manager)],
            "postprocessor_hooks": [self._build_postprocessor_hook(job_id)],
        }
        if output_type == "audio":
            # yt-dlp chooses its best audio stream, then FFmpeg produces a
            # playable MP3 at its highest VBR quality setting.
            options["postprocessors"] = [dict(_AUDIO_MP3_POSTPROCESSOR)]
        if cookie_file is not None:
            options["cookiefile"] = str(cookie_file)
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
        if "authenticated" in lowered and "session unavailable" in lowered:
            if "x" in lowered:
                return "Authenticated X session unavailable"
            return "Authenticated session unavailable"
        return "yt-dlp failed to download the media"

    def _extract_info(
        self,
        url: str,
        *,
        cookie_file: Path | None = None,
    ) -> dict[str, Any]:
        ydl_options = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": True,
            "skip_download": True,
            "cachedir": False,
        }
        if cookie_file is not None:
            ydl_options["cookiefile"] = str(cookie_file)

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
            if self._detect_platform(extracted_info) == "tiktok":
                raise APIError(
                    code="TIKTOK_PLAYLIST_NOT_SUPPORTED",
                    message="TikTok playlist import is unavailable",
                    details="TikTok playlist import is not supported. Paste individual TikTok video URLs instead.",
                    status_code=501,
                )
            raise APIError(
                code="PLAYLIST_NOT_SUPPORTED",
                message="Unsupported media type",
                details="Playlists are not supported in this version",
                status_code=501,
            )

        return extracted_info

    def _extract_info_or_raise_api_error(
        self,
        url: str,
        *,
        cookie_file: Path | None = None,
    ) -> dict[str, Any]:
        if cookie_file is None and detect_platform_from_url(url) == "tiktok":
            return self._extract_tiktok_info_with_retry(url)

        try:
            if cookie_file is None:
                return self._extract_info(url)
            return self._extract_info(url, cookie_file=cookie_file)
        except APIError:
            raise
        except (DownloadError, ExtractorError) as exc:
            raise self._map_yt_dlp_error(exc, url=url) from None
        except Exception as exc:
            raise APIError(
                code="METADATA_EXTRACTION_ERROR",
                message="Failed to extract media metadata",
                details="An unexpected error occurred while extracting media metadata",
                status_code=500,
            ) from exc

    def _extract_tiktok_info_with_retry(self, url: str) -> dict[str, Any]:
        for attempt in range(1, _TIKTOK_MAX_EXTRACTION_ATTEMPTS + 1):
            logger.info(
                "TikTok metadata extraction attempt attempt=%s max_attempts=%s",
                attempt,
                _TIKTOK_MAX_EXTRACTION_ATTEMPTS,
            )
            try:
                return self._extract_info(url)
            except APIError:
                raise
            except (DownloadError, ExtractorError) as exc:
                if not self._is_transient_tiktok_extraction_error(exc):
                    raise self._map_yt_dlp_error(exc, url=url) from None

                if attempt >= _TIKTOK_MAX_EXTRACTION_ATTEMPTS:
                    logger.warning(
                        "TikTok metadata extraction retry exhausted attempts=%s",
                        attempt,
                    )
                    raise self._map_yt_dlp_error(exc, url=url) from None

                base_delay = _TIKTOK_RETRY_DELAYS_SECONDS[attempt - 1]
                delay = base_delay + self._retry_jitter(0.0, base_delay * 0.2)
                logger.warning(
                    "TikTok transient extraction failure attempt=%s retrying=true delay_ms=%s",
                    attempt,
                    round(delay * 1000),
                )
                self._sleep(delay)
            except Exception as exc:
                raise APIError(
                    code="METADATA_EXTRACTION_ERROR",
                    message="Failed to extract media metadata",
                    details="An unexpected error occurred while extracting media metadata",
                    status_code=500,
                ) from exc

        raise AssertionError("TikTok extraction retry loop terminated unexpectedly")

    def _extract_playlist_info(self, url: str) -> dict[str, Any]:
        # Flat extraction intentionally avoids resolving each video's formats.
        # Batch Import performs that work later, sequentially, for selected URLs.
        ydl_options = {
            "quiet": True,
            "no_warnings": True,
            "noplaylist": False,
            "skip_download": True,
            "extract_flat": True,
            "cachedir": False,
        }
        with YoutubeDL(ydl_options) as youtube_dl:
            extracted_info = youtube_dl.extract_info(url, download=False)

        if not isinstance(extracted_info, dict):
            raise APIError(
                code="PLAYLIST_EXTRACTION_ERROR",
                message="Failed to extract playlist metadata",
                details="yt-dlp returned an unexpected response",
                status_code=500,
            )
        if extracted_info.get("_type") != "playlist" and not extracted_info.get("entries"):
            raise APIError(
                code="NOT_A_PLAYLIST",
                message="Playlist unavailable",
                details="The supplied URL does not reference a playlist",
                status_code=422,
            )
        return extracted_info

    def _extract_playlist_info_or_raise_api_error(self, url: str) -> dict[str, Any]:
        try:
            return self._extract_playlist_info(url)
        except APIError:
            raise
        except (DownloadError, ExtractorError) as exc:
            raise self._map_yt_dlp_error(exc, url=url) from None
        except Exception as exc:
            raise APIError(
                code="PLAYLIST_EXTRACTION_ERROR",
                message="Failed to extract playlist metadata",
                details="An unexpected error occurred while extracting playlist metadata",
                status_code=500,
            ) from exc

    @staticmethod
    def _normalize_source_url(url: str) -> str:
        normalized_url = validate_http_url(url)
        platform = detect_platform_from_url(normalized_url)
        if platform == "twitter":
            if not is_x_status_url(normalized_url):
                raise APIError(
                    code="INVALID_X_URL",
                    message="Invalid X post URL",
                    details="Use a public X post URL in the form x.com/<user>/status/<id>.",
                    status_code=422,
                )
            return normalize_media_url(normalized_url)

        if platform == "instagram":
            if not is_instagram_media_url(normalized_url):
                raise APIError(
                    code="INVALID_INSTAGRAM_URL",
                    message="Invalid Instagram URL",
                    details="Use a public Instagram Reel or Post URL in the form instagram.com/reel/<id> or instagram.com/p/<id>.",
                    status_code=422,
                )
            return normalize_media_url(normalized_url)

        if platform == "facebook":
            if not is_facebook_media_url(normalized_url):
                raise APIError(
                    code="INVALID_FACEBOOK_URL",
                    message="Invalid Facebook URL",
                    details="Use a public Facebook Watch, Reel, or Video URL.",
                    status_code=422,
                )
            return normalize_media_url(normalized_url)

        if platform == "reddit":
            if not is_reddit_media_url(normalized_url):
                raise APIError(
                    code="INVALID_REDDIT_URL",
                    message="Invalid Reddit URL",
                    details="Use a public Reddit post, comment, or video URL in the form reddit.com/r/<subreddit>/comments/<id> or v.redd.it/<id>.",
                    status_code=422,
                )
            return normalize_media_url(normalized_url)

        return normalized_url

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
        if "facebook" in haystack or "fb" in haystack:
            return "facebook"
        if "reddit" in haystack:
            return "reddit"
        if "vimeo" in haystack:
            return "vimeo"
        return "unknown"

    @staticmethod
    def _ensure_supported_media_platform(platform: str) -> None:
        if platform in _SUPPORTED_MEDIA_PLATFORMS:
            return
        raise APIError(
            code="UNSUPPORTED_PLATFORM",
            message="Unsupported platform",
            details="This media platform is not supported.",
            status_code=501,
        )

    def _ensure_platform_media_is_downloadable(self, info: dict[str, Any], platform: str) -> None:
        """Reject posts that yt-dlp resolved without playable media streams."""
        if platform == "twitter":
            formats = info.get("formats") or []
            if self._quality_selector.build_qualities(
                formats,
                platform=platform,
            ) or self._has_audio_available(formats, platform=platform):
                return

            raise APIError(
                code="X_MEDIA_NOT_AVAILABLE",
                message=_X_MEDIA_NOT_AVAILABLE_MESSAGE,
                details=_X_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=422,
            )

        if platform == "instagram":
            formats = info.get("formats") or []
            if self._quality_selector.build_qualities(
                formats,
                platform=platform,
            ) or self._has_audio_available(formats, platform=platform):
                return

            raise APIError(
                code="INSTAGRAM_MEDIA_NOT_AVAILABLE",
                message=_INSTAGRAM_MEDIA_NOT_AVAILABLE_MESSAGE,
                details=_INSTAGRAM_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=422,
            )

        if platform == "facebook":
            formats = info.get("formats") or []
            if self._quality_selector.build_qualities(
                formats,
                platform=platform,
            ) or self._has_audio_available(formats, platform=platform):
                return

            raise APIError(
                code="FACEBOOK_MEDIA_NOT_AVAILABLE",
                message=_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE,
                details=_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=422,
            )

    def _build_metadata(self, *, info: dict[str, Any], platform: str, url: str) -> MediaMetadata:
        formats = info.get("formats") or []
        video_qualities = self._quality_selector.build_qualities(formats, platform=platform)
        return MediaMetadata(
            platform=platform,
            title=str(info.get("title") or "Untitled media"),
            uploader=info.get("uploader"),
            uploader_url=info.get("uploader_url"),
            thumbnail_url=self._select_thumbnail(info),
            duration_seconds=self._int_or_none(info.get("duration")),
            webpage_url=self._download_source_url(info=info, platform=platform, url=url),
            extractor=str(info.get("extractor") or ""),
            extractor_key=str(info.get("extractor_key") or info.get("ie_key") or ""),
            upload_date=info.get("upload_date"),
            view_count=self._int_or_none(info.get("view_count")),
            like_count=self._int_or_none(info.get("like_count")),
            description=info.get("description"),
            video_qualities=video_qualities,
            audio_options=self._build_audio_options(formats, platform=platform),
        )

    def _build_playlist_items(self, info: dict[str, Any]) -> list[PlaylistItem]:
        items: list[PlaylistItem] = []
        is_instagram = self._detect_platform(info) == "instagram"
        is_facebook = self._detect_platform(info) == "facebook"
        is_reddit = self._detect_platform(info) == "reddit"
        for entry in info.get("entries") or []:
            if not isinstance(entry, dict):
                continue
            # For Instagram, Facebook, and Reddit multi-media, ignore image-only entries that have no playable video stream
            if is_instagram or is_facebook or is_reddit or self._detect_platform(entry) in ("instagram", "facebook", "reddit"):
                entry_formats = entry.get("formats") or []
                if not entry_formats and not entry.get("video_url") and not entry.get("duration"):
                    continue
            webpage_url = self._playlist_entry_webpage_url(entry)
            if webpage_url is None:
                continue
            items.append(
                PlaylistItem(
                    title=str(entry.get("title") or "Untitled media"),
                    thumbnail_url=self._select_thumbnail(entry),
                    webpage_url=webpage_url,
                    duration_seconds=self._int_or_none(entry.get("duration")),
                )
            )
        return items

    @staticmethod
    def _download_source_url(*, info: dict[str, Any], platform: str, url: str) -> str:
        # TikTok, Twitter, Instagram, Facebook, and Reddit URLs can succeed where a later extraction
        # of the canonical URL returned by yt-dlp fails or misses query state.
        if platform in {"tiktok", "twitter", "instagram", "facebook", "reddit"}:
            return url
        return str(info.get("webpage_url") or url)

    @staticmethod
    def _playlist_entry_webpage_url(entry: dict[str, Any]) -> str | None:
        webpage_url = entry.get("webpage_url") or entry.get("original_url")
        if webpage_url:
            return str(webpage_url)

        entry_url = entry.get("url")
        if isinstance(entry_url, str) and entry_url.startswith(("http://", "https://")):
            return entry_url

        entry_id = entry.get("id") or entry.get("code")
        if entry_id:
            ie_key = str(entry.get("ie_key") or entry.get("extractor_key") or "").casefold()
            if "instagram" in ie_key:
                return f"https://www.instagram.com/p/{quote(str(entry_id), safe='')}/"
            if "facebook" in ie_key:
                return f"https://www.facebook.com/watch/?v={quote(str(entry_id), safe='')}"
            if "reddit" in ie_key:
                display_id = entry.get("display_id") or entry_id
                return f"https://www.reddit.com/comments/{quote(str(display_id), safe='')}"

        # YouTube flat playlist extraction commonly returns only a video ID.
        if entry_id:
            return f"https://www.youtube.com/watch?v={quote(str(entry_id), safe='')}"
        return None

    def _build_audio_options(
        self,
        formats: list[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> list[AudioOption]:
        if not self._has_audio_available(formats, platform=platform):
            return []
        return [AudioOption(label="MP3", extension="mp3")]

    def _has_audio_available(
        self,
        formats: list[dict[str, Any]],
        *,
        platform: str | None = None,
    ) -> bool:
        return self._quality_selector.has_audio_available(formats, platform=platform)

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
    def _map_yt_dlp_error(exc: Exception, *, url: str | None = None) -> APIError:
        message = str(exc)
        lowered = message.casefold()

        is_twitter = url is not None and detect_platform_from_url(url) == "twitter"
        is_youtube = url is not None and detect_platform_from_url(url) == "youtube"
        is_tiktok = url is not None and detect_platform_from_url(url) == "tiktok"
        is_instagram = url is not None and detect_platform_from_url(url) == "instagram"
        is_facebook = url is not None and detect_platform_from_url(url) == "facebook"
        is_reddit = url is not None and detect_platform_from_url(url) == "reddit"

        if is_youtube and any(marker in lowered for marker in _YOUTUBE_MIX_FAILURE_MARKERS):
            return MediaService._youtube_mix_unavailable_error()

        if is_twitter and any(
            token in lowered
            for token in (
                "no video could be found",
                "no media could be found",
                "no downloadable video",
            )
        ):
            return APIError(
                code="X_MEDIA_NOT_AVAILABLE",
                message=_X_MEDIA_NOT_AVAILABLE_MESSAGE,
                details=_X_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=422,
            )

        if is_instagram and "there is no video in this post" in lowered:
            return APIError(
                code="NO_VIDEO_IN_POST",
                message="No downloadable video found",
                details="This Instagram post does not contain a downloadable video.",
                status_code=422,
            )

        if is_instagram and any(marker in lowered for marker in ("unsupported url", "is not a valid url")):
            return APIError(
                code="INVALID_INSTAGRAM_URL",
                message="Invalid Instagram URL",
                details="Use a public Instagram Reel or Post URL in the form instagram.com/reel/<id> or instagram.com/p/<id>.",
                status_code=422,
            )

        if is_facebook and any(marker in lowered for marker in ("unsupported url", "is not a valid url")):
            return APIError(
                code="INVALID_FACEBOOK_URL",
                message="Invalid Facebook URL",
                details="Use a public Facebook Watch, Reel, or Video URL.",
                status_code=422,
            )

        if is_facebook and any(
            token in lowered
            for token in (
                "there is no video in this post",
                "cannot parse data",
            )
        ):
            return APIError(
                code="NO_VIDEO_IN_POST",
                message="No downloadable video found",
                details="This Facebook post does not contain a downloadable video.",
                status_code=422,
            )

        if is_reddit and any(marker in lowered for marker in ("unsupported url", "is not a valid url")):
            return APIError(
                code="INVALID_REDDIT_URL",
                message="Invalid Reddit URL",
                details="Use a public Reddit post, comment, or video URL in the form reddit.com/r/<subreddit>/comments/<id> or v.redd.it/<id>.",
                status_code=422,
            )

        if is_reddit and any(
            token in lowered
            for token in (
                "no media found",
                "there is no video in this post",
                "this video is processing",
            )
        ):
            return APIError(
                code="NO_VIDEO_IN_POST",
                message="No downloadable video found",
                details="This Reddit post does not contain a downloadable video.",
                status_code=422,
            )

        if is_tiktok and MediaService._is_transient_tiktok_extraction_error(exc):
            return APIError(
                code="TIKTOK_EXTRACTION_UNAVAILABLE",
                message="TikTok video temporarily unavailable",
                details="TikTok could not be accessed right now. Try its share link again later.",
                status_code=502,
            )

        if any(
            token in lowered
            for token in (
                "private",
                "protected",
                "restricted",
                "members-only",
                "sign in",
                "registered users who follow this account",
                "account authentication is required",
                "quarantined subreddit",
                "private subreddit",
            )
        ):
            return APIError(
                code="VIDEO_PRIVATE",
                message="Private video",
                details="The requested video is private and cannot be accessed",
                status_code=403,
            )

        if any(token in lowered for token in ("removed", "unavailable", "not available", "not found", "empty media response")):
            if is_instagram:
                return APIError(
                    code="INSTAGRAM_MEDIA_NOT_AVAILABLE",
                    message=_INSTAGRAM_MEDIA_NOT_AVAILABLE_MESSAGE,
                    details=_INSTAGRAM_MEDIA_NOT_AVAILABLE_MESSAGE,
                    status_code=404,
                )
            if is_facebook:
                return APIError(
                    code="FACEBOOK_MEDIA_NOT_AVAILABLE",
                    message=_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE,
                    details=_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE,
                    status_code=404,
                )
            if is_reddit:
                return APIError(
                    code="REDDIT_MEDIA_NOT_AVAILABLE",
                    message=_REDDIT_MEDIA_NOT_AVAILABLE_MESSAGE,
                    details=_REDDIT_MEDIA_NOT_AVAILABLE_MESSAGE,
                    status_code=404,
                )
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

        if is_twitter:
            return APIError(
                code="X_EXTRACTION_UNAVAILABLE",
                message="X post temporarily unavailable",
                details="X could not be accessed right now. Try the public post URL again later.",
                status_code=502,
            )

        if is_instagram:
            return APIError(
                code="INSTAGRAM_EXTRACTION_UNAVAILABLE",
                message="Instagram post temporarily unavailable",
                details="Instagram could not be accessed right now. Try the public post URL again later.",
                status_code=502,
            )

        if is_facebook:
            return APIError(
                code="FACEBOOK_EXTRACTION_UNAVAILABLE",
                message="Facebook post temporarily unavailable",
                details=_FACEBOOK_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=502,
            )

        if is_reddit:
            return APIError(
                code="REDDIT_EXTRACTION_UNAVAILABLE",
                message="Reddit post temporarily unavailable",
                details=_REDDIT_MEDIA_NOT_AVAILABLE_MESSAGE,
                status_code=502,
            )

        return APIError(
            code="YTDLP_EXTRACTION_ERROR",
            message="Failed to extract media metadata",
            details="yt-dlp could not extract metadata from the provided URL",
            status_code=500,
        )

    @staticmethod
    def _is_transient_tiktok_extraction_error(exc: Exception) -> bool:
        messages: list[str] = []
        current: BaseException | None = exc
        seen: set[int] = set()
        while current is not None and id(current) not in seen:
            seen.add(id(current))
            messages.append(str(current).casefold())
            current = current.__cause__ or current.__context__

        combined = " ".join(messages)
        if any(marker in combined for marker in _TIKTOK_PERMANENT_EXTRACTION_MARKERS):
            return False
        if any(marker in combined for marker in _TIKTOK_TRANSIENT_EXTRACTION_MARKERS):
            return True
        return re.search(r"(?:http error|status(?: code)?)\s*5\d\d\b", combined) is not None

    def _log_failure(self, url: str, message: str, details: str, exc: Exception | None = None) -> None:
        if self._settings.debug and exc is not None:
            logger.exception("Metadata extraction failed url=%s message=%s details=%s", url, message, details)
        else:
            logger.warning("Metadata extraction failed url=%s message=%s details=%s", url, message, details)
