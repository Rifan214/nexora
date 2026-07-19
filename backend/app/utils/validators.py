from __future__ import annotations

from urllib.parse import urlparse


def validate_http_url(value: str) -> str:
    if not isinstance(value, str):
        raise ValueError("URL must be a string")

    normalized = value.strip()
    if not normalized:
        raise ValueError("URL must not be empty")

    parsed = urlparse(normalized)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("URL must use http or https")

    if not parsed.netloc:
        raise ValueError("URL must be a valid absolute URL")

    return normalized