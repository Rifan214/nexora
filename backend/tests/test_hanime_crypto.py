from __future__ import annotations

import base64
import json
import pytest

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


# ==============================================================================
# A. SHA-256 KEY DERIVATION
# ==============================================================================

def test_key_derivation_length_and_determinism() -> None:
    key1 = derive_handshake_key("htv-insecure-handshake-v1")
    key2 = derive_handshake_key("htv-insecure-handshake-v1")

    assert isinstance(key1, bytes)
    assert len(key1) == 32
    assert key1 == key2

    # Different seed yields different 32-byte key
    key3 = derive_handshake_key("different-seed-v2")
    assert len(key3) == 32
    assert key1 != key3


def test_key_derivation_invalid_seed() -> None:
    with pytest.raises(HanimeCryptoError, match="Handshake seed must be a non-empty string"):
        derive_handshake_key("")

    with pytest.raises(HanimeCryptoError, match="Handshake seed must be a non-empty string"):
        derive_handshake_key(None)  # type: ignore[arg-type]


# ==============================================================================
# B. AES-256-GCM ROUNDTRIP & DECRYPTION
# ==============================================================================

def test_aes_256_gcm_synthetic_roundtrip() -> None:
    synthetic_payload = {
        "title": "Synthetic Test Video",
        "sources": [
            {"src": "https://example.com/stream-720p.m3u8", "resolution": "720p"},
            {"src": "https://example.com/stream-480p.m3u8", "resolution": "480p"},
        ],
    }
    fixed_key = b"0123456789abcdef0123456789abcdef"
    fixed_iv = b"123456789012"
    fixed_aad = b"htv-insecure-v1"

    token_b64 = encrypt_handshake_token(
        synthetic_payload,
        key=fixed_key,
        aad=fixed_aad,
        iv=fixed_iv,
    )
    assert isinstance(token_b64, str)
    assert len(token_b64) > 0

    decrypted = decrypt_handshake_token(token_b64, key=fixed_key, aad=fixed_aad)
    assert decrypted == synthetic_payload


def test_aes_256_gcm_default_key_and_aad() -> None:
    sample_data = {"status": "ok", "user": "guest", "tier": 0}
    token = encrypt_handshake_token(sample_data)
    decrypted = decrypt_handshake_token(token)
    assert decrypted == sample_data


# ==============================================================================
# C. AES-256-GCM WRONG KEY
# ==============================================================================

def test_aes_256_gcm_wrong_key_fails() -> None:
    payload = {"secret": "confidential data"}
    key_correct = b"0123456789abcdef0123456789abcdef"
    key_wrong = b"fedcba9876543210fedcba9876543210"

    token = encrypt_handshake_token(payload, key=key_correct)

    with pytest.raises(HanimeDecryptionError, match="Authentication tag verification failed"):
        decrypt_handshake_token(token, key=key_wrong)


# ==============================================================================
# D. AES-256-GCM WRONG AAD
# ==============================================================================

def test_aes_256_gcm_wrong_aad_fails() -> None:
    payload = {"data": [1, 2, 3]}
    key = b"0123456789abcdef0123456789abcdef"
    token = encrypt_handshake_token(payload, key=key, aad=b"htv-insecure-v1")

    with pytest.raises(HanimeDecryptionError, match="Authentication tag verification failed"):
        decrypt_handshake_token(token, key=key, aad=b"tampered-aad-v1")


# ==============================================================================
# E. MALFORMED ENVELOPE VALIDATIONS
# ==============================================================================

def test_envelope_not_json_fails() -> None:
    # Invalid base64
    with pytest.raises(HanimeEnvelopeError, match="invalid base64 encoding"):
        decrypt_handshake_token("this-is-not-valid-base64-json!!!")

    # Valid base64, but decoded content is not JSON
    non_json_b64 = base64.b64encode(b"this is plain text, not JSON").decode("ascii")
    with pytest.raises(HanimeEnvelopeError, match="Decoded envelope is not valid JSON"):
        decrypt_handshake_token(non_json_b64)

    # Valid base64 JSON, but not a JSON object/dict (e.g. array)
    json_list_b64 = base64.b64encode(b"[1, 2, 3]").decode("ascii")
    with pytest.raises(HanimeEnvelopeError, match="Token envelope must be a JSON object"):
        decrypt_handshake_token(json_list_b64)

    # Empty string
    with pytest.raises(HanimeEnvelopeError, match="cannot be empty"):
        decrypt_handshake_token("")


def test_envelope_missing_v() -> None:
    envelope = {
        "alg": "AES-256-GCM",
        "iv": base64.b64encode(b"1" * 12).decode("ascii"),
        "tag": base64.b64encode(b"1" * 16).decode("ascii"),
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="Missing 'v'"):
        decrypt_handshake_token(envelope)


def test_envelope_wrong_v() -> None:
    envelope = {
        "v": 2,
        "alg": "AES-256-GCM",
        "iv": base64.b64encode(b"1" * 12).decode("ascii"),
        "tag": base64.b64encode(b"1" * 16).decode("ascii"),
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="Unsupported envelope version 2"):
        decrypt_handshake_token(envelope)


def test_envelope_wrong_alg() -> None:
    envelope = {
        "v": 1,
        "alg": "AES-128-CBC",
        "iv": base64.b64encode(b"1" * 12).decode("ascii"),
        "tag": base64.b64encode(b"1" * 16).decode("ascii"),
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="Unsupported algorithm 'AES-128-CBC'"):
        decrypt_handshake_token(envelope)


def test_envelope_invalid_iv_length() -> None:
    envelope = {
        "v": 1,
        "alg": "AES-256-GCM",
        "iv": base64.b64encode(b"1" * 8).decode("ascii"),  # 8 bytes instead of 12
        "tag": base64.b64encode(b"1" * 16).decode("ascii"),
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="Invalid IV length"):
        decrypt_handshake_token(envelope)


def test_envelope_invalid_tag_length() -> None:
    envelope = {
        "v": 1,
        "alg": "AES-256-GCM",
        "iv": base64.b64encode(b"1" * 12).decode("ascii"),
        "tag": base64.b64encode(b"1" * 8).decode("ascii"),  # 8 bytes instead of 16
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="Invalid tag length"):
        decrypt_handshake_token(envelope)


def test_envelope_corrupted_base64() -> None:
    envelope = {
        "v": 1,
        "alg": "AES-256-GCM",
        "iv": "not-valid-b64!@#$%",
        "tag": base64.b64encode(b"1" * 16).decode("ascii"),
        "data": base64.b64encode(b"1" * 16).decode("ascii"),
    }
    with pytest.raises(HanimeEnvelopeError, match="invalid base64 encoding"):
        decrypt_handshake_token(envelope)


def test_envelope_plaintext_not_json() -> None:
    # Encrypt raw non-JSON bytes
    key = derive_handshake_key()
    iv = b"123456789012"
    non_json_data = b"This is plain text, not a JSON string"

    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    cipher = Cipher(algorithms.AES(key), modes.GCM(iv))
    enc = cipher.encryptor()
    enc.authenticate_additional_data(b"htv-insecure-v1")
    ct = enc.update(non_json_data) + enc.finalize()
    tag = enc.tag

    raw_envelope = {
        "v": 1,
        "alg": "AES-256-GCM",
        "iv": base64.b64encode(iv).decode("ascii"),
        "tag": base64.b64encode(tag).decode("ascii"),
        "data": base64.b64encode(ct).decode("ascii"),
    }
    with pytest.raises(HanimeDecryptionError, match="Plaintext payload is not valid JSON"):
        decrypt_handshake_token(raw_envelope)


# ==============================================================================
# F. AES-128-CBC HLS SEGMENT DECRYPTION
# ==============================================================================

def test_aes_128_cbc_synthetic_roundtrip() -> None:
    key = b"0123456789abcdef"  # 16 bytes
    iv = derive_hls_iv(0)       # 16 bytes
    plaintext_ts = b"G" + b"\x00" * 187  # Synthetic 188-byte MPEG-TS packet

    ciphertext = encrypt_hls_segment_aes_128(plaintext_ts, key, iv)
    assert len(ciphertext) % 16 == 0
    assert ciphertext != plaintext_ts

    decrypted = decrypt_hls_segment_aes_128(ciphertext, key, iv)
    assert decrypted == plaintext_ts


# ==============================================================================
# G. INVALID AES-128 KEY
# ==============================================================================

def test_aes_128_cbc_invalid_key_length() -> None:
    iv = derive_hls_iv(0)
    data = b"\x00" * 16

    with pytest.raises(HanimeCryptoError, match="HLS key must be exactly 16 bytes"):
        decrypt_hls_segment_aes_128(data, b"short_8b", iv)

    with pytest.raises(HanimeCryptoError, match="HLS key must be exactly 16 bytes"):
        decrypt_hls_segment_aes_128(data, b"0123456789abcdef0123456789abcdef", iv)


# ==============================================================================
# H. INVALID AES-128 IV
# ==============================================================================

def test_aes_128_cbc_invalid_iv_length() -> None:
    key = b"0123456789abcdef"
    data = b"\x00" * 16

    with pytest.raises(HanimeCryptoError, match="HLS IV must be exactly 16 bytes"):
        decrypt_hls_segment_aes_128(data, key, b"short_8b")

    with pytest.raises(HanimeCryptoError, match="HLS IV must be exactly 16 bytes"):
        decrypt_hls_segment_aes_128(data, key, b"0123456789abcdef0123456789abcdef")


# ==============================================================================
# I. CORRUPTED CIPHERTEXT & PADDING
# ==============================================================================

def test_aes_128_cbc_invalid_ciphertext_size() -> None:
    key = b"0123456789abcdef"
    iv = derive_hls_iv(0)

    # Empty
    with pytest.raises(HanimeCryptoError, match="Ciphertext cannot be empty"):
        decrypt_hls_segment_aes_128(b"", key, iv)

    # Not multiple of 16
    with pytest.raises(HanimeCryptoError, match="not a multiple of 16 block size"):
        decrypt_hls_segment_aes_128(b"\x00" * 15, key, iv)


def test_aes_128_cbc_corrupted_padding_fails() -> None:
    key = b"0123456789abcdef"
    iv = derive_hls_iv(1)
    plaintext = b"Valid MPEG transport stream segment payload"

    ciphertext = encrypt_hls_segment_aes_128(plaintext, key, iv)
    # Corrupt last byte containing PKCS7 padding
    tampered = bytearray(ciphertext)
    tampered[-1] ^= 0xFF

    with pytest.raises(HanimeDecryptionError, match="Invalid PKCS7 padding"):
        decrypt_hls_segment_aes_128(bytes(tampered), key, iv)


# ==============================================================================
# J. HLS IV DERIVATION
# ==============================================================================

def test_hls_iv_derivation_deterministic() -> None:
    # Sequence 0: 16 zero bytes
    iv0 = derive_hls_iv(0)
    assert len(iv0) == 16
    assert iv0 == b"\x00" * 16

    # Sequence 1: 15 zero bytes + 0x01
    iv1 = derive_hls_iv(1)
    assert len(iv1) == 16
    assert iv1 == b"\x00" * 15 + b"\x01"

    # Sequence 2: 15 zero bytes + 0x02
    iv2 = derive_hls_iv(2)
    assert len(iv2) == 16
    assert iv2 == b"\x00" * 15 + b"\x02"

    # Large valid sequence
    seq_large = 0x123456789ABCDEF0
    iv_large = derive_hls_iv(seq_large)
    assert len(iv_large) == 16
    assert iv_large == b"\x00" * 8 + bytes.fromhex("123456789abcdef0")

    # Max 128-bit sequence
    max_128 = (1 << 128) - 1
    iv_max = derive_hls_iv(max_128)
    assert len(iv_max) == 16
    assert iv_max == b"\xff" * 16


# ==============================================================================
# K. NEGATIVE SEQUENCE
# ==============================================================================

def test_hls_iv_negative_sequence_fails() -> None:
    with pytest.raises(HanimeCryptoError, match="Sequence number cannot be negative"):
        derive_hls_iv(-1)

    with pytest.raises(HanimeCryptoError, match="Sequence number cannot be negative"):
        derive_hls_iv(-9999)


# ==============================================================================
# L. OVERFLOW SEQUENCE (> 128-BIT) & INVALID TYPES
# ==============================================================================

def test_hls_iv_overflow_sequence_fails() -> None:
    overflow_val = 1 << 128
    with pytest.raises(HanimeCryptoError, match="exceeds 128-bit"):
        derive_hls_iv(overflow_val)


def test_hls_iv_non_integer_fails() -> None:
    with pytest.raises(HanimeCryptoError, match="Sequence number must be an integer"):
        derive_hls_iv("0")  # type: ignore[arg-type]

    with pytest.raises(HanimeCryptoError, match="Sequence number must be an integer"):
        derive_hls_iv(12.5)  # type: ignore[arg-type]
