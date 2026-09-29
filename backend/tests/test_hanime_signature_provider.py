from __future__ import annotations

import asyncio
import logging
import os
import time
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.platforms.hanime.signature_provider import (
    HanimeSignature,
    HanimeSignatureError,
    HanimeSignatureProvider,
    HanimeSignatureProviderError,
    get_hanime_signature_provider,
    is_hanime_provider_enabled,
    reset_hanime_signature_provider,
)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# ==============================================================================
# 1. SIGNATURE MODEL VALIDATION
# ==============================================================================

def test_hanime_signature_model_fields_and_expiration() -> None:
    t0 = time.monotonic()
    sig = HanimeSignature(
        signature="test_signature_hash_123",
        stime="1790000000",
        version="web2",
        created_at=t0,
    )

    assert sig.signature == "test_signature_hash_123"
    assert sig.stime == "1790000000"
    assert sig.version == "web2"
    assert sig.created_at == t0

    # Unexpired at T+30s
    assert sig.is_expired(ttl_seconds=60.0, now=t0 + 30.0) is False
    # Expired at T+60.1s
    assert sig.is_expired(ttl_seconds=60.0, now=t0 + 60.1) is True


# ==============================================================================
# MOCK PLAYWRIGHT FIXTURES
# ==============================================================================

def _create_mock_playwright(
    *,
    signature_val: str = "mocked_sig_abc_123",
    stime_val: str = "1790123456",
    evaluate_side_effect: Any | None = None,
) -> tuple[AsyncMock, MagicMock, MagicMock, MagicMock]:
    """Create a fully mocked hierarchy of Playwright -> Browser -> Context -> Page."""
    mock_page = AsyncMock()
    mock_page.url = "https://hanime.tv/"
    mock_page.goto = AsyncMock()
    mock_page.wait_for_function = AsyncMock()
    mock_page.close = AsyncMock()

    if evaluate_side_effect is not None:
        mock_page.evaluate = AsyncMock(side_effect=evaluate_side_effect)
    else:
        async def _eval(expr: str) -> Any:
            if "ssignature" in expr:
                return signature_val
            if "stime" in expr:
                return stime_val
            return None
        mock_page.evaluate = AsyncMock(side_effect=_eval)

    mock_context = AsyncMock()
    mock_context.new_page = AsyncMock(return_value=mock_page)
    mock_context.close = AsyncMock()

    mock_browser = AsyncMock()
    mock_browser.new_context = AsyncMock(return_value=mock_context)
    mock_browser.close = AsyncMock()

    mock_chromium = AsyncMock()
    mock_chromium.launch = AsyncMock(return_value=mock_browser)

    mock_playwright = AsyncMock()
    mock_playwright.chromium = mock_chromium
    mock_playwright.stop = AsyncMock()

    return mock_playwright, mock_browser, mock_context, mock_page


# ==============================================================================
# 2. LIFECYCLE TESTS (START / CLOSE / IDEMPOTENCE)
# ==============================================================================

@pytest.mark.anyio
async def test_provider_lifecycle_start_and_close() -> None:
    mock_playwright, mock_browser, mock_context, mock_page = _create_mock_playwright()

    provider = HanimeSignatureProvider(
        playwright_launcher=AsyncMock(return_value=mock_playwright),
    )

    assert provider.is_started is False
    await provider.start()
    assert provider.is_started is True
    assert mock_playwright.chromium.launch.called

    # Multiple start calls are idempotent
    await provider.start()
    assert mock_playwright.chromium.launch.call_count == 1

    # Close shuts down all handles
    await provider.close()
    assert provider.is_started is False
    assert mock_page.close.called
    assert mock_context.close.called
    assert mock_browser.close.called
    assert mock_playwright.stop.called

    # Close is idempotent
    await provider.close()


# ==============================================================================
# 3. SIGNATURE GENERATION & CACHING
# ==============================================================================

@pytest.mark.anyio
async def test_get_signature_generates_and_caches() -> None:
    mock_pw, _, _, mock_page = _create_mock_playwright(
        signature_val="sig_alpha",
        stime_val="1000",
    )
    provider = HanimeSignatureProvider(
        ttl_seconds=60.0,
        playwright_launcher=AsyncMock(return_value=mock_pw),
    )

    # 1. First retrieval triggers evaluation
    sig1 = await provider.get_signature()
    assert sig1.signature == "sig_alpha"
    assert sig1.stime == "1000"
    assert sig1.version == "web2"
    assert mock_page.evaluate.call_count == 2  # 1 for ssignature, 1 for stime

    # 2. Subsequent call within TTL returns cached credential without page evaluate
    sig2 = await provider.get_signature()
    assert sig2 == sig1
    assert mock_page.evaluate.call_count == 2  # Not called again

    # 3. Expired cache (simulated by setting created_at in the past)
    provider._cached_signature = HanimeSignature(
        signature="sig_alpha",
        stime="1000",
        version="web2",
        created_at=time.monotonic() - 70.0,
    )
    # Update page mock for fresh credentials
    async def _new_eval(expr: str) -> str:
        return "sig_beta" if "ssignature" in expr else "2000"
    mock_page.evaluate = AsyncMock(side_effect=_new_eval)

    sig3 = await provider.get_signature()
    assert sig3.signature == "sig_beta"
    assert sig3.stime == "2000"
    assert mock_page.evaluate.call_count == 2

    await provider.close()


@pytest.mark.anyio
async def test_force_refresh_bypasses_valid_cache() -> None:
    mock_pw, _, _, mock_page = _create_mock_playwright(
        signature_val="sig_v1",
        stime_val="100",
    )
    provider = HanimeSignatureProvider(
        ttl_seconds=60.0,
        playwright_launcher=AsyncMock(return_value=mock_pw),
    )

    sig1 = await provider.get_signature()
    assert sig1.signature == "sig_v1"

    async def _v2_eval(expr: str) -> str:
        return "sig_v2" if "ssignature" in expr else "200"
    mock_page.evaluate = AsyncMock(side_effect=_v2_eval)

    # force_refresh=True refreshes even though cache is not expired
    sig2 = await provider.get_signature(force_refresh=True)
    assert sig2.signature == "sig_v2"

    await provider.close()


# ==============================================================================
# 4. CONCURRENCY: SERIALIZATION AND DEDUPLICATION
# ==============================================================================

@pytest.mark.anyio
async def test_concurrent_callers_do_not_duplicate_signatures() -> None:
    eval_call_count = 0

    async def _slow_eval(expr: str) -> str:
        nonlocal eval_call_count
        eval_call_count += 1
        await asyncio.sleep(0.05)  # Simulate page evaluate latency
        return "concurrent_sig" if "ssignature" in expr else "5555"

    mock_pw, _, _, mock_page = _create_mock_playwright(
        evaluate_side_effect=_slow_eval,
    )
    provider = HanimeSignatureProvider(
        ttl_seconds=60.0,
        playwright_launcher=AsyncMock(return_value=mock_pw),
    )

    # Launch 5 simultaneous requests
    results = await asyncio.gather(
        provider.get_signature(),
        provider.get_signature(),
        provider.get_signature(),
        provider.get_signature(),
        provider.get_signature(),
    )

    assert len(results) == 5
    first_sig = results[0]
    for r in results:
        assert r.signature == "concurrent_sig"
        assert r.stime == "5555"
        assert r == first_sig

    # Even with 5 concurrent callers, page evaluate was only executed once (2 calls: ssignature + stime)
    assert eval_call_count == 2

    await provider.close()


# ==============================================================================
# 5. ERROR HANDLING & BROWSER CRASH RECOVERY
# ==============================================================================

@pytest.mark.anyio
async def test_browser_launch_failure_raises_controlled_error() -> None:
    async def _failing_launcher() -> None:
        raise RuntimeError("Chromium binary not found")

    provider = HanimeSignatureProvider(playwright_launcher=_failing_launcher)

    with pytest.raises(HanimeSignatureProviderError, match="Failed to initialize browser resources"):
        await provider.start()


@pytest.mark.anyio
async def test_empty_signature_from_runtime_raises_controlled_error() -> None:
    mock_pw, _, _, _ = _create_mock_playwright(signature_val="", stime_val="")
    provider = HanimeSignatureProvider(playwright_launcher=AsyncMock(return_value=mock_pw))

    with pytest.raises(HanimeSignatureProviderError, match="Failed to generate Hanime signature"):
        await provider.get_signature()

    await provider.close()


@pytest.mark.anyio
async def test_browser_failure_triggers_recovery_and_succeeds() -> None:
    """When a transient evaluation/page crash occurs, provider recovers and retries once."""
    attempts = 0

    async def _eval_with_first_failure(expr: str) -> str:
        nonlocal attempts
        attempts += 1
        if attempts == 1:  # First evaluate call fails
            raise RuntimeError("Execution context was destroyed")
        return "recovered_sig" if "ssignature" in expr else "9999"

    mock_pw, _, _, mock_page = _create_mock_playwright(
        evaluate_side_effect=_eval_with_first_failure,
    )
    provider = HanimeSignatureProvider(playwright_launcher=AsyncMock(return_value=mock_pw))

    sig = await provider.get_signature()
    assert sig.signature == "recovered_sig"
    assert sig.stime == "9999"
    # 1 failed attempt + 2 successful calls in retry (ssignature + stime)
    assert attempts == 3

    await provider.close()


@pytest.mark.anyio
async def test_failed_recovery_raises_controlled_error() -> None:
    """If recovery retry also fails, it raises HanimeSignatureProviderError without infinite loop."""
    mock_pw, _, _, mock_page = _create_mock_playwright(
        evaluate_side_effect=RuntimeError("Persistent browser crash"),
    )
    provider = HanimeSignatureProvider(playwright_launcher=AsyncMock(return_value=mock_pw))

    with pytest.raises(HanimeSignatureProviderError, match="after recovery attempt"):
        await provider.get_signature()

    await provider.close()


# ==============================================================================
# 6. LOGGING & SECURITY AUDIT
# ==============================================================================

@pytest.mark.anyio
async def test_credentials_are_never_emitted_in_logs(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG)

    secret_signature = "SECRET_HEX_SIGNATURE_999888777"
    secret_stime = "9876543210"

    mock_pw, _, _, _ = _create_mock_playwright(
        signature_val=secret_signature,
        stime_val=secret_stime,
    )
    provider = HanimeSignatureProvider(playwright_launcher=AsyncMock(return_value=mock_pw))

    await provider.start()
    sig = await provider.get_signature()
    # Cache hit
    await provider.get_signature()
    await provider.close()

    assert sig.signature == secret_signature

    # Inspect all logs emitted by the provider
    all_logs = " ".join(record.message for record in caplog.records)

    # Verification: neither secret_signature nor secret_stime appears in logs
    assert secret_signature not in all_logs
    assert secret_stime not in all_logs

    # Confirm safe lifecycle messages were logged
    assert any("HanimeSignatureProvider started" in r.message for r in caplog.records)
    assert any("refreshed successfully" in r.message for r in caplog.records)
    assert any("cache hit" in r.message for r in caplog.records)


# ==============================================================================
# 7. SINGLETON HELPER TESTS
# ==============================================================================

def test_singleton_get_and_reset() -> None:
    reset_hanime_signature_provider()
    p1 = get_hanime_signature_provider()
    p2 = get_hanime_signature_provider()
    assert p1 is p2

    reset_hanime_signature_provider()
    p3 = get_hanime_signature_provider()
    assert p3 is not p1
    reset_hanime_signature_provider()


# ==============================================================================
# 8. OPTIONAL LIVE INTEGRATION TEST (SKIPPED BY DEFAULT)
# ==============================================================================

@pytest.mark.integration
@pytest.mark.skipif(
    os.environ.get("NEXORA_HANIME_LIVE_INTEGRATION_TEST") != "1",
    reason="Live integration test requires NEXORA_HANIME_LIVE_INTEGRATION_TEST=1",
)
@pytest.mark.anyio
async def test_live_playwright_signature_generation() -> None:
    """Optional end-to-end integration test validating real browser against Hanime."""
    provider = HanimeSignatureProvider(enabled=True)
    try:
        await provider.start()
        sig = await provider.get_signature()

        assert sig.signature != ""
        assert len(sig.signature) == 64
        assert sig.stime != ""
        assert sig.version == "web2"
    finally:
        await provider.close()
