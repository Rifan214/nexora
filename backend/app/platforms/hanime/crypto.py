from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
from typing import Any

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


class HanimeCryptoError(Exception):
    """Base exception for Hanime cryptographic operations."""


class HanimeEnvelopeError(HanimeCryptoError):
    """Raised when an encrypted token envelope is malformed or invalid."""


class HanimeDecryptionError(HanimeCryptoError):
    """Raised when decryption fails due to authentication or padding errors."""


_DEFAULT_HANDSHAKE_SEED = "htv-insecure-handshake-v1"
_DEFAULT_HANDSHAKE_AAD = b"htv-insecure-v1"
_EXPECTED_ENVELOPE_VERSION = 1
_EXPECTED_ENVELOPE_ALG = "AES-256-GCM"
_GCM_IV_LENGTH = 12
_GCM_TAG_LENGTH = 16
_AES_128_KEY_LENGTH = 16
_AES_128_IV_LENGTH = 16
_MAX_128_BIT_INT = (1 << 128) - 1


def _safe_b64decode(value: str | bytes, *, field_name: str) -> bytes:
    """Decode standard or URL-safe base64 strings with or without padding."""
    if not isinstance(value, (str, bytes)):
        raise HanimeEnvelopeError(f"Field '{field_name}' must be a base64 string or bytes.")

    raw = value.encode("ascii") if isinstance(value, str) else value
    if not raw.strip():
        raise HanimeEnvelopeError(f"Field '{field_name}' cannot be empty.")

    # Normalize urlsafe characters to standard base64
    normalized = raw.replace(b"-", b"+").replace(b"_", b"/")
    missing_padding = len(normalized) % 4
    if missing_padding:
        normalized += b"=" * (4 - missing_padding)

    try:
        return base64.b64decode(normalized, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HanimeEnvelopeError(f"Field '{field_name}' contains invalid base64 encoding.") from exc


def derive_handshake_key(seed: str = _DEFAULT_HANDSHAKE_SEED) -> bytes:
    """Derive a 32-byte AES-256 key from a handshake seed string using SHA-256."""
    if not isinstance(seed, str) or not seed:
        raise HanimeCryptoError("Handshake seed must be a non-empty string.")
    return hashlib.sha256(seed.encode("utf-8")).digest()


def decrypt_handshake_token(
    raw_token: str | bytes | dict[str, Any],
    *,
    key: bytes | None = None,
    aad: bytes = _DEFAULT_HANDSHAKE_AAD,
) -> Any:
    """Decrypt and parse a Hanime x-token payload.

    Args:
        raw_token: Serialized base64 token string, raw JSON bytes, or parsed dict envelope.
        key: Optional 32-byte AES key. Defaults to derive_handshake_key().
        aad: Associated data used for GCM verification.

    Returns:
        The deserialized JSON content from the plaintext payload.

    Raises:
        HanimeEnvelopeError: If the envelope is missing or contains invalid fields.
        HanimeDecryptionError: If GCM authentication or plaintext JSON parsing fails.
    """
    if key is None:
        key = derive_handshake_key()
    elif not isinstance(key, bytes) or len(key) != 32:
        raise HanimeCryptoError("Decryption key must be exactly 32 bytes for AES-256-GCM.")

    # 1. Parse outer envelope if raw string or bytes provided
    envelope: Any = raw_token
    if isinstance(raw_token, (str, bytes)):
        token_str = raw_token.strip() if isinstance(raw_token, str) else raw_token.decode("utf-8", errors="replace").strip()
        if not token_str:
            raise HanimeEnvelopeError("Encrypted token payload cannot be empty.")

        # Try parsing directly as JSON; if not, attempt base64 decode first
        parsed_json = None
        if token_str.startswith("{"):
            try:
                parsed_json = json.loads(token_str)
            except json.JSONDecodeError:
                parsed_json = None

        if parsed_json is None:
            decoded_bytes = _safe_b64decode(raw_token, field_name="envelope")
            try:
                envelope = json.loads(decoded_bytes.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                raise HanimeEnvelopeError("Decoded envelope is not valid JSON.") from exc
        else:
            envelope = parsed_json

    if not isinstance(envelope, dict):
        raise HanimeEnvelopeError("Token envelope must be a JSON object.")

    # 2. Strict envelope structure validation
    if "v" not in envelope:
        raise HanimeEnvelopeError("Missing 'v' (version) in envelope.")
    if envelope["v"] != _EXPECTED_ENVELOPE_VERSION:
        raise HanimeEnvelopeError(
            f"Unsupported envelope version {envelope['v']}; expected {_EXPECTED_ENVELOPE_VERSION}."
        )

    if "alg" not in envelope:
        raise HanimeEnvelopeError("Missing 'alg' in envelope.")
    if envelope["alg"] != _EXPECTED_ENVELOPE_ALG:
        raise HanimeEnvelopeError(
            f"Unsupported algorithm '{envelope['alg']}'; expected {_EXPECTED_ENVELOPE_ALG}."
        )

    for required_field in ("iv", "tag", "data"):
        if required_field not in envelope:
            raise HanimeEnvelopeError(f"Missing required field '{required_field}' in envelope.")

    iv = _safe_b64decode(envelope["iv"], field_name="iv")
    if len(iv) != _GCM_IV_LENGTH:
        raise HanimeEnvelopeError(f"Invalid IV length ({len(iv)} bytes); expected {_GCM_IV_LENGTH} bytes.")

    tag = _safe_b64decode(envelope["tag"], field_name="tag")
    if len(tag) != _GCM_TAG_LENGTH:
        raise HanimeEnvelopeError(f"Invalid tag length ({len(tag)} bytes); expected {_GCM_TAG_LENGTH} bytes.")

    ciphertext = _safe_b64decode(envelope["data"], field_name="data")

    # 3. Authenticated Decryption
    try:
        cipher = Cipher(algorithms.AES(key), modes.GCM(iv, tag))
        decryptor = cipher.decryptor()
        if aad:
            decryptor.authenticate_additional_data(aad)
        plaintext_bytes = decryptor.update(ciphertext) + decryptor.finalize()
    except InvalidTag as exc:
        raise HanimeDecryptionError("Authentication tag verification failed for token.") from exc
    except Exception as exc:
        raise HanimeDecryptionError("Cryptographic failure during token decryption.") from exc

    # 4. Parse plaintext as JSON
    try:
        return json.loads(plaintext_bytes.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HanimeDecryptionError("Plaintext payload is not valid JSON.") from exc


def encrypt_handshake_token(
    payload: Any,
    *,
    key: bytes | None = None,
    aad: bytes = _DEFAULT_HANDSHAKE_AAD,
    iv: bytes | None = None,
) -> str:
    """Generate an encrypted Hanime token string for synthetic testing and mocks.

    Returns:
        URL-safe base64 encoded JSON envelope string.
    """
    if key is None:
        key = derive_handshake_key()
    elif not isinstance(key, bytes) or len(key) != 32:
        raise HanimeCryptoError("Encryption key must be exactly 32 bytes for AES-256-GCM.")

    if iv is None:
        iv = os.urandom(_GCM_IV_LENGTH)
    elif len(iv) != _GCM_IV_LENGTH:
        raise HanimeCryptoError(f"IV must be exactly {_GCM_IV_LENGTH} bytes.")

    plaintext = json.dumps(payload).encode("utf-8")

    cipher = Cipher(algorithms.AES(key), modes.GCM(iv))
    encryptor = cipher.encryptor()
    if aad:
        encryptor.authenticate_additional_data(aad)
    ciphertext = encryptor.update(plaintext) + encryptor.finalize()
    tag = encryptor.tag

    envelope = {
        "v": _EXPECTED_ENVELOPE_VERSION,
        "alg": _EXPECTED_ENVELOPE_ALG,
        "iv": base64.b64encode(iv).decode("ascii"),
        "tag": base64.b64encode(tag).decode("ascii"),
        "data": base64.b64encode(ciphertext).decode("ascii"),
    }

    envelope_bytes = json.dumps(envelope).encode("utf-8")
    return base64.urlsafe_b64encode(envelope_bytes).decode("ascii")


def decrypt_hls_segment_aes_128(ciphertext: bytes, key: bytes, iv: bytes) -> bytes:
    """Decrypt an AES-128-CBC encrypted HLS media segment and remove PKCS7 padding.

    Args:
        ciphertext: Encrypted binary segment data.
        key: Exactly 16 bytes AES-128 key.
        iv: Exactly 16 bytes initialization vector.

    Returns:
        Decrypted binary segment data (e.g. MPEG-TS).

    Raises:
        HanimeCryptoError: If key, IV, or ciphertext dimensions are invalid.
        HanimeDecryptionError: If decryption or PKCS7 unpadding fails.
    """
    if not isinstance(key, bytes) or len(key) != _AES_128_KEY_LENGTH:
        raise HanimeCryptoError(f"HLS key must be exactly {_AES_128_KEY_LENGTH} bytes; got {len(key) if isinstance(key, bytes) else type(key)}.")

    if not isinstance(iv, bytes) or len(iv) != _AES_128_IV_LENGTH:
        raise HanimeCryptoError(f"HLS IV must be exactly {_AES_128_IV_LENGTH} bytes; got {len(iv) if isinstance(iv, bytes) else type(iv)}.")

    if not isinstance(ciphertext, bytes) or len(ciphertext) == 0:
        raise HanimeCryptoError("Ciphertext cannot be empty.")

    if len(ciphertext) % _AES_128_KEY_LENGTH != 0:
        raise HanimeCryptoError(
            f"Ciphertext length ({len(ciphertext)}) is not a multiple of {_AES_128_KEY_LENGTH} block size."
        )

    try:
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
        decryptor = cipher.decryptor()
        padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()

        unpadder = padding.PKCS7(128).unpadder()
        return unpadder.update(padded_plaintext) + unpadder.finalize()
    except ValueError as exc:
        raise HanimeDecryptionError("Invalid PKCS7 padding in decrypted segment.") from exc
    except Exception as exc:
        raise HanimeDecryptionError("Decryption failed for HLS segment.") from exc


def encrypt_hls_segment_aes_128(plaintext: bytes, key: bytes, iv: bytes) -> bytes:
    """Encrypt a media segment using AES-128-CBC with PKCS7 padding for synthetic testing."""
    if not isinstance(key, bytes) or len(key) != _AES_128_KEY_LENGTH:
        raise HanimeCryptoError(f"HLS key must be exactly {_AES_128_KEY_LENGTH} bytes.")

    if not isinstance(iv, bytes) or len(iv) != _AES_128_IV_LENGTH:
        raise HanimeCryptoError(f"HLS IV must be exactly {_AES_128_IV_LENGTH} bytes.")

    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(plaintext) + padder.finalize()

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    return encryptor.update(padded_data) + encryptor.finalize()


def derive_hls_iv(sequence: int) -> bytes:
    """Derive a 16-byte Big-Endian IV from an HLS media sequence integer.

    As specified in RFC 8216 Section 5.2, when EXT-X-KEY lacks an explicit IV,
    the sequence number of the media segment is encoded as a 128-bit unsigned
    integer in big-endian order.

    Args:
        sequence: Non-negative integer representing the segment sequence number.

    Returns:
        16-byte binary initialization vector.

    Raises:
        HanimeCryptoError: If sequence is negative or exceeds 128-bit capacity.
    """
    if not isinstance(sequence, int):
        raise HanimeCryptoError(f"Sequence number must be an integer, got {type(sequence).__name__}.")

    if sequence < 0:
        raise HanimeCryptoError(f"Sequence number cannot be negative: {sequence}.")

    if sequence > _MAX_128_BIT_INT:
        raise HanimeCryptoError(f"Sequence number exceeds 128-bit unsigned integer range: {sequence}.")

    return sequence.to_bytes(16, byteorder="big")
