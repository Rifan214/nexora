from __future__ import annotations

import logging
from typing import Any
from urllib.parse import urlsplit

import yt_dlp
from yt_dlp.networking._urllib import RedirectHandler

from app.platforms.rule34video.constants import (
    MAX_REDIRECT_HOPS,
    RULE34VIDEO_REFERER,
    RULE34VIDEO_USER_AGENT,
)
from app.platforms.rule34video.exceptions import (
    Rule34VideoNetworkError,
    Rule34VideoSecurityError,
)
from app.platforms.rule34video.http_client import (
    sanitize_url_for_logging,
    validate_url_security,
    verify_resolved_ip_is_safe,
)

logger = logging.getLogger(__name__)


class SafeRule34VideoRedirectHandler(RedirectHandler):
    """yt-dlp redirect handler enforcing Rule34Video origin, CDN allowlist, and SSRF restrictions."""

    def __init__(self, *, max_hops: int = MAX_REDIRECT_HOPS) -> None:
        super().__init__()
        self.max_hops = max_hops
        self._hops = 0

    def redirect_request(
        self,
        req: Any,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> Any:
        self._hops += 1
        logger.debug(
            "yt-dlp intercepted redirect hop=%d newurl=%s",
            self._hops,
            sanitize_url_for_logging(newurl),
        )

        if self._hops > self.max_hops:
            raise Rule34VideoNetworkError(
                f"Exceeded maximum redirect hops ({self.max_hops})."
            )

        validate_url_security(newurl, allow_cdn=True)
        parsed = urlsplit(newurl)
        if parsed.hostname:
            verify_resolved_ip_is_safe(parsed.hostname)

        # Let the base handler construct the redirected request
        redirected_req = super().redirect_request(req, fp, code, msg, headers, newurl)

        # Cross-origin header hygiene: avoid forwarding sensitive headers across origins
        if req is not None and redirected_req is not None:
            old_url = getattr(req, "full_url", getattr(req, "url", None))
            if old_url:
                old_origin = urlsplit(old_url).netloc.casefold()
                new_origin = parsed.netloc.casefold()
                if old_origin != new_origin:
                    for store in (
                        getattr(redirected_req, "headers", {}),
                        getattr(redirected_req, "unredirected_hdrs", {}),
                    ):
                        if isinstance(store, dict):
                            for header_key in list(store.keys()):
                                if header_key.casefold() in ("authorization", "cookie", "proxy-authorization"):
                                    store.pop(header_key, None)

        return redirected_req


def configure_rule34video_network_guards(youtube_dl: yt_dlp.YoutubeDL) -> None:
    """Attach destination and redirect security guards to a YoutubeDL instance for Rule34Video."""
    rd = getattr(youtube_dl, "_request_director", None)
    if rd is None or not hasattr(rd, "handlers"):
        return

    # 1. Guard UrllibRH
    urllib_rh = rd.handlers.get("Urllib")
    if urllib_rh is not None and hasattr(urllib_rh, "_create_instance"):
        orig_create = urllib_rh._create_instance

        def custom_urllib_create(*args: Any, **kwargs: Any) -> Any:
            opener = orig_create(*args, **kwargs)
            safe_redirect = SafeRule34VideoRedirectHandler()
            safe_redirect.add_parent(opener)

            new_handlers = []
            for handler in opener.handlers:
                if isinstance(handler, RedirectHandler):
                    new_handlers.append(safe_redirect)
                else:
                    new_handlers.append(handler)
            opener.handlers = new_handlers

            # Patch opener.handle_error dispatch table directly
            for proto in ("http", "https"):
                if hasattr(opener, "handle_error") and proto in opener.handle_error:
                    for code in (301, 302, 303, 307, 308):
                        if code in opener.handle_error[proto]:
                            opener.handle_error[proto][code] = [safe_redirect]

            return opener

        urllib_rh._create_instance = custom_urllib_create
        if hasattr(urllib_rh, "_clear_instances"):
            urllib_rh._clear_instances()

    # 2. Guard RequestsRH
    requests_rh = rd.handlers.get("Requests")
    if requests_rh is not None and hasattr(requests_rh, "_create_instance"):
        orig_req_create = requests_rh._create_instance

        def custom_requests_create(*args: Any, **kwargs: Any) -> Any:
            session = orig_req_create(*args, **kwargs)
            orig_resolve = session.resolve_redirects

            def safe_resolve_redirects(resp: Any, req: Any, **kw: Any) -> Any:
                hops = 0
                for r in orig_resolve(resp, req, **kw):
                    hops += 1
                    if hops > MAX_REDIRECT_HOPS:
                        raise Rule34VideoNetworkError(
                            f"Exceeded maximum redirect hops ({MAX_REDIRECT_HOPS})."
                        )
                    validate_url_security(r.url, allow_cdn=True)
                    p = urlsplit(r.url)
                    if p.hostname:
                        verify_resolved_ip_is_safe(p.hostname)

                    # Cross-origin header hygiene
                    if req is not None and hasattr(req, "url"):
                        old_origin = urlsplit(req.url).netloc.casefold()
                        new_origin = p.netloc.casefold()
                        if old_origin != new_origin and hasattr(r, "request") and hasattr(r.request, "headers"):
                            for k in list(r.request.headers.keys()):
                                if k.casefold() in ("authorization", "cookie", "proxy-authorization"):
                                    r.request.headers.pop(k, None)

                    yield r

            session.resolve_redirects = safe_resolve_redirects
            return session

        requests_rh._create_instance = custom_requests_create
        if hasattr(requests_rh, "_clear_instances"):
            requests_rh._clear_instances()

    # 3. Guard top-level urlopen
    orig_urlopen = youtube_dl.urlopen

    def safe_urlopen(req: Any) -> Any:
        target_url = getattr(req, "url", req if isinstance(req, str) else None)
        if target_url and isinstance(target_url, str):
            validate_url_security(target_url, allow_cdn=True)
            p = urlsplit(target_url)
            if p.hostname:
                verify_resolved_ip_is_safe(p.hostname)
        return orig_urlopen(req)

    youtube_dl.urlopen = safe_urlopen  # type: ignore[assignment]

