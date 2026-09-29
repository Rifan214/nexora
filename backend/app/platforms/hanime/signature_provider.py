from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import logging
import os
import time
from typing import Any

logger = logging.getLogger(__name__)

_DEFAULT_SIGNATURE_TTL_SECONDS = 60.0
_DEFAULT_NAV_TIMEOUT_MS = 20000
_DEFAULT_WAIT_TIMEOUT_MS = 15000
_HANIME_ROOT_URL = "https://hanime.tv/"
_HOST_RESOLVER_RULES = "MAP hanime.tv 104.21.18.100, MAP *.hanime.tv 104.21.18.100"
_DEFAULT_BROWSER_ARGS = (
    f"--host-resolver-rules={_HOST_RESOLVER_RULES}",
    "--disable-dev-shm-usage",
    "--no-sandbox",
)


class HanimeSignatureError(Exception):
    """Base exception for Hanime signature errors."""


class HanimeSignatureProviderError(HanimeSignatureError):
    """Raised when the signature provider fails to initialize or generate a credential."""


@dataclass(frozen=True)
class HanimeSignature:
    """Represents a time-bound verification credential for Hanime API requests."""

    signature: str
    stime: str
    version: str = "web2"
    created_at: float = field(default_factory=time.monotonic)

    def is_expired(self, ttl_seconds: float = _DEFAULT_SIGNATURE_TTL_SECONDS, *, now: float | None = None) -> bool:
        current = now if now is not None else time.monotonic()
        return (current - self.created_at) >= ttl_seconds


def is_hanime_provider_enabled() -> bool:
    """Determine whether the signature provider should eagerly start on application startup."""
    val = os.environ.get("NEXORA_HANIME_SIGNATURE_PROVIDER_ENABLED", "").strip().lower()
    if val in ("0", "false", "no", "off"):
        return False
    # If running under pytest and not explicitly enabled, keep false to avoid browser overhead in unrelated tests
    if "PYTEST_CURRENT_TEST" in os.environ and val != "true":
        return False
    return True


class HanimeSignatureProvider:
    """Manages a persistent, reusable Playwright Chromium browser to provide Hanime web signatures."""

    def __init__(
        self,
        *,
        ttl_seconds: float = _DEFAULT_SIGNATURE_TTL_SECONDS,
        browser_args: list[str] | None = None,
        enabled: bool = True,
        headless: bool = True,
        playwright_launcher: Any | None = None,
    ) -> None:
        self._ttl_seconds = ttl_seconds
        self._browser_args = browser_args or list(_DEFAULT_BROWSER_ARGS)
        self.enabled = enabled
        self._headless = headless
        self._playwright_launcher = playwright_launcher
        self._active_lock: asyncio.Lock | None = None
        self._active_lock_loop: Any = None
        self._cached_signature: HanimeSignature | None = None
        self._playwright: Any = None
        self._browser: Any = None
        self._context: Any = None
        self._page: Any = None
        self._started = False

    @property
    def _lock(self) -> asyncio.Lock:
        try:
            current_loop = asyncio.get_running_loop()
        except RuntimeError:
            current_loop = None
        if self._active_lock is None or self._active_lock_loop != current_loop:
            self._active_lock = asyncio.Lock()
            self._active_lock_loop = current_loop
        return self._active_lock

    @property
    def is_started(self) -> bool:
        return self._started

    @property
    def has_cached_signature(self) -> bool:
        return self._cached_signature is not None and not self._cached_signature.is_expired(self._ttl_seconds)

    async def start(self) -> None:
        """Initialize reusable Playwright and browser resources."""
        if not self.enabled:
            logger.debug("HanimeSignatureProvider is disabled; skipping startup")
            return

        async with self._lock:
            if self._started:
                return
            try:
                await self._init_browser_resources()
                self._started = True
                logger.info("HanimeSignatureProvider started successfully")
            except Exception as exc:
                logger.error("Failed to start HanimeSignatureProvider: %s", exc)
                await self._dispose_browser_resources()
                raise HanimeSignatureProviderError(
                    f"Failed to initialize browser resources: {exc.__class__.__name__}"
                ) from exc

    async def close(self) -> None:
        """Close browser, context, and Playwright subprocess cleanly (idempotent)."""
        async with self._lock:
            if not self._started and self._playwright is None:
                return
            await self._dispose_browser_resources()
            self._cached_signature = None
            self._started = False
            logger.info("HanimeSignatureProvider closed successfully")

    async def get_signature(self, *, force_refresh: bool = False) -> HanimeSignature:
        """Retrieve a valid Hanime web signature, using cache when valid.

        Concurrent calls are serialized to prevent duplicate browser executions.
        """
        # Fast path: unexpired cache check
        cached = self._cached_signature
        if not force_refresh and cached is not None and not cached.is_expired(self._ttl_seconds):
            logger.debug("Hanime signature cache hit")
            return cached

        async with self._lock:
            # Double-checked locking inside the lock
            cached = self._cached_signature
            if not force_refresh and cached is not None and not cached.is_expired(self._ttl_seconds):
                logger.debug("Hanime signature cache hit (post-lock)")
                return cached

            sig = await self._generate_with_recovery()
            self._cached_signature = sig
            logger.info("Hanime signature refreshed successfully (version=%s)", sig.version)
            return sig

    async def _init_browser_resources(self) -> None:
        """Launch Playwright Chromium and prepare a single reusable page."""
        if self._playwright_launcher is not None:
            self._playwright = await self._playwright_launcher()
        else:
            from playwright.async_api import async_playwright
            self._playwright = await async_playwright().start()

        self._browser = await self._playwright.chromium.launch(
            headless=self._headless,
            args=self._browser_args,
        )
        self._context = await self._browser.new_context()
        self._page = await self._context.new_page()

    async def _dispose_browser_resources(self) -> None:
        """Close all browser and Playwright handles safely without throwing."""
        if self._page is not None:
            try:
                await self._page.close()
            except Exception:
                pass
            self._page = None

        if self._context is not None:
            try:
                await self._context.close()
            except Exception:
                pass
            self._context = None

        if self._browser is not None:
            try:
                await self._browser.close()
            except Exception:
                pass
            self._browser = None

        if self._playwright is not None:
            try:
                await self._playwright.stop()
            except Exception:
                pass
            self._playwright = None

    async def _generate_with_recovery(self) -> HanimeSignature:
        """Generate a signature, retrying once if browser resources have degraded."""
        if not self._started or self._page is None:
            await self._init_browser_resources()
            self._started = True

        try:
            return await self._extract_signature_from_page()
        except Exception as exc:
            logger.warning(
                "Hanime signature generation failed (%s); attempting browser recovery",
                exc.__class__.__name__,
            )
            try:
                await self._dispose_browser_resources()
                await self._init_browser_resources()
                return await self._extract_signature_from_page()
            except Exception as retry_exc:
                logger.error("Hanime signature recovery retry failed: %s", retry_exc)
                raise HanimeSignatureProviderError(
                    "Failed to generate Hanime signature after recovery attempt."
                ) from retry_exc

    async def _extract_signature_from_page(self) -> HanimeSignature:
        """Navigate to root page and read window.ssignature and window.stime."""
        if self._page is None:
            raise HanimeSignatureProviderError("Browser page is not initialized.")

        # Navigate only if not already on the Hanime root
        current_url = self._page.url or ""
        if not current_url.startswith(_HANIME_ROOT_URL):
            await self._page.goto(
                _HANIME_ROOT_URL,
                timeout=_DEFAULT_NAV_TIMEOUT_MS,
                wait_until="domcontentloaded",
            )

        # Wait for the client-side Wasm runtime to populate the signature
        await self._page.wait_for_function(
            "() => Boolean(window.ssignature && window.stime)",
            timeout=_DEFAULT_WAIT_TIMEOUT_MS,
        )

        sig = await self._page.evaluate("window.ssignature")
        stime = await self._page.evaluate("window.stime")

        if not sig or not stime:
            raise HanimeSignatureProviderError("Browser runtime returned empty signature or stime.")

        return HanimeSignature(
            signature=str(sig),
            stime=str(stime),
            version="web2",
            created_at=time.monotonic(),
        )


_global_provider: HanimeSignatureProvider | None = None


def get_hanime_signature_provider() -> HanimeSignatureProvider:
    """Return the global HanimeSignatureProvider singleton."""
    global _global_provider
    if _global_provider is None:
        _global_provider = HanimeSignatureProvider(enabled=is_hanime_provider_enabled())
    return _global_provider


def reset_hanime_signature_provider() -> None:
    """Reset the global provider singleton (useful for isolated tests)."""
    global _global_provider
    _global_provider = None

def reset_hanime_signature_provider() -> None:
    """Reset the global provider singleton (useful for isolated tests)."""
    global _global_provider
    _global_provider = None
