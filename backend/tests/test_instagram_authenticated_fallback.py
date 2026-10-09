from __future__ import annotations

from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from yt_dlp.utils import DownloadError, ExtractorError

from app.core.exceptions import APIError
from app.models.instagram_auth import InstagramAuthSource
from app.services.instagram_auth_manager import InstagramAuthManager
from app.services.instagram_user_session_store import EphemeralInstagramUserSessionStore
from app.services.media_service import MediaService

_IG_URL = "https://www.instagram.com/reel/C_test_12345/"


@pytest.fixture
def session_store(tmp_path: Path) -> EphemeralInstagramUserSessionStore:
    return EphemeralInstagramUserSessionStore(storage_dir=tmp_path / "sessions", cleanup_on_startup=True)


@pytest.fixture
def auth_manager(session_store: EphemeralInstagramUserSessionStore) -> InstagramAuthManager:
    return InstagramAuthManager(user_session_store=session_store)


@pytest.fixture
def media_service(auth_manager: InstagramAuthManager) -> MediaService:
    return MediaService(instagram_auth_manager=auth_manager)


def _mock_ig_info(title: str = "Test Video") -> dict[str, Any]:
    return {
        "id": "C_test_12345",
        "title": title,
        "extractor": "Instagram",
        "extractor_key": "Instagram",
        "formats": [
            {
                "format_id": "0",
                "ext": "mp4",
                "vcodec": "avc1.64001f",
                "acodec": None,
                "width": 720,
                "height": 1280,
                "protocol": "https",
            }
        ],
    }


def test_guest_success_does_not_attempt_authenticated_fallback(
    media_service: MediaService,
    session_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = session_store.create_session(sessionid="test_sessionid")

    with patch.object(media_service, "_extract_info", return_value=_mock_ig_info("Guest Video")) as mock_extract:
        meta = media_service.get_metadata(
            _IG_URL,
            auth_source="user_session",
            auth_session_id=session.session_id,
        )

        assert meta.title == "Guest Video"
        assert mock_extract.call_count == 1
        # Cookie file should NOT be passed in guest attempt
        assert mock_extract.call_args.kwargs.get("cookie_file") is None


def test_empty_media_response_triggers_authenticated_fallback(
    media_service: MediaService,
    session_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = session_store.create_session(sessionid="test_sessionid")

    def side_effect(url: str, cookie_file: Path | None = None) -> dict[str, Any]:
        if cookie_file is None:
            # First attempt (guest) fails with empty media response
            raise ExtractorError(
                "Instagram sent an empty media response. Check if this post is accessible in your "
                "browser without being logged-in.",
                expected=True,
            )
        # Second attempt (authenticated) succeeds
        return _mock_ig_info("Authenticated Instagram Video")

    with patch.object(media_service, "_extract_info", side_effect=side_effect) as mock_extract:
        meta = media_service.get_metadata(
            _IG_URL,
            auth_source="user_session",
            auth_session_id=session.session_id,
        )

        assert meta.title == "Authenticated Instagram Video"
        assert mock_extract.call_count == 2
        # First call: no cookie_file
        assert mock_extract.call_args_list[0].kwargs.get("cookie_file") is None
        # Second call: valid cookie_file
        second_cookie = mock_extract.call_args_list[1].kwargs.get("cookie_file")
        assert second_cookie is not None
        assert second_cookie.is_file()


def test_empty_media_response_without_session_does_not_fallback(
    media_service: MediaService,
) -> None:
    def side_effect(url: str, cookie_file: Path | None = None) -> dict[str, Any]:
        raise ExtractorError(
            "Instagram sent an empty media response. Check if this post is accessible in your "
            "browser without being logged-in.",
            expected=True,
        )

    with patch.object(media_service, "_extract_info", side_effect=side_effect) as mock_extract:
        with pytest.raises(APIError) as exc:
            media_service.get_metadata(_IG_URL)

        assert exc.value.code == "INSTAGRAM_MEDIA_NOT_AVAILABLE"
        assert exc.value.status_code == 404
        assert mock_extract.call_count == 1


def test_authenticated_fallback_failure_preserves_session_and_raises(
    media_service: MediaService,
    session_store: EphemeralInstagramUserSessionStore,
) -> None:
    session = session_store.create_session(sessionid="test_sessionid")

    def side_effect(url: str, cookie_file: Path | None = None) -> dict[str, Any]:
        raise ExtractorError("Instagram sent an empty media response", expected=True)

    with patch.object(media_service, "_extract_info", side_effect=side_effect) as mock_extract:
        with pytest.raises(APIError) as exc:
            media_service.get_metadata(
                _IG_URL,
                auth_source="user_session",
                auth_session_id=session.session_id,
            )

        assert exc.value.code == "INSTAGRAM_MEDIA_NOT_AVAILABLE"
        assert mock_extract.call_count == 2
        # Verify session is still valid and has not been wiped or destroyed
        assert session_store.has_session(session.session_id) is True
