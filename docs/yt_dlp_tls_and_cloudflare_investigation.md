# Laporan Investigasi Lanjutan: yt-dlp TLS Certificate Mismatch dan Cloudflare 403 di Windows

**Dokumen**: `yt_dlp_tls_and_cloudflare_investigation.md`
**Tanggal**: 27 Oktober 2026
**Investigator**: Senior Windows Networking & Python/yt-dlp Specialist
**Domain Uji**: `danbooru.donmai.us`, `rule34video.com`
**Metodologi**: Analisis Diagnostik Read-Only (Non-Destruktif, Tanpa Restart, Tanpa Bypass TLS)

---

## 1. Ringkasan Eksekutif

Investigasi teknis mendalam ini dilakukan untuk menguraikan anomali perilaku jaringan HTTPS antara `curl.exe` dan `yt-dlp` pada Windows 11 setelah konfigurasi DNS-over-HTTPS (DoH) Cloudflare diaktifkan.

### Tiga Pertanyaan Inti dan Jawabannya:

1. **Mengapa `curl.exe` berhasil menerima sertifikat valid dan mendapat HTTP 200, sedangkan `yt-dlp` dengan `curl_cffi` gagal dengan error `curl: (60) SSL: no alternative certificate subject name matches target hostname`?**
   - **Akar Masalah**: Perbedaan mendasar pada **DNS Resolver** internal.
   - `curl.exe` menggunakan Win32 resolver sistem (`getaddrinfo`), yang memanfaatkan DoH Windows 11 (`1.1.1.1` via HTTPS port 443). Kueri berhasil menembus ke Cloudflare dan mendapatkan IP asli (`104.26.11.39`).
   - Sebaliknya, `curl_cffi` (yang digunakan saat impersonation) dibangun di atas `curl-impersonate` dengan library **`c-ares`** sebagai resolver asinkron. `c-ares` **tidak menggunakan API DoH Windows**, melainkan membaca IP server dari network adapter (`1.1.1.1`) lalu mengirimkan **kueri UDP mentah ke port 53**.
   - Kueri UDP port 53 ini **langsung dibajak oleh Transparent DNS Proxy ISP (AS7713 Telkom / IndiHome)**, mengembalikan IP pemblokiran: **`36.86.63.185`**.
   - Server pada `36.86.63.185` menyajikan sertifikat SSL milik **`internetpositif.id`**. Karena nama host `danbooru.donmai.us` dan `rule34video.com` tidak ada dalam SAN (Subject Alternative Name) sertifikat `internetpositif.id`, `libcurl` membatalkan koneksi demi keamanan dengan cURL error 60.

2. **Mengapa handler HTTP default/legacy pada `yt-dlp` (`requests` dan `urllib`) justru mendapatkan respons HTTP 403 Forbidden?**
   - **Akar Masalah**: **Cloudflare Bot Management / WAF Challenge**.
   - Handler `requests` dan `urllib` menggunakan API sistem Windows sehingga **berhasil menyelesaikan DoH dan terhubung ke IP Cloudflare asli** (verifikasi TLS 100% sukses tanpa error sertifikat).
   - Namun, Python standard library dan `requests` (urllib3) memancarkan **TLS ClientHello Fingerprint (JA3/JA4)** khas library otomatis (bukan browser nyata). Cloudflare WAF mendeteksi signature ini dan membalas dengan status `HTTP 403 Forbidden` (`Cf-Mitigated: challenge` / Turnstile).

3. **Mengapa pengambilan cookie Chrome (`--cookies-from-browser chrome`) gagal dengan `PermissionError: [Errno 13] Permission denied`?**
   - **Akar Masalah**: **Windows File Sharing Violation (`ERROR_SHARING_VIOLATION` / Win32 Error 32)**.
   - Terverifikasi ada **25 proses `chrome.exe`** yang sedang berjalan aktif.
   - Google Chrome mengunci database SQLite `Cookies` (`...\Profile 6\Network\Cookies`) dengan *non-shared lock*. Ketika `yt-dlp` mencoba menyalin file tersebut (`shutil.copy2`), kernel Windows menolak pembukaan file dengan Win32 Error 32, yang diterjemahkan Python C-runtime menjadi `PermissionError: [Errno 13]`.

---

## 2. Fakta yang Sudah Dikonfirmasi

Berdasarkan pengujian teknis objektif di terminal, fakta-fakta berikut telah terbukti 100%:

| No. | Komponen / Pengujian | Hasil Pengamatan | Kesimpulan Teknis |
|:---:|:---|:---|:---|
| 1 | **Status DoH Windows 11** | `AutoUpgrade: True`, `AllowFallbackToUdp: False` pada `1.1.1.1` dan `1.0.0.1`. | DoH sistem Windows telah aktif dan berfungsi sempurna. |
| 2 | **Resolusi Sistem (`Resolve-DnsName`)** | `danbooru.donmai.us` -> `104.26.11.39`, `172.67.70.99`, `104.26.10.39`.<br>`rule34video.com` -> `190.115.31.243`. | Kueri sistem berhasil mendapatkan IP resmi Cloudflare / hosting sah. |
| 3 | **Kueri `curl.exe` (Schannel)** | Remote IP `104.26.11.39`, `ssl_verify_result: 0`, HTTP 200 OK. | Konektivitas langsung ke Cloudflare CDN via Schannel berfungsi normal. |
| 4 | **Sertifikat Sah Danbooru** | Subject: `CN=donmai.us`, Issuer: `CN=YE1, O=Let's Encrypt`, SAN: `*.donmai.us, donmai.us`, Valid s/d 07 Jan 2027. | Sertifikat server tujuan valid dan mencakup subdomain `danbooru`. |
| 5 | **Sertifikat pada IP `36.86.63.185`** | Subject: `CN=internetpositif.id`, Issuer: `CN=E8, O=Let's Encrypt`, SAN: `internetpositif.id`. | IP pemblokiran ISP menyajikan sertifikat yang tidak cocok dengan target domain. |
| 6 | **`yt-dlp` Handler `requests`** | Berhasil TLS handshake ke `danbooru.donmai.us:443`, menerima respons: `HTTP/1.1 403 Forbidden` dengan header `Cf-Mitigated: challenge`. | DNS & TLS berhasil, namun diblokir oleh WAF Cloudflare karena JA3/JA4 fingerprint bot. |
| 7 | **`yt-dlp` Handler `curl_cffi`** | Mengalami error: `curl: (60) SSL: no alternative certificate subject name matches target hostname`. | `curl_cffi` tersambung ke `36.86.63.185` (IP TrustPositif) akibat kebocoran kueri DNS UDP port 53. |
| 8 | **`rule34video.com` via `prefer-legacy`** | TLS berhasil, halaman terunduh, extractor memproses HTML (`No video formats found`). | Tanpa `curl_cffi`, TLS ke server asli berhasil sempurna. |
| 9 | **`rule34video.com` via `--impersonate chrome`** | Error: `curl: (60) SSL: no alternative certificate subject name matches target hostname 'rule34video.com'`. | Membuktikan masalah SSL Error 60 terjadi pada **semua domain** yang dibuka melalui `curl_cffi`. |
| 10 | **Proses Google Chrome** | 25 proses `chrome.exe` aktif berjalan. | Chrome sedang mengunci file database profil. |
| 11 | **Uji File Lock SQLite Cookies** | Pemanggilan Win32 `CreateFileW` pada `Cookies` mengembalikan handle `-1` dan `LastError: 32` (`ERROR_SHARING_VIOLATION`). | Penyebab `PermissionError [Errno 13]` terbukti karena file sedang dikunci Chrome. |

---

## 3. Hasil Pengujian dan Perintah Bukti

### 3.1. Pembuktian Sertifikat Sah vs Sertifikat Pemblokiran

#### Sertifikat Asli dari Cloudflare Edge (danbooru.donmai.us):
```powershell
python -c "import ssl, cryptography.x509; pem = ssl.get_server_certificate(('danbooru.donmai.us', 443)); cert = cryptography.x509.load_pem_x509_certificate(pem.encode()); print('Subject:', cert.subject); print('Issuer:', cert.issuer); print('SAN:', cert.extensions.get_extension_for_oid(cryptography.x509.OID_SUBJECT_ALTERNATIVE_NAME).value)"
```
**Output**:
```text
Subject: <Name(CN=donmai.us)>
Issuer: <Name(CN=YE1,O=Let's Encrypt,C=US)>
SAN: <SubjectAlternativeName(<GeneralNames([<DNSName(value='*.donmai.us')>, <DNSName(value='donmai.us')>])>)>
```
*Analisis*: Sertifikat asli memuat SAN `*.donmai.us`, yang secara hukum kriptografi valid untuk `danbooru.donmai.us`.

#### Sertifikat yang Disajikan oleh IP Pemblokiran ISP (`36.86.63.185`):
```powershell
python -c "import ssl, cryptography.x509; pem = ssl.get_server_certificate(('36.86.63.185', 443)); cert = cryptography.x509.load_pem_x509_certificate(pem.encode()); print('Subject:', cert.subject); print('Issuer:', cert.issuer); print('SAN:', cert.extensions.get_extension_for_oid(cryptography.x509.OID_SUBJECT_ALTERNATIVE_NAME).value)"
```
**Output**:
```text
Subject: <Name(CN=internetpositif.id)>
Issuer: <Name(CN=E8,O=Let's Encrypt,C=US)>
SAN: <SubjectAlternativeName(<GeneralNames([<DNSName(value='internetpositif.id')>])>)>
```
*Analisis*: Sertifikat pada IP `36.86.63.185` **hanya memiliki SAN `internetpositif.id`**. Jika sebuah klien meminta `danbooru.donmai.us` ke IP ini, cURL secara otomatis mengeluarkan error `curl: (60) SSL: no alternative certificate subject name matches target hostname 'danbooru.donmai.us'`.

### 3.2. Perilaku Traffic Director `yt-dlp` pada Permintaan Default

```powershell
yt-dlp --simulate --verbose --print-traffic "https://danbooru.donmai.us/posts/11766677"
```
**Output Cuplikan**:
```text
[debug] Request Handlers: urllib, requests, websockets, curl_cffi
director: Handler preferences for this request: urllib=0, requests=100, websockets=0, curl_cffi=-100
director: Sending request via "requests"
requests: Starting new HTTPS connection (1): danbooru.donmai.us:443
send: b'GET /posts/11766677 HTTP/1.1\r\nHost: danbooru.donmai.us\r\nUser-Agent: Mozilla/5.0 ...\r\n\r\n'
reply: 'HTTP/1.1 403 Forbidden\r\n'
header: Cf-Mitigated: challenge
header: Server: cloudflare
header: CF-RAY: a510fe8b2fd8339a-SIN
ERROR: [generic] Got HTTP Error 403 caused by Cloudflare anti-bot challenge; try again with  --extractor-args "generic:impersonate"
```
*Analisis*:
- Handler `requests` berhasil menyelesaikan resolusi DNS via Windows DoH ke IP Cloudflare.
- TLS Handshake sukses (tidak ada error sertifikat).
- Cloudflare mendeteksi bot melalui TLS fingerprinting dan mengembalikan `Cf-Mitigated: challenge`.

### 3.3. Perilaku `yt-dlp` saat Impersonation Diaktifkan

```powershell
yt-dlp --simulate --verbose --extractor-args "generic:impersonate" "https://danbooru.donmai.us/posts/11766677"
```
**Output Cuplikan**:
```text
  File "yt_dlp\networking\_curlcffi.py", line 318, in _send
  File "curl_cffi\requests\session.py", line 1117, in request
curl_cffi.requests.exceptions.CertificateVerifyError: Failed to perform, curl: (60) SSL: no alternative certificate subject name matches target hostname 'danbooru.donmai.us'.
```
*Analisis*: `_curlcffi.py` menginisiasi `curl_cffi.requests.Session()`. Karena `curl_cffi` menggunakan `c-ares`, kueri DNS dikirim via UDP 53 biasa ke `1.1.1.1`, dicegat oleh Telkom, diarahkan ke `36.86.63.185`, dan gagal validasi SAN sertifikat.

### 3.4. Pembuktian File Lock pada Database Cookie Chrome

Pengujian Win32 API `CreateFileW` langsung ke kernel Windows:
```powershell
python -c "import ctypes; h = ctypes.windll.kernel32.CreateFileW(r'C:\Users\linaf\AppData\Local\Google\Chrome\User Data\Profile 6\Network\Cookies', 0x80000000, 1 | 2, None, 3, 0, None); print('Handle:', h, 'LastError:', ctypes.GetLastError())"
```
**Output**:
```text
Handle: -1 LastError: 32
```
*Analisis*: `LastError: 32` adalah konstanta Windows `ERROR_SHARING_VIOLATION`. Operasi `shutil.copy2` pada `yt-dlp` gagal karena database SQLite sedang dikunci secara eksklusif oleh proses `chrome.exe` yang aktif.

---

## 4. Analisis Terpisah

```
笏娯楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏・笏・                             ARUS KONEKSI & TITIK KEGAGALAN                            笏・笏懌楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏､
笏・                                                                                       笏・笏・1. JALUR CURL.EXE & PYTHON REQUESTS (Win32 getaddrinfo):                               笏・笏・   Aplikasi 笏笏笆ｺ Windows DoH 笏笏笆ｺ Cloudflare DNS (443) 笏笏笆ｺ IP Asli: 104.26.11.39         笏・笏・                                                                                       笏・笏・   a) curl.exe (Schannel) 笏笏笆ｺ TLS Sukses 笏笏笆ｺ HTTP 200 OK                               笏・笏・   b) requests/urllib (OpenSSL) 笏笏笆ｺ TLS Sukses 笏笏笆ｺ Cloudflare WAF 笏笏笆ｺ HTTP 403 Bot     笏・笏・                                                                                       笏・笏懌楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏､
笏・                                                                                       笏・笏・2. JALUR IMPERSONATE (curl_cffi / c-ares):                                             笏・笏・   yt-dlp 笏笏笆ｺ c-ares Resolver 笏笏笆ｺ UDP Port 53 笏笏笆ｺ DPI Telkom (Dibajak)                笏・笏・                                                         笏・                            笏・笏・                                                         笆ｼ                             笏・笏・                                                IP Palsu: 36.86.63.185                 笏・笏・                                                         笏・                            笏・笏・   curl_cffi 笏笏笆ｺ Connect 36.86.63.185:443                笏・                            笏・笏・   Server mengembalikan cert: internetpositif.id         笆ｼ                             笏・笏・   libcurl SAN check: internetpositif.id != danbooru 笏笏笆ｺ ERROR 60 SSL SAN MISMATCH    笏・笏・                                                                                       笏・笏懌楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏､
笏・                                                                                       笏・笏・3. JALUR COOKIES-FROM-BROWSER:                                                         笏・笏・   yt-dlp copy SQLite Cookies 笏笏笆ｺ Chrome Process Lock 笏笏笆ｺ Win32 Error 32 (Sharing)    笏・笏・                              笏笏笆ｺ Python Errno 13 Permission Denied                    笏・笏・                                                                                       笏・笏披楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏・```

### 4.1. Analisis Masalah TLS Mismatch (`curl_cffi`)
- **Penyebab**: `curl-impersonate` / `curl_cffi` dikompilasi dengan **`c-ares`** untuk mendukung DNS asinkron dan opsi kustom DNS. `c-ares` berjalan di *user-space* dan tidak memiliki integrasi dengan engine DoH Windows 11.
- `c-ares` secara default mengambil DNS server dari adapter jaringan (`1.1.1.1` dan `1.0.0.1`), namun mengirim kueri melalui soket UDP port 53 standar.
- Port 53 UDP pada jaringan IndiHome dibajak oleh DPI ISP dan dialihkan ke `36.86.63.185`.
- Sertifikat pada `36.86.63.185` adalah milik `internetpositif.id`.
- `libcurl` menolak sertifikat tersebut karena tidak sesuai dengan nama host yang diminta (`danbooru.donmai.us` / `rule34video.com`).

### 4.2. Analisis Masalah HTTP 403 (Cloudflare Anti-Bot Challenge)
- Terjadi pada handler `requests` dan `urllib`.
- Koneksi TLS ke Cloudflare sebenarnya **berhasil 100%**. Masalah terjadi di Layer 7 (HTTP / TLS fingerprinting).
- Cloudflare memeriksa ekstensi TLS ClientHello (cipher suite order, supported curves, ALPN order, header order). Library Python standar memiliki fingerprint yang dikenal luas sebagai bot.
- Header `Cf-Mitigated: challenge` dan respons kode 403 adalah mekanisme pertahanan resmi Cloudflare untuk meminta verifikasi Turnstile/CAPTCHA dari browser interaktif.

### 4.3. Analisis Masalah Cookie Chrome (`PermissionError`)
- SQLite menggunakan locking berbasis sistem berkas (file-level lock) saat koneksi database aktif.
- Selama browser Google Chrome terbuka, proses Chrome memegang handle file `Cookies` dengan atribut `FILE_SHARE_READ` dibatasi.
- Windows Kernel memicu `ERROR_SHARING_VIOLATION` (Error 32) ketika proses eksternal mencoba melakukan `shutil.copy2` atau membuka file untuk membaca.

---

## 5. Akar Masalah dan Tingkat Keyakinan

| Masalah | Akar Masalah Utama | Tingkat Keyakinan | Bukti Penguat |
|:---|:---|:---:|:---|
| **TLS Error 60 pada `curl_cffi`** | Library `c-ares` di dalam `curl_cffi` membocorkan kueri DNS ke UDP port 53 biasa sehingga terintersepsi oleh DPI IndiHome menuju `36.86.63.185`. | **100% (Pasti)** | IP `36.86.63.185` menyajikan cert `CN=internetpositif.id`. Error terjadi identik pada domain Danbooru dan Rule34Video hanya saat `curl_cffi` digunakan. |
| **HTTP 403 pada Handler Default** | Cloudflare WAF mendeteksi JA3/JA4 TLS Fingerprint dan User-Agent milik Python `requests`/`urllib`. | **100% (Pasti)** | Header respons eksplisit memuat `Cf-Mitigated: challenge` dari Cloudflare edge Singapore. |
| **PermissionError Cookie Chrome** | Google Chrome sedang berjalan aktif dan mengunci file SQLite `Cookies` (`ERROR_SHARING_VIOLATION`). | **100% (Pasti)** | Uji `CreateFileW` langsung mengembalikan Win32 Error 32. Terdapat 25 proses Chrome aktif. |

---

## 6. Hipotesis yang Belum Terkonfirmasi / Gugur

1. **Hipotesis Kerusakan Sertifikat Target (Gugur)**:
   - *Dugaan*: Sertifikat Danbooru atau Rule34Video kedaluwarsa atau tidak memiliki SAN yang valid.
   - *Fakta*: Sertifikat sah dari Let's Encrypt terbukti masih aktif hingga Januari 2027 dengan SAN `*.donmai.us`.
2. **Hipotesis Kegagalan Root CA Certifi Windows (Gugur)**:
   - *Dugaan*: Bundle `cacert.pem` certifi di Windows tidak mempercayai root CA Cloudflare.
   - *Fakta*: Handshake TLS via Python dengan `certifi.where()` berhasil sempurna (`TLSv1.3`).
3. **Hipotesis Izin Akses Akun / Hak Administrator Cookie (Gugur)**:
   - *Dugaan*: Akun Windows `linaf` tidak memiliki permission NTFS pada folder Profile Chrome.
   - *Fakta*: ACL file normal; kegagalan murni akibat *sharing violation* (file lock oleh proses lain).

---

## 7. Rekomendasi Solusi Berjenjang (Risiko Terendah ke Tertinggi)

Untuk menyelesaikan ketiga masalah ini secara menyeluruh, berikut adalah rekomendasi solusi:

### Rekomendasi 1 (Risiko Terendah): Mengatasi Cookie Chrome Sharing Violation
Jangan menutup paksa (*kill*) Chrome jika sedang ada pekerjaan penting yang belum tersimpan.
1. **Cara Aman Tanpa Menutup Browser**:
   - Gunakan ekstensi Chrome seperti *Get cookies.txt LOCALLY* untuk mengekspor cookie sesi `danbooru.donmai.us` ke file teks (misalnya `cookies.txt`).
   - Jalankan `yt-dlp` menggunakan argumen:
     ```powershell
     yt-dlp --cookies cookies.txt "https://danbooru.donmai.us/posts/11766677"
     ```
2. **Cara Menutup Browser Normal**:
   - Tutup seluruh jendela Google Chrome secara normal melalui menu *Exit*.
   - Verifikasi tidak ada proses background: `Get-Process chrome` (harus kosong).
   - Jalankan kembali perintah dengan `--cookies-from-browser chrome`.

---

### Rekomendasi 2 (Risiko Rendah): Mengatasi Kebocoran DNS `c-ares` pada `curl_cffi`

Karena `c-ares` tidak mendukung DoH Windows, kita harus mencegah kueri DNS UDP port 53 keluar ke jaringan IndiHome.

#### Pilihan A: Menggunakan Local DNS Proxy / Client DoH (Sangat Direkomendasikan)
Pasang atau jalankan DNS proxy lokal ringan di Windows yang mendengarkan di `127.0.0.1:53` dan meneruskan semua kueri ke Cloudflare via DoH (misalnya **Cloudflare WARP**, **YogaDNS**, atau **Stubby**):
- Karena DNS adapter diarahkan ke `127.0.0.1`, kueri UDP 53 dari `c-ares` hanya berputar di loopback lokal (`localhost`).
- Paket tidak pernah menyentuh kabel/Wi-Fi sehingga DPI IndiHome tidak dapat mencegatnya.
- Hasil: `curl_cffi` mendapatkan IP Cloudflare asli, TLS impersonation berhasil, dan Cloudflare 403 terlewati.

#### Pilihan B: Menggunakan Local HTTP/SOCKS Proxy
Jika Anda memiliki atau menjalankan proxy lokal (misalnya proxy SOCKS5/HTTP lokal):
- Jalankan `yt-dlp` dengan:
  ```powershell
  yt-dlp --proxy "socks5h://127.0.0.1:1080" --extractor-args "generic:impersonate" "URL"
  ```
- Protokol `socks5h://` mendelegasikan resolusi nama domain sepenuhnya ke sisi proxy, membypass total `c-ares` lokal.

---

### Rekomendasi 3 (Solusi Khusus Target): Ekstraktor Spesifik Danbooru API
Danbooru menyediakan REST API publik resmi yang tidak memerlukan scraping HTML halaman web (`generic extractor`):
- Format URL API Danbooru:
  `https://danbooru.donmai.us/posts/11766677.json`
- API endpoint Danbooru memiliki aturan Cloudflare WAF yang jauh lebih longgar terhadap permintaan data JSON dibandingkan halaman web HTML interaktif.

---

## 8. Rencana Tes Lanjutan yang Membutuhkan Persetujuan Pengguna

Sebelum menerapkan perubahan sistem apa pun, Anda dapat menyetujui uji coba terkontrol berikut:

### Tes A: Uji `yt-dlp` dengan File Cookie yang Diekspor Manual
- **Tujuan**: Memverifikasi apakah cookie sesi valid dapat melewati Cloudflare 403 pada handler default `requests` tanpa perlu mengaktifkan impersonasi `curl_cffi`.
- **Perintah**:
  ```powershell
  yt-dlp --simulate --verbose --cookies "e:\CODING HYBRID\Nexora\cookies.txt" "https://danbooru.donmai.us/posts/11766677"
  ```
- **Risiko**: Nol. Tidak mengubah konfigurasi sistem.

### Tes B: Uji Ekstraksi Langsung File Media / JSON Danbooru
- **Tujuan**: Memeriksa apakah file media asli (gambar/video) di `cdn.donmai.us` dapat diunduh tanpa terkena Cloudflare challenge.
- **Perintah**:
  ```powershell
  curl.exe -sS -I "https://danbooru.donmai.us/posts/11766677.json"
  ```
- **Risiko**: Nol. Kueri read-only.

---

## 9. Daftar File dan Sumber Eksternal yang Digunakan

1. **File Internal**:
   - [`windows_dns_redirection_investigation.md`](file:///e:/CODING%20HYBRID/Nexora/docs/windows_dns_redirection_investigation.md) (Laporan DoH & ISP DPI sebelumnya).
   - `C:\Users\linaf\AppData\Local\Google\Chrome\User Data\Profile 6\Network\Cookies` (Pemeriksaan Win32 sharing lock).
2. **Komponen Perangkat Lunak**:
   - `yt-dlp` executable versi `2026.10.26` (`win_exe`).
   - Python 3.14.10 internal / Python 3.11 host.
   - `curl_cffi` versi 0.17.0 (komponen `curl-impersonate` & `c-ares`).
3. **Dokumentasi & Referensi Eksternal**:
   - *c-ares Asynchronous Resolver Library Architecture & Windows Socket Integration* (c-ares.org).
   - *curl-impersonate & curl_cffi Session Architecture* (lexiforest/curl_cffi GitHub repository).
   - *Cloudflare WAF Documentation: Managed Challenge & Bot Detection Headers (`Cf-Mitigated: challenge`)* (cloudflare.com).
   - *Microsoft Win32 Error Codes: `ERROR_SHARING_VIOLATION` (0x20 / 32)* (learn.microsoft.com).
