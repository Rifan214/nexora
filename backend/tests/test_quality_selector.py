from __future__ import annotations

import logging

import pytest

from app.services.quality_selector import QualitySelector


def test_360p_progressive_stream_is_selected_without_an_audio_merge() -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "18",
                "height": 360,
                "ext": "mp4",
                "vcodec": "avc1.42001E",
                "acodec": "mp4a.40.2",
                "filesize": 10_000,
            }
        ],
        360,
    )

    assert selection is not None
    assert selection.selector == "18"
    assert selection.audio_format_id is None
    assert selection.quality.model_dump() == {
        "label": "360p",
        "height": 360,
        "extension": "mp4",
        "estimated_filesize": 10_000,
    }


def test_1080p_prefers_h264_and_pairs_it_with_the_best_audio_stream() -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "299",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.640028",
                "acodec": "none",
                "tbr": 4_500,
                "filesize": 110_000,
            },
            {
                "format_id": "303",
                "height": 1080,
                "ext": "webm",
                "vcodec": "vp09.00.40.08",
                "acodec": "none",
                "tbr": 4_000,
                "filesize": 105_000,
            },
            {
                "format_id": "399",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "av01.0.08M.08",
                "acodec": "none",
                "tbr": 3_500,
                "filesize": 100_000,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "abr": 128,
                "filesize": 2_000,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
                "filesize": 3_000,
            },
        ],
        1080,
    )

    assert selection is not None
    assert selection.video_format_id == "299"
    assert selection.audio_format_id == "251"
    assert selection.selector == "299+251"
    assert selection.quality.label == "1080p Full HD"
    assert selection.quality.estimated_filesize == 113_000


def test_720p_prefers_h264_over_vp9_and_av1() -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "298",
                "height": 720,
                "ext": "mp4",
                "vcodec": "avc1.4d401f",
                "acodec": "none",
                "tbr": 2_000,
            },
            {
                "format_id": "302",
                "height": 720,
                "ext": "webm",
                "vcodec": "vp09.00.31.08",
                "acodec": "none",
                "tbr": 1_800,
            },
            {
                "format_id": "398",
                "height": 720,
                "ext": "mp4",
                "vcodec": "av01.0.08M.08",
                "acodec": "none",
                "tbr": 1_700,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
            },
        ],
        720,
    )

    assert selection is not None
    assert selection.selector == "298+251"
    assert selection.quality.label == "720p HD"


@pytest.mark.parametrize(
    ("height", "vp9_format_id", "av1_format_id", "label"),
    [
        (1440, "308", "400", "1440p QHD"),
        (2160, "315", "401", "2160p 4K"),
    ],
)
def test_vp9_is_selected_when_h264_is_not_available(
    height: int,
    vp9_format_id: str,
    av1_format_id: str,
    label: str,
) -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": vp9_format_id,
                "height": height,
                "ext": "webm",
                "vcodec": "vp09.00.40.08",
                "acodec": "none",
                "tbr": 4_000,
            },
            {
                "format_id": av1_format_id,
                "height": height,
                "ext": "mp4",
                "vcodec": "av01.0.12M.08",
                "acodec": "none",
                "tbr": 3_500,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
            },
        ],
        height,
    )

    assert selection is not None
    assert selection.selector == f"{vp9_format_id}+251"
    assert selection.quality.label == label


def test_progressive_h264_aac_mp4_wins_when_it_is_substantially_more_compatible() -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "18",
                "height": 360,
                "ext": "mp4",
                "vcodec": "avc1.42001E",
                "acodec": "mp4a.40.2",
                "tbr": 600,
            },
            {
                "format_id": "394",
                "height": 360,
                "ext": "mp4",
                "vcodec": "av01.0.00M.08",
                "acodec": "none",
                "tbr": 500,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
            },
        ],
        360,
    )

    assert selection is not None
    assert selection.selector == "18"


def test_short_form_video_formats_follow_the_same_quality_rules() -> None:
    selector = QualitySelector()
    qualities = selector.build_qualities(
        [
            {
                "format_id": "160",
                "height": 144,
                "ext": "mp4",
                "vcodec": "avc1.4d400c",
                "acodec": "none",
            },
            {
                "format_id": "247",
                "height": 720,
                "ext": "webm",
                "vcodec": "vp09.00.31.08",
                "acodec": "none",
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "abr": 160,
            },
        ]
    )

    assert [quality.height for quality in qualities] == [144, 720]
    assert [quality.label for quality in qualities] == ["144p", "720p HD"]


def test_progressive_only_video_is_available_without_an_audio_only_stream() -> None:
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "22",
                "height": 720,
                "ext": "mp4",
                "vcodec": "avc1.64001F",
                "acodec": "mp4a.40.2",
                "filesize_approx": 50_000,
            }
        ],
        720,
    )

    assert selection is not None
    assert selection.selector == "22"
    assert selection.quality.estimated_filesize == 50_000


def test_video_only_stream_without_audio_is_not_exposed() -> None:
    selector = QualitySelector()

    assert selector.build_qualities(
        [
            {
                "format_id": "137",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.640028",
                "acodec": "none",
            }
        ]
    ) == []


def test_debug_logging_traces_each_quality_selection_stage(caplog) -> None:
    selector = QualitySelector()
    caplog.set_level(logging.DEBUG, logger="app.services.quality_selector")

    selection = selector.select_for_height(
        [
            {
                "format_id": "399",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "av01.0.09M.08",
                "acodec": "none",
                "filesize": 100_000,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "abr": 128,
                "filesize": 2_000,
            },
        ],
        1080,
    )

    messages = "\n".join(record.getMessage() for record in caplog.records)
    assert selection is not None
    assert "raw_format_count=2" in messages
    assert "format_id=399" in messages
    assert "format_id=140" in messages
    assert "video_candidate_count=1" in messages
    assert "audio_candidate_count=1" in messages
    assert "grouped_resolutions={1080: ['399']}" in messages
    assert "selected_quality_count=1" in messages
