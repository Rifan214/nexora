from __future__ import annotations

import socket
from typing import Any

_HANIME_DNS_MAP: dict[str, str] = {
    "hanime.tv": "104.21.18.100",
    "www.hanime.tv": "104.21.18.100",
    "auth.hanime.tv": "104.21.18.100",
    "ct.htv-services.com": "104.21.18.100",
}

_orig_getaddrinfo = socket.getaddrinfo
_is_installed = False


def install_hanime_dns_resolver() -> None:
    """Ensure Hanime domains resolve to authentic Cloudflare edge IPs even on censored networks.

    Thread-safe and idempotent. Only intercepts Hanime domains; all other hosts bypass unconditionally.
    """
    global _is_installed
    if _is_installed:
        return

    def _hanime_getaddrinfo(host: Any, port: Any, *args: Any, **kwargs: Any) -> Any:
        host_str = host.decode("idna") if isinstance(host, (bytes, bytearray)) else (host or "")
        if host_str:
            host_lower = host_str.casefold()
            if host_lower in _HANIME_DNS_MAP or host_lower.endswith(".hanime.tv"):
                target_ip = _HANIME_DNS_MAP.get(host_lower, "104.21.18.100")
                return _orig_getaddrinfo(target_ip, port, *args, **kwargs)
        return _orig_getaddrinfo(host, port, *args, **kwargs)

    socket.getaddrinfo = _hanime_getaddrinfo
    _is_installed = True
