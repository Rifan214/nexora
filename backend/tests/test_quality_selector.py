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


def test_portrait_video_uses_its_short_edge_for_familiar_quality_labels() -> None:
    selector = QualitySelector()

    qualities = selector.build_qualities(
        [
            {
                "format_id": "tiktok-720",
                "width": 720,
                "height": 1280,
                "ext": "mp4",
                "vcodec": "h264",
                "acodec": "aac",
            },
            {
                "format_id": "tiktok-1080",
                "width": 1080,
                "height": 1920,
                "ext": "mp4",
                "vcodec": "h265",
                "acodec": "aac",
            },
        ]
    )

    assert [quality.height for quality in qualities] == [720, 1080]
    assert [quality.label for quality in qualities] == ["720p HD", "1080p Full HD"]


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


def test_x_style_hls_audio_rendition_without_an_acodec_is_recognized() -> None:
    selector = QualitySelector()
    audio_rendition = {
        "format_id": "hls-audio-high",
        "vcodec": "none",
        "acodec": None,
        "video_ext": "none",
        "audio_ext": "mp4",
        "protocol": "m3u8_native",
        "abr": 128,
    }

    assert selector.has_audio_available([audio_rendition]) is True
    assert selector._is_audio_only(audio_rendition) is True


def test_conventional_audio_format_with_an_acodec_remains_recognized() -> None:
    selector = QualitySelector()
    audio_format = {
        "format_id": "251",
        "vcodec": "none",
        "acodec": "opus",
        "ext": "webm",
        "protocol": "https",
    }

    assert selector.has_audio_available([audio_format]) is True
    assert selector._is_audio_only(audio_format) is True


def test_video_only_hls_format_is_not_recognized_as_audio() -> None:
    selector = QualitySelector()
    video_format = {
        "format_id": "hls-720",
        "width": 1280,
        "height": 720,
        "vcodec": "avc1.64001F",
        "acodec": "none",
        "video_ext": "mp4",
        "audio_ext": "none",
        "protocol": "m3u8_native",
    }

    assert selector.has_audio_available([video_format]) is False
    assert selector._is_audio_only(video_format) is False
    assert selector.build_qualities([video_format]) == []


@pytest.mark.parametrize(
    "format_item",
    [
        {
            "format_id": "direct-video-less",
            "vcodec": "none",
            "acodec": None,
            "video_ext": "none",
            "audio_ext": "mp4",
            "protocol": "https",
        },
        {
            "format_id": "hls-with-video-extension",
            "vcodec": "none",
            "acodec": None,
            "video_ext": "mp4",
            "audio_ext": "mp4",
            "protocol": "m3u8_native",
        },
        {
            "format_id": "hls-without-audio-extension",
            "vcodec": "none",
            "acodec": None,
            "video_ext": "none",
            "audio_ext": "none",
            "protocol": "m3u8_native",
        },
    ],
)
def test_invalid_hls_audio_marker_combinations_are_not_recognized(format_item: dict) -> None:
    selector = QualitySelector()

    assert selector.has_audio_available([format_item]) is False
    assert selector._is_audio_only(format_item) is False


def test_x_hls_video_variants_pair_with_the_highest_bitrate_hls_audio_rendition() -> None:
    selector = QualitySelector()
    selections = selector.select_qualities(
        [
            {
                "format_id": "hls-audio-low",
                "vcodec": "none",
                "acodec": None,
                "video_ext": "none",
                "audio_ext": "mp4",
                "protocol": "m3u8_native",
                "abr": 32,
            },
            {
                "format_id": "hls-audio-high",
                "vcodec": "none",
                "acodec": None,
                "video_ext": "none",
                "audio_ext": "mp4",
                "protocol": "m3u8_native",
                "abr": 128,
            },
            {
                "format_id": "hls-320",
                "width": 320,
                "height": 568,
                "ext": "mp4",
                "vcodec": "avc1.4D401E",
                "acodec": "none",
                "video_ext": "mp4",
                "audio_ext": "none",
                "protocol": "m3u8_native",
            },
            {
                "format_id": "hls-480",
                "width": 480,
                "height": 852,
                "ext": "mp4",
                "vcodec": "avc1.4D401F",
                "acodec": "none",
                "video_ext": "mp4",
                "audio_ext": "none",
                "protocol": "m3u8_native",
            },
            {
                "format_id": "hls-720",
                "width": 720,
                "height": 1280,
                "ext": "mp4",
                "vcodec": "avc1.64001F",
                "acodec": "none",
                "video_ext": "mp4",
                "audio_ext": "none",
                "protocol": "m3u8_native",
            },
        ],
        platform="twitter",
    )

    assert [selection.quality.height for selection in selections] == [320, 480, 720]
    assert [selection.selector for selection in selections] == [
        "hls-320+hls-audio-high",
        "hls-480+hls-audio-high",
        "hls-720+hls-audio-high",
    ]


def test_x_video_only_fallback_exposes_direct_formats_without_audio() -> None:
    selector = QualitySelector()

    selections = selector.select_qualities(_x_video_only_formats(), platform="twitter")

    assert [selection.quality.height for selection in selections] == [320, 480, 720]
    assert [selection.selector for selection in selections] == [
        "http-632",
        "http-950",
        "http-2176",
    ]
    assert all(selection.audio_format_id is None for selection in selections)


@pytest.mark.parametrize("platform", [None, "youtube", "tiktok"])
def test_x_video_only_fallback_does_not_apply_to_other_platforms(
    platform: str | None,
) -> None:
    selector = QualitySelector()

    assert selector.select_qualities(
        _x_video_only_formats(),
        platform=platform,
    ) == []


def test_x_video_only_fallback_rejects_ambiguous_direct_formats() -> None:
    selector = QualitySelector()

    selections = selector.select_qualities(
        [
            {
                "format_id": "ambiguous-http",
                "width": 720,
                "height": 1280,
                "ext": "mp4",
                "vcodec": None,
                "acodec": None,
                "video_ext": "none",
                "audio_ext": "none",
                "protocol": "https",
            }
        ],
        platform="twitter",
    )

    assert selections == []


def _x_video_only_formats() -> list[dict]:
    formats = []
    for format_id, width, height, bitrate in (
        ("http-632", 320, 568, 632),
        ("http-950", 480, 852, 950),
        ("http-2176", 720, 1280, 2176),
    ):
        formats.append(
            {
                "format_id": format_id,
                "width": width,
                "height": height,
                "ext": "mp4",
                "vcodec": None,
                "acodec": None,
                "video_ext": "mp4",
                "audio_ext": "none",
                "protocol": "https",
                "tbr": bitrate,
            }
        )
    formats.append(
        {
            "format_id": "hls-1694",
            "width": 720,
            "height": 1280,
            "ext": "mp4",
            "vcodec": "avc1.64001F",
            "acodec": "none",
            "video_ext": "mp4",
            "audio_ext": "none",
            "protocol": "m3u8_native",
            "tbr": 1694,
        }
    )
    return formats


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


def test_quality_selector_youtube_avoids_blocked_progressive_18() -> None:
    selector = QualitySelector()
    formats = [
        {
            "format_id": "18",
            "height": 360,
            "ext": "mp4",
            "vcodec": "avc1.42001E",
            "acodec": "mp4a.40.2",
            "filesize": 12_000,
        },
        {
            "format_id": "134",
            "height": 360,
            "ext": "mp4",
            "vcodec": "avc1.4d401e",
            "acodec": "none",
            "filesize": 8_000,
        },
        {
            "format_id": "251",
            "ext": "webm",
            "vcodec": "none",
            "acodec": "opus",
            "abr": 160,
            "filesize": 3_000,
        },
    ]

    # For YouTube, adaptive 134+251 must be selected and format 18 must be avoided
    youtube_selection = selector.select_for_height(formats, 360, platform="youtube")
    assert youtube_selection is not None
    assert youtube_selection.selector == "134+251"
    assert youtube_selection.video_format_id == "134"
    assert youtube_selection.audio_format_id == "251"
    assert youtube_selection.selector != "18"

    # For generic / other platforms, progressive format 18 continues to be selected without merge
    generic_selection = selector.select_for_height(formats, 360)
    assert generic_selection is not None
    assert generic_selection.selector == "18"


def test_hls_video_prefers_hls_audio_over_dash_audio() -> None:
    """A: HLS video + HLS audio -> HLS audio is preferred even if DASH audio reports higher bitrate."""
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "312",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.64002A",
                "acodec": "none",
                "protocol": "m3u8_native",
                "tbr": 6200,
            },
            {
                "format_id": "234",
                "ext": "mp4",
                "vcodec": "none",
                "video_ext": "none",
                "audio_ext": "mp4",
                "acodec": None,
                "protocol": "m3u8_native",
                "abr": 128,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "protocol": "https",
                "abr": 160,
            },
        ],
        1080,
    )
    assert selection is not None
    assert selection.video_format_id == "312"
    assert selection.audio_format_id == "234"
    assert selection.selector == "312+234"


def test_hls_audio_with_missing_bitrate_does_not_rank_as_zero() -> None:
    """B: HLS video + HLS audio with missing abr/tbr -> missing bitrate does not make HLS audio rank as zero."""
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "312",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.64002A",
                "acodec": "none",
                "protocol": "m3u8_native",
                "tbr": 6200,
            },
            {
                "format_id": "hls-audio-unspecified",
                "ext": "mp4",
                "vcodec": "none",
                "video_ext": "none",
                "audio_ext": "mp4",
                "acodec": None,
                "protocol": "m3u8_native",
                "abr": None,
                "tbr": None,
                "format_note": "Default, high",
            },
            {
                "format_id": "hls-audio-low",
                "ext": "mp4",
                "vcodec": "none",
                "video_ext": "none",
                "audio_ext": "mp4",
                "acodec": None,
                "protocol": "m3u8_native",
                "abr": None,
                "tbr": None,
                "format_note": "Default, low",
            },
        ],
        1080,
    )
    assert selection is not None
    assert selection.audio_format_id == "hls-audio-unspecified"
    assert selection.selector == "312+hls-audio-unspecified"


def test_hls_video_falls_back_to_dash_audio_when_no_hls_audio_exists() -> None:
    """C: HLS video + DASH audio only -> DASH audio remains usable as fallback if no HLS audio exists."""
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "312",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.64002A",
                "acodec": "none",
                "protocol": "m3u8_native",
                "tbr": 6200,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "protocol": "https",
                "abr": 128,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "protocol": "https",
                "abr": 160,
            },
        ],
        1080,
    )
    assert selection is not None
    assert selection.video_format_id == "312"
    assert selection.audio_format_id == "251"
    assert selection.selector == "312+251"


def test_non_hls_video_pairs_with_dash_audio_preserving_existing_behavior() -> None:
    """D: Non-HLS video + normal DASH audio -> existing behavior remains unchanged."""
    selector = QualitySelector()
    selection = selector.select_for_height(
        [
            {
                "format_id": "299",
                "height": 1080,
                "ext": "mp4",
                "vcodec": "avc1.64002A",
                "acodec": "none",
                "protocol": "https",
                "tbr": 5200,
            },
            {
                "format_id": "234",
                "ext": "mp4",
                "vcodec": "none",
                "video_ext": "none",
                "audio_ext": "mp4",
                "acodec": None,
                "protocol": "m3u8_native",
                "abr": 128,
            },
            {
                "format_id": "140",
                "ext": "m4a",
                "vcodec": "none",
                "acodec": "mp4a.40.2",
                "protocol": "https",
                "abr": 128,
            },
            {
                "format_id": "251",
                "ext": "webm",
                "vcodec": "none",
                "acodec": "opus",
                "protocol": "https",
                "abr": 160,
            },
        ],
        1080,
    )
    assert selection is not None
    assert selection.video_format_id == "299"
    assert selection.audio_format_id == "251"
    assert selection.selector == "299+251"


def test_youtube_1080p_selects_hls_pair_312_plus_234_over_140() -> None:
    """E: Known YouTube case: 312 + 234 is selected instead of 312 + 140."""
    selector = QualitySelector()
    formats = [
        {
            "format_id": "312",
            "height": 1080,
            "ext": "mp4",
            "vcodec": "avc1.64002A",
            "acodec": "none",
            "protocol": "m3u8_native",
            "tbr": 6266.8,
            "fps": 60,
        },
        {
            "format_id": "299",
            "height": 1080,
            "ext": "mp4",
            "vcodec": "avc1.64002A",
            "acodec": "none",
            "protocol": "https",
            "tbr": 5262.7,
            "fps": 60,
        },
        {
            "format_id": "233",
            "ext": "mp4",
            "vcodec": "none",
            "video_ext": "none",
            "audio_ext": "mp4",
            "acodec": None,
            "protocol": "m3u8_native",
            "format_note": "Default, low",
            "abr": None,
            "tbr": None,
            "url": "https://manifest.googlevideo.com/.../sgoap/clen%3D1288760%3Bdur%3D211.208%3B...",
        },
        {
            "format_id": "234",
            "ext": "mp4",
            "vcodec": "none",
            "video_ext": "none",
            "audio_ext": "mp4",
            "acodec": None,
            "protocol": "m3u8_native",
            "format_note": "Default, high",
            "abr": None,
            "tbr": None,
            "url": "https://manifest.googlevideo.com/.../sgoap/clen%3D3417528%3Bdur%3D211.115%3B...",
        },
        {
            "format_id": "140",
            "ext": "m4a",
            "vcodec": "none",
            "acodec": "mp4a.40.2",
            "protocol": "https",
            "abr": 129.5,
            "tbr": 129.5,
            "asr": 44100,
            "filesize": 3417528,
        },
        {
            "format_id": "251",
            "ext": "webm",
            "vcodec": "none",
            "acodec": "opus",
            "protocol": "https",
            "abr": 121.6,
            "tbr": 121.6,
            "asr": 48000,
            "filesize": 3209128,
        },
    ]

    selection = selector.select_for_height(formats, 1080, platform="youtube")
    assert selection is not None
    assert selection.video_format_id == "312"
    assert selection.audio_format_id == "234"
    assert selection.selector == "312+234"
    assert selection.audio_format_id != "140"

