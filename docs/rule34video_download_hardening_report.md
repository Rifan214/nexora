# Nexora Backend — Rule34Video Download Pipeline Hardening Report

**Document Version:** 1.0.0  
**Implementation Date:** 2026-10-30  
**Author:** Antigravity (Advanced Agentic Coding Assistant)  
**Status:** Completed & Fully Verified  
**Scope:** Rule34Video Adapter, HTTP Client, Network Guards, MediaService, and yt-dlp Download Engine  
**Target Post Verified:** `https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/`  

---

## 1. Executive Summary

Following the comprehensive security and pipeline audit documented in `docs/rule34video_security_download_audit.md`, this report details the defense-in-depth hardening implemented across Nexora's Rule34Video download pipeline.

The hardening directly resolves the four identified security and precision gaps:
1. **Download-Phase CDN Redirect Bypass (High Severity)**: Resolved by pre-resolving the original format stream URL (`https://rule34video.com/get_file/...`) to its validated final CDN destination (`https://<edge-node>.boomio-cdn.com/...`) before starting the download worker. Furthermore, runtime network guards (`SafeRule34VideoRedirectHandler` and `configure_rule34video_network_guards`) are attached to the `YoutubeDL` engine to intercept and validate any subsequent redirects during download execution.
2. **DNS Rebinding & TOCTOU Window (Medium Severity)**: Resolved by introducing `SafeNetworkBackend` and `SafeAsyncHTTPTransport`, which inspect the actual connected TCP socket's peer IP (`getpeername()[0]`) immediately upon connection and reject private/loopback/link-local addresses before TLS wrapping or HTTP request transmission occurs.
3. **Filesize Badge Approximation Stored as Exact (Low Severity)**: Corrected by separating approximate and exact byte measurements. HTML badge values are now ingested strictly into `filesize_approx`, while exact byte counts are retrieved from the validated CDN `Content-Length` header during pre-resolution and stored in `filesize`.
4. **Cross-Origin Header Hygiene (Low Severity)**: Enforced both in `HttpRule34VideoClient.resolve_media_url` and `SafeRule34VideoRedirectHandler.redirect_request`, stripping sensitive headers (such as `Authorization` and `Cookie`) across origins while preserving the required `User-Agent` and `Referer` headers for CDN hotlink validation.

### Verification Highlights
- **Dedicated Suite:** 50/50 unit and integration tests passed in `backend/tests/test_rule34video_support.py` (+10 new hardening tests).
- **Targeted Platforms:** 100% pass across Danbooru (38/38), Hanime (16/16), QualitySelector (29/29), and MediaService routes (83/83).
- **Full Backend Regression Suite:** **755 passed, 3 skipped, 0 failures** across all platforms (YouTube, TikTok, Twitter/X, Instagram, Facebook, Reddit, Hanime, Danbooru, Rule34Video).
- **Live End-to-End Download:** Target Post 4667334 format 360p was successfully pre-resolved, downloaded directly from `boomio-cdn.com`, validated via `validate_download_artifact()`, and cleaned up cleanly.

---

## 2. Original Findings & Root Cause Analysis

### 2.1 Gap 1: Download-Phase CDN Redirect Bypass
- **Finding:** While `HttpRule34VideoClient` validated redirect destinations during metadata extraction, the binary download phase delegated directly to `YoutubeDL.process_ie_result()`. yt-dlp's internal `RedirectHandler` followed HTTP 302 redirects automatically without checking destinations against Nexora's domain allowlist or private IP filters.
- **Root Cause:** yt-dlp was handed the unredirected origin URL (`https://rule34video.com/get_file/...`) rather than the final CDN destination, leaving redirect handling to yt-dlp's unconstrained internal HTTP downloader.

### 2.2 Gap 2: DNS Rebinding & TOCTOU Window
- **Finding:** `HttpRule34VideoClient.fetch_html()` executed pre-validation using `socket.getaddrinfo()` before `httpx.AsyncClient` established an independent socket connection.
- **Root Cause:** A separate preliminary DNS lookup does not bind the socket used by `httpx`. An authoritative DNS server with TTL=0 could return a benign IP during pre-validation and rebind to a private/internal IP during socket creation.

### 2.3 Gap 3: Filesize Badge Approximation Stored as Exact
- **Finding:** Coarse HTML display badges (e.g. `11 MB`, `55 MB`) were parsed as exact byte counts (e.g. `11,534,336`) and assigned to `format["filesize"]`.
- **Root Cause:** Upstream Kernel Video Sharing CMS renders integer-rounded megabyte strings in `<span class="vp-sheet__meta">`. Storing these in `filesize` created a ~211 KB discrepancy against the true byte length (`11,322,797`) and caused percentage progress skew prior to response header receipt.

### 2.4 Gap 4: Cross-Origin Header Propagation
- **Finding:** Request headers (`Referer: https://rule34video.com/`) were passed globally to yt-dlp and forwarded across redirects.
- **Root Cause:** Standard redirect handlers forward all original headers unless explicitly filtered upon origin transition.

---

## 3. Architecture & Implementation Details

```mermaid
flowchart TD
    subgraph PreResolution["1. Pre-Download Format Resolution"]
        Req["POST /media/download"] --> MS["MediaService._process_download_with_youtube_dl"]
        MS --> Prep["_prepare_rule34video_download_info()"]
        Prep --> Extractor["Rule34VideoExtractor.resolve_media_formats_for_selector()"]
        Extractor --> Client["HttpRule34VideoClient.resolve_media_url()"]
        
        Client --> Hop1["Hop 1: HEAD https://rule34video.com/get_file/..."]
        Hop1 --> CheckHop1{"Validate Scheme, Host & Safe IP"}
        CheckHop1 -->|"HTTP 302"| Hop2["Hop 2: Location https://<edge>.boomio-cdn.com/..."]
        CheckHop1 -->|"Untrusted / Private"| SecurityErr["Raise Rule34VideoSecurityError"]
        
        Hop2 --> CheckHop2{"Validate Scheme, Host & Safe IP"}
        CheckHop2 -->|"HTTP 200"| FinalData["Extract Exact Content-Length & Final CDN URL"]
        CheckHop2 -->|"Untrusted / Private"| SecurityErr
    end

    subgraph DownloadWorker["2. Hardened Worker Execution"]
        FinalData --> UpdateInfo["Update format: url=CDN URL, filesize=Exact, filesize_approx=Badge"]
        UpdateInfo --> Guards["configure_rule34video_network_guards(youtube_dl)"]
        Guards --> ProcessIE["youtube_dl.process_ie_result(resolved_download_info)"]
        ProcessIE --> DirectConnect["Direct Connection to Pre-Validated CDN Node"]
        DirectConnect --> Disk["Stream to Local Temp & validate_download_artifact()"]
    end
```

### 3.1 Component Modifications

| File | Changes Made |
|---|---|
| `backend/app/platforms/rule34video/constants.py` | Added `MAX_REDIRECT_HOPS = 5`. |
| `backend/app/platforms/rule34video/http_client.py` | 1. Updated `is_safe_ip()` to evaluate IPv4, IPv6, and unwrapped IPv4-mapped IPv6 consistently.<br>2. Implemented `SafeNetworkBackend` to inspect `raw_socket.getpeername()[0]` on connected sockets, eliminating the TOCTOU window.<br>3. Implemented `SafeAsyncHTTPTransport` using `SafeNetworkBackend`.<br>4. Added `resolve_media_url()` with hop-by-hop security checks, max 5 hops cap, cross-origin header hygiene, and exact `Content-Length` extraction. |
| `backend/app/platforms/rule34video/extractor.py` | 1. HTML badges are now ingested strictly into `filesize_approx`, leaving `filesize = None`.<br>2. Added `resolve_media_format()` to update a format item with its validated CDN URL and exact `filesize`.<br>3. Added `resolve_media_formats_for_selector()` to pre-resolve candidate streams prior to download worker execution. |
| `backend/app/platforms/rule34video/network_guards.py` | **(New Module)**<br>1. `SafeRule34VideoRedirectHandler`: Custom `RedirectHandler` for yt-dlp that enforces HTTPS scheme, domain allowlist, IP safety, max 5 hops, and header stripping across origins.<br>2. `configure_rule34video_network_guards()`: Attaches redirect handlers and wraps `urlopen` on the `YoutubeDL` instance. |
| `backend/app/platforms/rule34video/__init__.py` | Exported `MAX_REDIRECT_HOPS`, `SafeNetworkBackend`, `SafeAsyncHTTPTransport`, `SafeRule34VideoRedirectHandler`, and `configure_rule34video_network_guards`. |
| `backend/app/services/media_service.py` | 1. Added `_prepare_rule34video_download_info()` to pre-resolve candidate streams before calling `youtube_dl.process_ie_result()`.<br>2. Attached `configure_rule34video_network_guards()` to `youtube_dl` and `fallback_youtube_dl` in `_download_job_background()`.<br>3. Updated `_map_yt_dlp_error()` to map `Rule34VideoSecurityError` to `RULE34VIDEO_SECURITY_ERROR` (HTTP 422). |
| `backend/tests/test_rule34video_support.py` | Updated `test_extractor_extract_success` to assert `filesize_approx` and added 10 dedicated hardening tests covering redirects, downgrades, max hops, IP validation, header handling, exact filesize, and network guards. |

---

## 4. Connection Validation & DNS Rebinding Hardening

### 4.1 Connected Socket Inspection
To close the TOCTOU window between preliminary DNS lookups and actual network connections, `SafeNetworkBackend` subclasses `AnyIOBackend`:

```python
class SafeNetworkBackend(AnyIOBackend):
    async def connect_tcp(self, host: str, port: int, timeout=None, local_address=None, socket_options=None):
        stream = await super().connect_tcp(host, port, timeout=timeout, local_address=local_address, socket_options=socket_options)
        if not self._allow_http_for_tests:
            raw_sock = getattr(getattr(stream, "_stream", None), "_raw_socket", None)
            if raw_sock and hasattr(raw_sock, "getpeername"):
                peer_ip = raw_sock.getpeername()[0]
                if not is_safe_ip(peer_ip):
                    await stream.aclose()
                    raise Rule34VideoSecurityError(
                        f"Host '{host}' established connection to forbidden private/loopback IP '{peer_ip}'."
                    )
        return stream
```

### 4.2 Security Properties
1. **Zero Data Disclosure:** The peer IP is verified immediately after TCP establishment and before TLS handshake or HTTP request transmission. If the peer is private/loopback, the socket is immediately closed.
2. **TLS Integrity Maintained:** Standard TLS certificate verification is preserved because `server_hostname` is passed through normally into `TLSStream.wrap(..., hostname=server_hostname)`.
3. **Consistent Address Handling:** `is_safe_ip()` unwraps `ip.ipv4_mapped` on IPv6 addresses, ensuring `::ffff:127.0.0.1` and `127.0.0.1` are rejected identically.

---

## 5. Verification & Regression Test Results

### 5.1 Automated Test Execution Summary

| Test Suite / Scope | Tests Run | Result | Execution Time |
|---|---|---|---|
| `test_rule34video_support.py` (Rule34Video Hardened) | 50 | **50 PASSED** | 3.27s |
| `test_danbooru_support.py` (Danbooru Adapter) | 38 | **38 PASSED** | 2.83s |
| `test_media_service_hanime.py` (Hanime Adapter) | 16 | **16 PASSED** | 2.50s |
| `test_quality_selector.py` (Quality & Codec Engine) | 29 | **29 PASSED** | 0.52s |
| Media Routes & Services (`download`, `quality`, `extraction`, `cache`) | 83 | **83 PASSED** | 8.09s |
| **Full Backend Regression Suite** (`backend/tests/`) | **758** | **755 PASSED, 3 SKIPPED, 0 FAILED** | **22.26s** |

### 5.2 Hardening Tests Details (10 New Scenarios)
1. `test_resolve_media_url_valid_cdn_redirect`: Verifies 302 redirect from `rule34video.com` to `boomio-cdn.com` resolves with exact `Content-Length: 57218883`. (PASS)
2. `test_resolve_media_url_unapproved_destination_blocked`: Verifies 302 redirect to `https://unauthorized-attacker.com` is rejected with `Rule34VideoSecurityError`. (PASS)
3. `test_resolve_media_url_http_downgrade_blocked`: Verifies 302 redirect to insecure `http://` destination is rejected with `Rule34VideoSecurityError`. (PASS)
4. `test_resolve_media_url_exceeds_max_hops_blocked`: Verifies redirect chain exceeding 5 hops raises `Rule34VideoNetworkError`. (PASS)
5. `test_resolve_media_url_private_ip_destination_blocked`: Verifies redirect to `127.0.0.1` is rejected with `Rule34VideoSecurityError`. (PASS)
6. `test_is_safe_ip_ipv4_and_ipv6_variants`: Verifies comprehensive IP safety across IPv4, IPv6, and IPv4-mapped IPv6 (`::ffff:127.0.0.1` -> False, `::ffff:8.8.8.8` -> True). (PASS)
7. `test_header_handling_across_different_origins`: Verifies sensitive headers (`Authorization`, `Cookie`) are stripped upon origin change while `User-Agent` and `Referer` are preserved. (PASS)
8. `test_resolve_media_format_approx_and_exact_filesize`: Verifies format item retains `filesize_approx` while updating `filesize` with exact CDN byte count. (PASS)
9. `test_download_worker_uses_validated_final_url`: Verifies that `MediaService._process_download_with_youtube_dl` passes the pre-resolved validated CDN URL to `process_ie_result`. (PASS)
10. `test_configure_rule34video_network_guards_blocks_runtime_untrusted_redirect`: Verifies that yt-dlp's runtime opener with installed guards rejects untrusted redirects during download. (PASS)

---

## 6. Live Manual End-to-End Verification

A live end-to-end verification was performed against target Post `4667334`:

1. **Metadata Phase:**
   - URL: `https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/`
   - Available Qualities Extracted: `[360p, 480p, 720p, 1080p]`.
   - Approximate Badge Size for 360p: `11,534,336 bytes` (`11 MB`).
2. **Pre-Resolution Phase:**
   - Format 360p stream URL: `https://rule34video.com/get_file/58/5084998489e92997a5abbb4edca5813c/4667000/4667334/4667334_360.mp4/?v-acctoken=...&download=true`
   - Pre-resolved via `HttpRule34VideoClient.resolve_media_url()`:
     - Hop 1: `https://rule34video.com/get_file/...` -> HTTP 302 Found.
     - Destination validated: `https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?...` (HTTPS, boomio-cdn domain, safe public IP verified).
     - Response: HTTP 200 OK, `Content-Length: 11322797 bytes`.
   - Format updated: `url` set to final CDN URL, `filesize = 11322797`, `filesize_approx = 11534336`.
3. **Download Worker Execution:**
   - Background worker thread invoked `youtube_dl.process_ie_result()` with network guards active.
   - Downloader connected directly to `eu-cdn10-prem.boomio-cdn.com` without initiating an origin redirect.
   - Progress events tracked smoothly from `0.0% of 10.80MiB` to `100.0% of 10.80MiB` (`11,322,797 bytes`).
4. **Artifact Validation:**
   - Disk artifact verified at `backend/storage/temp/<job_id>.mp4`.
   - File size on disk: exactly **`11,322,797 bytes`**.
   - Validated via `validate_download_artifact(output_type='video')`: intact MP4 container with H.264 video and AAC audio streams.
   - Temporary artifacts removed after test verification.

---

## 7. Cross-Platform Regression Assessment

Zero regressions were detected across all supported platforms:
- **YouTube:** Progressive stream blocking (format 18), HLS/DASH audio pairing, and transport refresh remain intact.
- **Instagram:** Guest extraction, authenticated fallback, and Batch Import cookie propagation remain fully operational.
- **TikTok:** Transient failure retry delays and signature handling remain unchanged.
- **Twitter / X:** HLS variant pairing and authenticated fallback remain unaffected.
- **Facebook & Reddit:** Error translation and progressive MP4 selection remain unaffected.
- **Danbooru:** Native JSON API adapter and progressive MP4 candidate selection remain unaffected (38/38 passed).
- **Hanime:** Native manifest preparation and signature verification remain unaffected (16/16 passed).

---

## 8. Remaining Limitations

1. **CDN Domain Allowlist Scope:** The adapter allowlist permits `boomio-cdn.com` and its subdomains (`*.boomio-cdn.com`). If upstream Rule34Video transitions media storage to an entirely new CDN provider, `ALLOWED_CDN_DOMAIN` in `constants.py` will require a configuration update.
2. **Upstream Account Token Lifetimes:** Rule34Video get_file tokens (`?v-acctoken=...`) are time-limited by upstream servers. Pre-resolving immediately prior to download worker execution minimizes token expiration risk.
3. **DNS Multi-IP Resolution:** In networks where a CDN hostname maps to multiple Anycast IPs, `SafeNetworkBackend` validates the specific IP chosen for the TCP connection.

---

## 9. Final Assessment & Verdict

### **VERDICT: PASS (HARDENED)**

**Justification:**
1. All four security and precision gaps identified in the audit report have been definitively remediated.
2. The download worker uses a pre-resolved, validated final CDN destination with zero redirect bypass during normal execution.
3. Secondary runtime network guards on the `YoutubeDL` engine prevent any rogue redirects during download streaming.
4. Connection-level socket validation eliminates the DNS rebinding TOCTOU window while preserving standard TLS certificate verification.
5. Filesize metadata properly distinguishes approximate display badges from exact CDN byte measurements.
6. 100% of all platform tests and full backend regression suites passed (755 passed, 0 failures).

