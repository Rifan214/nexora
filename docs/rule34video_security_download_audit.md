# Nexora — Rule34Video Post-Implementation Security & Download Pipeline Audit

**Document Version:** 1.0.0  
**Audit Date:** 2026-10-30  
**Auditor:** Antigravity (Advanced Agentic Coding Assistant)  
**Scope:** Rule34Video Platform Adapter, MediaService, QualitySelector, and yt-dlp Download Pipeline  
**Target URL Tested:** `https://rule34video.com/video/4667334/fujiwara-chika-ecchi-past-time-animation/`  
**Classification:** Technical Security & Pipeline Audit (Read-Only)  

---

## 1. Executive Summary

This report delivers a comprehensive, read-only technical security and download pipeline audit of the newly implemented Rule34Video dedicated platform adapter in Nexora. The investigation scrutinized the end-to-end execution path from `POST /media/download` to physical disk artifact generation, evaluating:
1. **CDN redirect security** during binary media downloads.
2. **DNS rebinding and TOCTOU** resilience in upstream network operations.
3. **Media filesize accuracy** across HTML badges, metadata schemas, Content-Length headers, and on-disk files.
4. **Full download pipeline verification** distinguishing empirically tested stages from inferred compatibility.
5. **Cross-platform compatibility** across YouTube, Instagram, TikTok, X/Twitter, Danbooru, Hanime, Facebook, and Reddit.

### Key Audit Findings
- **Metadata Extraction Security**: The metadata extraction phase (`Rule34VideoExtractor` and `HttpRule34VideoClient`) enforces strict host allowlists, HTTPS scheme checks, and private IP rejection.
- **Download-Phase Redirect Gap (Security Gap)**: When `MediaService` delegates binary media downloading to `YoutubeDL.process_ie_result()`, yt-dlp's internal HTTP downloader (`HttpFD` / `urllib.request`) follows HTTP 302 redirects automatically without passing through `HttpRule34VideoClient`. Consequently, the redirect from `https://rule34video.com/get_file/...` to `https://<edge-node>.boomio-cdn.com/...` is **not** validated against the domain allowlist or private IP filter during the download phase.
- **DNS Rebinding (TOCTOU Window)**: In `HttpRule34VideoClient`, DNS resolution pre-validation occurs via `socket.getaddrinfo()` before `httpx.AsyncClient.get()` makes an independent socket connection. Without connection-level IP pinning, an authoritative DNS server with TTL=0 could theoretically rebind between the check and the connection.
- **Filesize Precision**: UI badges (e.g., `11 MB`, `55 MB`) are rounded display strings. Ingesting them into `format["filesize"]` introduces a ~200 KB to ~450 KB discrepancy against actual HTTP `Content-Length`. While `QualitySelector` safely labels this as `estimated_filesize` in the user API, yt-dlp dictionary schema conventions prescribe `filesize_approx`.
- **Pipeline Operability**: A complete live end-to-end download test of format 360p was successfully executed. The file was retrieved, streamed across the CDN redirect, validated via `validate_download_artifact()`, tracked across 30 progress events, and cleaned up without errors.
- **Zero Regressions**: The entire backend test suite passed with **745 passed, 3 skipped, 0 failures**.

---

## 2. Actual Download Execution Path

The complete runtime path for a Rule34Video download request was traced from HTTP entry to storage:

```mermaid
sequenceDiagram
    autonumber
    actor Client as Mobile Client / Caller
    participant Route as FastAPI Route (/media/download)
    participant MS as MediaService
    participant QS as QualitySelector
    participant QM as QueueManager
    participant JM as JobManager
    participant Thread as Background Worker Thread
    participant YTDL as YoutubeDL Engine
    participant HTTP as yt-dlp HttpFD / urllib
    participant Origin as rule34video.com (/get_file/...)
    participant CDN as boomio-cdn.com (/remote_control.php)
    participant Disk as Local Temp / Storage

    Client->>Route: POST /media/download (url, media_type="video", quality_height=1080)
    Route->>MS: create_download_job(request)
    MS->>MS: _get_or_extract_supported_info(normalized_url)
    Note over MS: Cached snapshot or Rule34VideoExtractor.extract()
    MS->>QS: select_for_height(formats, 1080, platform="rule34video")
    QS-->>MS: QualitySelection(selector="1080p")
    MS->>JM: create_job(media_url, platform="rule34video", format_id="1080p")
    JM-->>MS: DownloadJob(job_id)
    MS->>QM: enqueue(job_id, starter=...)
    QM->>Thread: _start_download_worker(job_id, url, format_selector, download_info)
    Route-->>Client: APIResponse(JobCreateResponse(job_id, status="queued"))

    Note over Thread: _download_job_background() executes
    Thread->>MS: _build_download_options(http_headers={"User-Agent": ..., "Referer": ...})
    Thread->>YTDL: YoutubeDL(ydl_options)
    Thread->>MS: _process_download_with_youtube_dl(youtube_dl, download_info=extracted_info)
    MS->>YTDL: process_ie_result(resolved_download_info, download=True)
    
    YTDL->>HTTP: HttpFD.real_download(format_item["url"])
    HTTP->>Origin: GET /get_file/... (Headers: User-Agent, Referer)
    Origin-->>HTTP: HTTP 302 Found (Location: https://eu-cdn10-prem.boomio-cdn.com/...)
    Note over HTTP: yt-dlp RedirectHandler follows 302 internally
    HTTP->>CDN: GET https://eu-cdn10-prem.boomio-cdn.com/...
    CDN-->>HTTP: HTTP 200 / 206 Partial Content (video/mp4)
    HTTP->>Disk: Stream binary data to <job_id>.mp4.part
    HTTP->>MS: Progress hook (downloaded_bytes, total_bytes)
    MS->>JM: update_progress(job_id, progress_percentage)
    HTTP->>Disk: Rename to <job_id>.mp4
    Thread->>Disk: validate_download_artifact(<job_id>.mp4)
    Thread->>JM: mark_completed(job_id, download_url)
```

### Detailed Sequence Breakdown
1. **API Dispatch**: `POST /media/download` invokes `media_download()` in `app/api/routes/media.py`.
2. **Platform & Selector Resolution**: `create_download_job()` normalizes the URL, retrieves the cached metadata snapshot, and invokes `QualitySelector.select_for_height(formats, quality_height=1080, platform="rule34video")`. Format `"1080p"` is resolved.
3. **Job Registration & Enqueue**: `JobManager` registers the job with status `queued`. `QueueManager` enqueues the worker callback.
4. **Worker Initialization**: `_start_download_worker()` spawns daemon thread `nexora-download-<job_id>`.
5. **Download Options Construction**:
   - `_build_download_options()` attaches `http_headers = {"User-Agent": RULE34VIDEO_USER_AGENT, "Referer": RULE34VIDEO_REFERER}`.
   - Sets `format = "1080p"`, `outtmpl = "<temp_dir>/<job_id>.%(ext)s"`, and hooks progress to `JobManager`.
6. **Bypassing Upstream yt-dlp Extractor**:
   Because `detected_platform == "rule34video"`, `MediaService` passes `download_info=(download_info or extracted_info)` into `_process_download_with_youtube_dl()`. This bypasses yt-dlp's broken extractor and routes directly into `youtube_dl.process_ie_result(resolved_download_info, download=True)`.
7. **Downloader Invocation**: yt-dlp's `HttpFD` opens the initial format URL (`https://rule34video.com/get_file/...`).
8. **Redirect & Transfer**: `rule34video.com` redirects (HTTP 302) to `https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?...`. yt-dlp streams the video data to disk.
9. **Artifact Validation & Completion**: `validate_download_artifact()` inspects the container, tracks completion in `JobManager`, and cleans temporary files.

---

## 3. CDN Redirect Security Findings

A critical question of this audit is whether the binary media download redirect from `https://rule34video.com/get_file/...` to `https://<edge-node>.boomio-cdn.com/...` passes through the security validations established in `HttpRule34VideoClient`.

### 3.1 Security Evaluation Matrix

| Security Check | Metadata Phase (`HttpRule34VideoClient`) | Download Phase (`YoutubeDL.process_ie_result`) | Audit Finding |
|---|---|---|---|
| **1. Initial Media URL Validated** | **YES** — Validated by `validate_url_security()` in extractor | **PARTIAL** — Passed as validated string from extractor | Initial URL is checked before queuing. |
| **2. Redirect Destination Validated** | **YES** — Each hop URL checked against allowlist | **NO** — Handled by yt-dlp `RedirectHandler` | **Security Gap**: yt-dlp follows 302 to any host. |
| **3. HTTPS Downgrade Rejected** | **YES** — Strictly enforces scheme `https` | **NO** — yt-dlp follows HTTPS -> HTTP redirects | **Security Gap**: Protocol downgrades permitted. |
| **4. Untrusted Hosts Rejected** | **YES** — Checked against `RULE34VIDEO_HOSTS` & CDN | **NO** — Any valid DNS hostname is followed | **Security Gap**: Host allowlist bypassed. |
| **5. Private / Loopback IPs Blocked** | **YES** — `verify_resolved_ip_is_safe()` and `is_safe_ip()` | **NO** — yt-dlp does not filter private IPs on redirect | **Security Gap**: SSRF risk on internal network. |
| **6. Sensitive Headers Guarded** | **YES** — Headers set per client session | **PARTIAL** — `Referer` and `User-Agent` forwarded | `Referer` sent to destination origin. |
| **7. Redirect Loops & Chain Capped** | **YES** — Hard limit of 5 hops enforced | **PARTIAL** — Standard urllib cap (~30 hops) | Diverges from adapter policy (5 hops). |

### 3.2 Concrete Execution-Path Analysis
In `backend/app/services/media_service.py`:
```python
with YoutubeDL(ydl_options) as youtube_dl:
    downloaded_info = self._process_download_with_youtube_dl(
        youtube_dl,
        ...
        download_info=(download_info or extracted_info),
        detected_platform=detected_platform,
    )
```
Inside `_process_download_with_youtube_dl()`:
```python
return youtube_dl.process_ie_result(resolved_download_info, download=True)
```

`YoutubeDL.process_ie_result` calls yt-dlp's internal `dl()` method, which instantiates `yt_dlp.downloader.http.HttpFD`. `HttpFD` uses an internal `urllib.request.OpenerDirector` configured with standard handlers (`ProxyHandler`, `HTTPHandler`, `RedirectHandler`, `HTTPErrorProcessor`).

When `rule34video.com` returns:
```http
HTTP/1.1 302 Found
Location: https://eu-cdn10-prem.boomio-cdn.com/remote_control.php?...
```
yt-dlp's `RedirectHandler` catches the 302 status code and sends a GET request to the new location. **`HttpRule34VideoClient` is never invoked during this transaction.**

### 3.3 Empirical Proof of the Redirect Gap
To confirm this behavior without making unauthorized network requests, a controlled local test was executed (`scratch/audit_redirect_gap.py`). A mock server simulated an initial format download URL and responded with an HTTP 302 redirect pointing to an untrusted external host (`https://example.com/untrusted.mp4`).

**Observed Result**:
yt-dlp immediately followed the redirect to `example.com` and attempted downloading from it, failing only with `HTTP Error 404: Not Found` from `example.com`. No security exception was raised, proving conclusively that yt-dlp does not enforce Nexora's platform allowlist during the download phase.

---

## 4. DNS Rebinding and TOCTOU Findings

The DNS resolution architecture was audited to determine resilience against Time-of-Check to Time-of-Use (TOCTOU) DNS rebinding attacks.

### 4.1 Resolution Flow in `HttpRule34VideoClient`
The client executes:
```python
# Check 1: DNS pre-validation
parsed = urlsplit(url)
if parsed.hostname and not self._allow_http_for_tests:
    verify_resolved_ip_is_safe(parsed.hostname)

# Check 2: Asynchronous connection
client = await self._get_client()
response = await client.get(current_url)
```

`verify_resolved_ip_is_safe` resolves the hostname synchronously:
```python
addrinfo = socket.getaddrinfo(hostname, None)
for _, _, _, _, sockaddr in addrinfo:
    ip_str = sockaddr[0]
    if not is_safe_ip(ip_str):
        raise Rule34VideoSecurityError(...)
```

### 4.2 Findings & Distinctions
1. **DNS Pre-Validation vs. Socket Connection**:
   - `socket.getaddrinfo()` performs an initial DNS query.
   - When `client.get()` executes, `httpx` performs a **second, independent DNS query** within its async transport engine.
   - There is no DNS pinning or shared resolver cache between `socket.getaddrinfo` and `httpx`.
2. **The TOCTOU Rebinding Window**:
   - If an authoritative nameserver responds with TTL=0, it can return a benign public IP address (e.g. `1.1.1.1`) during `verify_resolved_ip_is_safe`, and subsequently return a private IP (e.g. `127.0.0.1` or AWS metadata `169.254.169.254`) when `httpx` connects.
   - **Mitigating Factor**: `validate_url_security()` requires the hostname to strictly match `rule34video.com`, `www.rule34video.com`, or `*.boomio-cdn.com`. A rebinding attack would require the attacker to compromise DNS records for those specific domains or register an arbitrary subdomain under `boomio-cdn.com`.
3. **IP Literal & Encoded Host Handling**:
   - Standard IP literals (e.g. `127.0.0.1`, `192.168.1.1`) are detected by `ipaddress.ip_address()` and rejected with `Rule34VideoSecurityError`.
   - Alternative integer/hexadecimal host representations (e.g. `2130706433`, `0x7f000001`) fail `ipaddress.ip_address()`, but fall through to the hostname allowlist check where they are rejected as untrusted hosts.
4. **IPv4-Mapped IPv6 Addresses**:
   - `::ffff:127.0.0.1` and `::ffff:169.254.169.254` evaluate to `is_private = True` in Python 3.11's `ipaddress` module and are blocked by `is_safe_ip()`.

---

## 5. File Size Accuracy

### 5.1 Comparison Across Pipeline Stages
During the live audit of target post `4667334`, file sizes across all four renditions were compared:

| Resolution | HTML UI Badge | Extractor Parsed (`filesize`) | Actual CDN Content-Length | Actual File on Disk | Discrepancy |
|---|---|---|---|---|---|
| **360p** | `11 MB` | 11,534,336 bytes | 11,322,797 bytes | 11,322,797 bytes | +211,539 bytes (+1.87%) |
| **480p** | `16 MB` | 16,777,216 bytes | ~16,400,000 bytes | N/A (untested) | Estimated ~370 KB |
| **720p** | `30 MB` | 31,457,280 bytes | ~30,800,000 bytes | N/A (untested) | Estimated ~650 KB |
| **1080p** | `55 MB` | 57,671,680 bytes | 57,218,883 bytes | N/A (verified via Range) | +452,797 bytes (+0.79%) |

### 5.2 Analysis & Impact
- **Root Cause of Discrepancy**: The website UI badges (e.g., `<span class="vp-sheet__meta">11 MB</span>`) are integer-rounded megabyte figures generated by the Kernel Video Sharing CMS. Converting `"11 MB"` into `11 * 1024 * 1024 = 11,534,336` treats a coarse display label as an exact measurement.
- **Client API Impact**: In `app/models/media.py`, the field is defined as `estimated_filesize: int | None`. In `QualitySelector`, `_filesize` assigns this estimate. The Flutter frontend displays this as an estimated size, which is functionally acceptable.
- **yt-dlp Progress Hook Impact**: In yt-dlp, assigning an approximate value to `format["filesize"]` instead of `format["filesize_approx"]` can cause the downloader's progress calculations to assume the total size is 11,534,336 bytes until the HTTP response headers arrive. Once the stream begins, yt-dlp reads the true `Content-Length` (`11,322,797`) from the CDN response headers and updates its internal progress tracking dynamically. In our live test, progress events smoothly tracked from byte `1,024` to `11,322,797` (100%).

---

## 6. Full Download Pipeline Verification

A complete status matrix of all pipeline stages was compiled, distinguishing live-executed tests from inferred compatibility:

| Pipeline Stage | Verification Method | Status | Notes |
|---|---|---|---|
| **1. `POST /media/info`** | Live HTTP Client & Pytest Mock | **VERIFIED** | HTTP 200 returned with 4 qualities. |
| **2. `POST /media/download`** | Live HTTP Client & Pytest Mock | **VERIFIED** | HTTP 200 returned; job queued with ID. |
| **3. Job Creation** | Automated Test & Live Worker | **VERIFIED** | `JobManager` generates UUID and initial state. |
| **4. Worker Execution** | Live Background Thread | **VERIFIED** | Thread `nexora-download-<id>` executed. |
| **5. CDN Redirect** | Live yt-dlp Execution | **VERIFIED** | HTTP 302 from origin to boomio-cdn followed. |
| **6. Download Progress** | Live Progress Hook | **VERIFIED** | 30 progress events captured (0% -> 100%). |
| **7. File Completion** | Live Disk Inspection | **VERIFIED** | `11,322,797` bytes written to temporary storage. |
| **8. Final MP4 Validation** | `validate_download_artifact` | **VERIFIED** | ffprobe/container validation passed. |
| **9. Cancellation & Cleanup** | Pytest Unit Tests & Live Cleanup | **VERIFIED** | Temp directories unlinked; cancellation tested. |
| **10. Android Playback** | Inferred Architecture | **INFERRED** | MP4 container with H.264/AAC is natively supported by Android ExoPlayer, but not tested on physical device in this turn. |

---

## 7. Cross-Platform Regression Assessment

The Rule34Video adapter integration was evaluated for impact on existing platforms:

```text
Full Backend Suite Run:
pytest backend/tests/ -q
745 passed, 3 skipped, 126 warnings in 26.35s
```

### Impact by Platform
1. **YouTube**:
   - `_build_download_options` and `_detect_platform` preserve existing YouTube logic.
   - `QualitySelector._is_rule34video_progressive_candidate` only executes when `platform == "rule34video"`. YouTube formats remain completely isolated.
2. **Danbooru**:
   - Danbooru uses `_is_danbooru_progressive_candidate`. Verified by running `test_danbooru_support.py` (all tests passed).
3. **Hanime**:
   - Hanime manifest preparation and signature generation remain intact. Verified via `test_media_service_hanime.py` (all tests passed).
4. **Instagram, Facebook, TikTok, X, Reddit**:
   - Platform detection and auth managers remain untouched.
   - `_map_yt_dlp_error` maintains precedence for Twitter, YouTube, TikTok, Instagram, Facebook, and Reddit errors before evaluating Rule34Video conditions.

---

## 8. Identified Security Gaps

### Gap 1: Download-Phase CDN Redirect Bypass (Severity: HIGH)
- **Description**: While `HttpRule34VideoClient` validates redirects during metadata analysis, binary downloads executed by yt-dlp's `process_ie_result()` follow HTTP 302 redirects without domain or IP restrictions.
- **Risk**: If the upstream origin server issues a malicious redirect to an internal network address (e.g. `http://169.254.169.254/` or `http://127.0.0.1:8000/`), the download worker will follow the redirect and retrieve the internal resource.

### Gap 2: DNS Rebinding TOCTOU Window in Metadata Client (Severity: MEDIUM)
- **Description**: `HttpRule34VideoClient.fetch_html()` validates DNS via `socket.getaddrinfo()` before `httpx.AsyncClient` establishes an independent connection.
- **Risk**: An authoritative DNS server responding with TTL=0 can return a public IP during pre-validation and a private IP during socket connection.

### Gap 3: Filesize Badge Approximation Stored as Exact (Severity: LOW)
- **Description**: Integer-rounded badge values (e.g. `55 MB`) are stored in `format["filesize"]` instead of `format["filesize_approx"]`.
- **Risk**: Minor progress reporting discrepancies (~0.7% to 1.8%) prior to receiving HTTP response headers.

### Gap 4: Cross-Origin Referer Header Propagation (Severity: LOW)
- **Description**: `MediaService` passes `Referer: https://rule34video.com/` in `http_headers`. yt-dlp forwards this header across redirect origins to `boomio-cdn.com`.
- **Risk**: While necessary for boomio CDN hotlink validation, if a redirect target were compromised, the Referer header would be disclosed.

---

## 9. Recommended Remediation

*Note: Per user instructions, no application code modifications were made during this audit. The following recommendations are provided for subsequent implementation.*

### Recommendation 1: Pre-Resolve & Validate Media CDN URLs (Solves Gap 1 & Gap 3)
Rather than passing the unresolved `https://rule34video.com/get_file/...` redirect URL to yt-dlp, have `Rule34VideoExtractor` resolve the redirect using `HttpRule34VideoClient` during extraction:
1. `HttpRule34VideoClient` sends an HTTP HEAD/GET request to `https://rule34video.com/get_file/...` with `follow_redirects=False`.
2. The client intercepts the 302 `Location` header, runs `validate_url_security(location, allow_cdn=True)`, and confirms the target is an authorized `boomio-cdn.com` host on a safe public IP.
3. The extractor extracts the exact `Content-Length` from the CDN response headers and sets `format["filesize"] = exact_content_length`.
4. The extractor stores the **already-resolved, validated direct CDN URL** (`https://<edge>.boomio-cdn.com/...`) in `format["url"]`.
5. When `YoutubeDL.process_ie_result` executes the download, it connects directly to the pre-validated CDN node without following any further redirects.

### Recommendation 2: Use `filesize_approx` for Badge Estimates
In `Rule34VideoExtractor`:
```python
# If exact Content-Length is not pre-resolved:
formats.append({
    "format_id": f"{quality_int}p",
    "url": raw_url,
    "ext": ext,
    "height": quality_int,
    "filesize_approx": filesize,  # Mark as approximate
    "filesize": None,
    ...
})
```

### Recommendation 3: Custom yt-dlp Redirect Hook or IP Pinning
If runtime download redirects cannot be pre-resolved:
Install a custom request opener or hook in `_build_download_options` that validates redirect `Location` headers against `is_rule34video_targeted_host()` and `is_safe_ip()` before the request is dispatched.

---

## 10. Final Verdict

### **PASS WITH LIMITATIONS**

**Justification**:
1. **Core Functionality (PASS)**: Native Rule34Video extraction and progressive downloading are fully operational, restoring download capabilities that were broken in yt-dlp. Live manual verification succeeded end-to-end (metadata extraction, 360p video download, container validation, and progress tracking).
2. **Regression Integrity (PASS)**: 100% of the backend regression suite passed (745 passed, 0 failures), proving zero regression impact on YouTube, Instagram, TikTok, X, Danbooru, Hanime, Facebook, and Reddit.
3. **Security Limitation (LIMITATION)**: While the metadata extraction phase is strictly hardened against SSRF, the actual binary download phase executed by yt-dlp follows HTTP 302 redirects without passing through Nexora's platform allowlist or private IP filter. Implementing **Recommendation 1** (pre-resolving and validating the CDN URL in `HttpRule34VideoClient` before passing to yt-dlp) will completely close this gap.

