from __future__ import annotations

import pytest

from app.services.download_progress_tracker import DownloadProgressTracker


def test_single_stream_progress_normal() -> None:
    """Test that single-stream downloads map progress across 0..99 normally."""
    tracker = DownloadProgressTracker(format_selector="18")
    assert tracker.expected_streams == 1
    assert tracker.current_stream_index == 0

    assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 0, "total_bytes": 100}) == 0
    assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 25, "total_bytes": 100}) == 25
    assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 50, "total_bytes": 100}) == 50
    assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 99, "total_bytes": 100}) == 99
    assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 100, "total_bytes": 100}) == 99
    assert tracker.update_from_payload({"status": "finished"}) == 99


def test_hls_estimated_total_changes_does_not_decrease_progress() -> None:
    """Test that HLS VBR fluctuations (40 -> 37 -> 41) do not move progress backwards."""
    tracker = DownloadProgressTracker(format_selector="best")

    # 40% of estimated size
    p1 = tracker.update_from_payload({
        "status": "downloading",
        "downloaded_bytes": 40,
        "total_bytes_estimate": 100,
    })
    assert p1 == 40

    # Total estimate increases (e.g. 139MiB -> 154MiB), dropping raw percentage to 37%
    p2 = tracker.update_from_payload({
        "status": "downloading",
        "downloaded_bytes": 37,
        "total_bytes_estimate": 100,
    })
    # Must NOT decrease: clamped to 40
    assert p2 == 40
    assert tracker.get_stream_progress(0) == 40.0

    # Next fragment progresses to 41%
    p3 = tracker.update_from_payload({
        "status": "downloading",
        "downloaded_bytes": 41,
        "total_bytes_estimate": 100,
    })
    assert p3 == 41
    assert tracker.get_stream_progress(0) == 41.0


def test_multiformat_stream_sequence_moves_forward_and_not_stuck_at_99() -> None:
    """Test multi-format download sequence:

    Video: 0 -> 50 -> 99 -> finished
    Audio: 0 -> 6 -> 20 -> 50 -> 100
    Public progress must advance sensibly, never regress, and never freeze at 99 during audio.
    """
    tracker = DownloadProgressTracker(format_selector="312+234")
    assert tracker.expected_streams == 2

    # Video stream (Stream 0)
    p_v0 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 0,
        "total_bytes": 100,
    })
    assert p_v0 == 0
    assert tracker.current_stream_index == 0

    p_v50 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 50,
        "total_bytes": 100,
    })
    assert p_v50 == 42  # 50% of 85% = 42.5 -> 42

    p_v99 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 99,
        "total_bytes": 100,
    })
    assert p_v99 == 84  # 99% of 85% = 84.15 -> 84

    p_v_fin = tracker.update_from_payload({
        "status": "finished",
        "filename": "video.f312.mp4",
    })
    assert p_v_fin == 85  # 100% of video = 85

    # Audio stream (Stream 1) starts
    p_a0 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 0,
        "total_bytes": 100,
    })
    assert tracker.current_stream_index == 1
    assert p_a0 == 85  # Does NOT drop backwards to 0%

    p_a6 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 6,
        "total_bytes": 100,
    })
    assert p_a6 == 85  # 85 + (6% of 14) = 85.84 -> 85

    p_a20 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 20,
        "total_bytes": 100,
    })
    assert p_a20 == 87  # 85 + (20% of 14) = 87.8 -> 87

    p_a50 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 50,
        "total_bytes": 100,
    })
    assert p_a50 == 92  # 85 + (50% of 14) = 92.0 -> 92

    p_a100 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 100,
        "total_bytes": 100,
    })
    assert p_a100 == 99  # 85 + 14 = 99

    p_a_fin = tracker.update_from_payload({
        "status": "finished",
        "filename": "audio.f234.m4a",
    })
    assert p_a_fin == 99

    # Verify monotonic ordering throughout the whole sequence
    sequence = [p_v0, p_v50, p_v99, p_v_fin, p_a0, p_a6, p_a20, p_a50, p_a100, p_a_fin]
    assert sequence == [0, 42, 84, 85, 85, 85, 87, 92, 99, 99]
    for i in range(len(sequence) - 1):
        assert sequence[i] <= sequence[i + 1]


def test_streams_maintain_isolated_state() -> None:
    """Test that stream 0 and stream 1 do not overwrite each other's progress state."""
    tracker = DownloadProgressTracker(format_selector="video+audio")

    tracker.update_from_payload({
        "status": "downloading",
        "info_dict": {"format_id": "video"},
        "downloaded_bytes": 70,
        "total_bytes": 100,
    })
    assert tracker.get_stream_progress(0) == 70.0
    assert tracker.get_stream_progress(1) == 0.0

    tracker.update_from_payload({
        "status": "finished",
        "info_dict": {"format_id": "video"},
    })
    assert tracker.get_stream_progress(0) == 100.0
    assert tracker.get_stream_progress(1) == 0.0

    tracker.update_from_payload({
        "status": "downloading",
        "info_dict": {"format_id": "audio"},
        "downloaded_bytes": 30,
        "total_bytes": 100,
    })
    # Stream 0 state remains 100%, stream 1 state is 30%
    assert tracker.get_stream_progress(0) == 100.0
    assert tracker.get_stream_progress(1) == 30.0


def test_old_99_bug_regression_verification() -> None:
    """Regression test ensuring audio starting after video completion never gets locked at 99."""
    tracker = DownloadProgressTracker(format_selector="312+234")

    # Video completes to 100%
    tracker.update_from_payload({"status": "downloading", "filename": "v.mp4", "downloaded_bytes": 100, "total_bytes": 100})
    tracker.update_from_payload({"status": "finished", "filename": "v.mp4"})

    # In the old bug, the overall progress was 99 at this point.
    # In the new architecture, video completes at 85%.
    assert tracker.get_overall_progress() == 85

    # Audio starts at 6%
    p_audio_start = tracker.update_from_payload({
        "status": "downloading",
        "filename": "a.m4a",
        "downloaded_bytes": 6,
        "total_bytes": 100,
    })
    # Progress is 85, NOT locked at 99!
    assert p_audio_start == 85

    # Audio reaches 50%
    p_audio_mid = tracker.update_from_payload({
        "status": "downloading",
        "filename": "a.m4a",
        "downloaded_bytes": 50,
        "total_bytes": 100,
    })
    # Progress moves forward to 92, NOT stuck at 99!
    assert p_audio_mid == 92
    assert p_audio_mid > p_audio_start


def test_initialization_fragment_spike_does_not_jump_to_85() -> None:
    """1. INITIALIZATION SPIKE
    Simulate payload:
        status="downloading"
        downloaded_bytes=1024
        total_bytes_estimate=1024
        fragment_index=0
        fragment_count=43
    Raw percentage = 100%.
    Assertion: tracker TIDAK boleh menghasilkan 85%. Progress harus tetap berada di awal download.
    """
    tracker = DownloadProgressTracker(format_selector="312+234")
    overall = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 1024,
        "total_bytes_estimate": 1024,
        "fragment_index": 0,
        "fragment_count": 43,
    })
    # Tracker must NOT produce 85%
    assert overall != 85
    assert overall == 0
    assert tracker.get_stream_progress(0) == 0.0


def test_hls_multiformat_full_lifecycle_and_audio_transition() -> None:
    """Tests 1, 2, 3, 4, 5 in realistic lifecycle sequence:
    1. Init spike (frag 0/43, 1024/1024) -> overall 0 (NOT 85)
    2. Follow-up frag 0 (frag 0/43, 3072/44032, raw ~7%) -> moves normal from initial (overall 5)
    3. Real media fragment 1 (frag 1/43, 4.4MB/384.7MB, raw ~1.2%) -> does not drop back to 0 (stays 5)
    4. Video stream finished -> stream reaches 100% internal and overall becomes 85
    5. Audio transition (0% -> 6% -> 20% -> 50% -> 100% -> finished):
       overall: 85 -> 85 -> 87 -> 92 -> 99 -> 99
    """
    tracker = DownloadProgressTracker(format_selector="312+234")
    assert tracker.expected_streams == 2

    # Step 1: Initialization spike (frag 0/43, 1KiB / 1KiB)
    p1 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 1024,
        "total_bytes_estimate": 1024,
        "fragment_index": 0,
        "fragment_count": 43,
    })
    assert p1 == 0
    assert p1 != 85
    assert tracker.get_stream_progress(0) == 0.0

    # Step 2: Follow-up fragment 0 (3KiB / 43KiB, raw ~7%)
    p2 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 3072,
        "total_bytes_estimate": 44032,
        "fragment_index": 0,
        "fragment_count": 43,
    })
    # raw ~6.97% -> 6.97% of 85% = 5.93 -> 5
    assert p2 == 5
    assert p2 >= p1
    assert tracker.get_stream_progress(0) == pytest.approx(6.9767, rel=1e-3)

    # Step 3: Real media fragment 1 (4.4MB / 384.7MB, raw ~1.2%)
    p3 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "video.f312.mp4",
        "downloaded_bytes": 4400000,
        "total_bytes_estimate": 384700000,
        "fragment_index": 1,
        "fragment_count": 43,
    })
    # raw ~1.14%, clamped monotonically to ~6.98% -> overall remains 5 (does NOT drop to 0 or 1)
    assert p3 == 5
    assert p3 >= p2
    assert tracker.get_stream_progress(0) == pytest.approx(6.9767, rel=1e-3)

    # Step 4: Stream finished (video stream complete)
    p4 = tracker.update_from_payload({
        "status": "finished",
        "filename": "video.f312.mp4",
    })
    assert tracker.get_stream_progress(0) == 100.0
    assert p4 == 85

    # Step 5: Audio transition
    # Audio 0%
    p_a0 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 0,
        "total_bytes": 100,
    })
    assert tracker.current_stream_index == 1
    assert p_a0 == 85

    # Audio 6%
    p_a6 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 6,
        "total_bytes": 100,
    })
    assert p_a6 == 85  # 85 + (6% of 14) = 85.84 -> 85

    # Audio 20%
    p_a20 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 20,
        "total_bytes": 100,
    })
    assert p_a20 == 87  # 85 + (20% of 14) = 87.8 -> 87

    # Audio 50%
    p_a50 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 50,
        "total_bytes": 100,
    })
    assert p_a50 == 92  # 85 + (50% of 14) = 92.0 -> 92

    # Audio 100%
    p_a100 = tracker.update_from_payload({
        "status": "downloading",
        "filename": "audio.f234.m4a",
        "downloaded_bytes": 100,
        "total_bytes": 100,
    })
    assert p_a100 == 99  # 85 + (100% of 14) = 99

    # Audio finished
    p_a_fin = tracker.update_from_payload({
        "status": "finished",
        "filename": "audio.f234.m4a",
    })
    assert tracker.get_stream_progress(1) == 100.0
    assert p_a_fin == 99

    # Monotonic progression assertion throughout the whole lifecycle
    overall_seq = [p1, p2, p3, p4, p_a0, p_a6, p_a20, p_a50, p_a100, p_a_fin]
    assert overall_seq == [0, 5, 5, 85, 85, 85, 87, 92, 99, 99]
    for i in range(len(overall_seq) - 1):
        assert overall_seq[i] <= overall_seq[i + 1]


def test_hls_jitter_monotonic_clamp() -> None:
    """6. HLS JITTER
    Simulate:
        40.5 -> 37.4 -> 41.9
    Expected stream progress:
        40.5 -> 40.5 -> 41.9
    Using realistic HLS payloads with fragment metadata.
    """
    tracker = DownloadProgressTracker(format_selector="best")

    # Frag 15/43: 40.5%
    p1 = tracker.update_from_payload({
        "status": "downloading",
        "fragment_index": 15,
        "fragment_count": 43,
        "downloaded_bytes": 40500,
        "total_bytes_estimate": 100000,
    })
    assert tracker.get_stream_progress(0) == pytest.approx(40.5)
    assert p1 == 40

    # Frag 16/43: estimate increases, raw drops to 37.4%
    p2 = tracker.update_from_payload({
        "status": "downloading",
        "fragment_index": 16,
        "fragment_count": 43,
        "downloaded_bytes": 41140,
        "total_bytes_estimate": 110000,
    })
    assert tracker.get_stream_progress(0) == pytest.approx(40.5)
    assert p2 == 40

    # Frag 17/43: download catches up, raw reaches 41.9%
    p3 = tracker.update_from_payload({
        "status": "downloading",
        "fragment_index": 17,
        "fragment_count": 43,
        "downloaded_bytes": 46090,
        "total_bytes_estimate": 110000,
    })
    assert tracker.get_stream_progress(0) == pytest.approx(41.9)
    assert p3 == 41


def test_single_stream_regression_format_18_and_22() -> None:
    """7. SINGLE STREAM REGRESSION
    Ensure single-stream formats (YouTube format 18, 22) are unaffected.
    """
    for fmt in ["18", "22"]:
        tracker = DownloadProgressTracker(format_selector=fmt)
        assert tracker.expected_streams == 1
        assert tracker.current_stream_index == 0

        assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 0, "total_bytes": 1000}) == 0
        assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 250, "total_bytes": 1000}) == 25
        assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 500, "total_bytes": 1000}) == 50
        assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 990, "total_bytes": 1000}) == 99
        assert tracker.update_from_payload({"status": "downloading", "downloaded_bytes": 1000, "total_bytes": 1000}) == 99
        assert tracker.update_from_payload({"status": "finished"}) == 99
        assert tracker.get_stream_progress(0) == 100.0


def test_implicit_stream_transition_by_key_change() -> None:
    """Test stream transition detection when status: finished is not explicitly received."""
    tracker = DownloadProgressTracker(format_selector="312+234")

    tracker.update_from_payload({
        "status": "downloading",
        "filename": "part1.mp4",
        "downloaded_bytes": 80,
        "total_bytes": 100,
    })
    assert tracker.current_stream_index == 0

    # Next payload has different filename without finished status
    tracker.update_from_payload({
        "status": "downloading",
        "filename": "part2.m4a",
        "downloaded_bytes": 40,
        "total_bytes": 100,
    })
    assert tracker.current_stream_index == 1
    assert tracker.get_stream_progress(0) == 100.0
    assert tracker.get_stream_progress(1) == 40.0
