from __future__ import annotations

from app.platforms.hanime.crypto import (
    HanimeCryptoError,
    HanimeDecryptionError,
    HanimeEnvelopeError,
    decrypt_handshake_token,
    decrypt_hls_segment_aes_128,
    derive_handshake_key,
    derive_hls_iv,
    encrypt_handshake_token,
    encrypt_hls_segment_aes_128,
)
from app.platforms.hanime.extractor import (
    HanimeDecryptionFailureError,
    HanimeExtractor,
    HanimeMalformedPayloadError,
    HanimeNoPlayableFormatsError,
    HanimeUrlError,
    parse_iso_duration,
)
from app.platforms.hanime.http_client import (
    HanimeExtractionError,
    HanimeHandshakeAuthError,
    HanimeHttpClientError,
    HanimeMalformedResponseError,
    HanimeNetworkError,
    HanimeRateLimitError,
    HanimeSecurityError,
    HanimeServerError,
    HttpHanimeClient,
)
from app.platforms.hanime.signature_provider import (
    HanimeSignature,
    HanimeSignatureError,
    HanimeSignatureProvider,
    HanimeSignatureProviderError,
    get_hanime_signature_provider,
    is_hanime_provider_enabled,
    reset_hanime_signature_provider,
)

from app.platforms.hanime.dns import install_hanime_dns_resolver

__all__ = [
    "install_hanime_dns_resolver",
    "HanimeCryptoError",
    "HanimeEnvelopeError",
    "HanimeDecryptionError",
    "derive_handshake_key",
    "decrypt_handshake_token",
    "encrypt_handshake_token",
    "decrypt_hls_segment_aes_128",
    "encrypt_hls_segment_aes_128",
    "derive_hls_iv",
    "HanimeSignature",
    "HanimeSignatureError",
    "HanimeSignatureProvider",
    "HanimeSignatureProviderError",
    "get_hanime_signature_provider",
    "is_hanime_provider_enabled",
    "reset_hanime_signature_provider",
    "HanimeExtractionError",
    "HttpHanimeClient",
    "HanimeHttpClientError",
    "HanimeNetworkError",
    "HanimeSecurityError",
    "HanimeHandshakeAuthError",
    "HanimeRateLimitError",
    "HanimeServerError",
    "HanimeMalformedResponseError",
    "HanimeExtractor",
    "HanimeUrlError",
    "HanimeDecryptionFailureError",
    "HanimeMalformedPayloadError",
    "HanimeNoPlayableFormatsError",
    "parse_iso_duration",
]
