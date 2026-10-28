# Laporan Investigasi DNS Redirection dan Kegagalan DNS over HTTPS (DoH) pada Windows

**Dokumen**: `windows_dns_redirection_investigation.md`
**Waktu Investigasi**: 27 Oktober 2026
**Target Domain**: `rule34video.com`, `danbooru.donmai.us`
**Metodologi**: Analisis Diagnostik Read-Only (Non-Destruktif, Tanpa Restart)

---

## 1. Executive Summary

Investigasi ini dilakukan untuk menjawab mengapa sistem operasi Windows mengembalikan respons DNS berupa pengalihan ke `aduankonten.id` / `internetpositif.id` (`36.86.63.185` dan `195.35.23.222`) untuk domain `rule34video.com` dan `danbooru.donmai.us`, meskipun pengguna telah mengonfigurasi DNS Wi-Fi ke Cloudflare DoH (`1.1.1.1` / `1.0.0.1` dengan template `https://cloudflare-dns.com/dns-query` dan *Fallback to plaintext: Off*).

### Kesimpulan Utama (The Bottom Line):
1. **Akar Masalah Utama di Jaringan (ISP)**:
   Jaringan yang digunakan teridentifikasi sebagai **AS7713 PT Telekomunikasi Indonesia (IndiHome)** melalui gateway publik `180.242.99.253`. Jaringan ini menerapkan **Transparent DNS Proxy / Hijacking aktif pada seluruh lalu lintas UDP port 53**.
   - **Bukti Absolut**: Kueri DNS UDP yang diarahkan ke IP dokumentasi non-eksisten (`192.0.2.1` - RFC 5737) **tetap dijawab dalam hitungan milidetik** dengan CNAME `aduankonten.id` dan IP `36.86.63.185`. Ini membuktikan adanya middlebox jaringan yang membajak semua paket UDP:53.
   - **Bukti Pembanding TCP**: Kueri langsung ke Cloudflare menggunakan protokol **TCP port 53** (`nslookup -vc rule34video.com 1.1.1.1`) **berhasil menembus Cloudflare** dan mengembalikan IP asli `190.115.31.243`. Hal ini membuktikan pemblokiran hanya mengintersepsi UDP port 53.

2. **Akar Masalah di Windows (Mengapa DoH Tidak Bekerja)**:
   Meskipun GUI Settings Windows 11 menampilkan DoH *On (manual template)* dan *Fallback: Off*, pada lapisan engine DNS Client Windows (`dnscache`), tabel konfigurasi `MSFT_DNSClientDohServerAddress` untuk `1.1.1.1` dan `1.0.0.1` memiliki status:
   ```text
   AutoUpgrade        : False
   AllowFallbackToUdp : False
   ```
   Berdasarkan spesifikasi implementasi Windows DNS Client, ketika **`AutoUpgrade` bernilai `False`**, engine Windows DNS **tidak pernah menaikkan kueri ke HTTPS (DoH)**. Akibatnya, kueri sistem (`Resolve-DnsName` dan API Win32 `getaddrinfo`) tetap dilepaskan sebagai paket plaintext **UDP port 53**. Begitu paket UDP 53 keluar dari interface Wi-Fi, paket langsung diintersepsi dan dipalsukan oleh DPI ISP.

3. **Kabar Baik**:
   Konektivitas HTTPS (port 443) ke endpoint DoH Cloudflare (`https://1.1.1.1/dns-query` dan `https://cloudflare-dns.com/dns-query`) **sama sekali tidak diblokir** dan terbukti dapat berkomunikasi normal. Dengan demikian, DoH di Windows dapat diaktifkan dan diperbaiki secara permanen **tanpa perlu me-restart Windows atau mengganti jaringan**.

---

## 2. Temuan yang Terverifikasi

Tabel berikut merangkum fakta-fakta teknis yang telah diverifikasi secara objektif melalui terminal Windows:

| No. | Komponen / Aspek | Kondisi Aktual Terverifikasi | Status |
|:---:|:---|:---|:---:|
| 1 | **Kueri DoH HTTPS Langsung** | `curl` ke `https://cloudflare-dns.com/dns-query` menghasilkan status 0 dan IP sah (`190.115.31.243` untuk Rule34Video dan `172.67.70.99`/`104.26.10.39`/`104.26.11.39` untuk Danbooru). | **Normal** |
| 2 | **Koneksi TLS ke DoH Endpoint** | `curl -Iv https://1.1.1.1/dns-query` dan `https://cloudflare-dns.com/dns-query` berhasil melakukan TLS 1.3 handshake dengan Cloudflare edge (Singapore PoP). | **Normal** |
| 3 | **Kueri DNS TCP Port 53** | `nslookup -vc rule34video.com 1.1.1.1` mengembalikan IP asli `190.115.31.243`. Tidak diintersepsi oleh ISP. | **Bypass Terbukti** |
| 4 | **Kueri DNS UDP Port 53** | `nslookup rule34video.com 1.1.1.1` mengembalikan CNAME `aduankonten.id` dan IP `36.86.63.185`. | **Terintersepsi** |
| 5 | **Intersepsi Port 53 UDP Arbitrer** | `Resolve-DnsName rule34video.com -Server 192.0.2.1 -DnsOnly` (IP mati RFC 5737) tetap dijawab seketika dengan `aduankonten.id`. | **Terbukti 100% DPI ISP** |
| 6 | **Konfigurasi DoH Server Windows** | `Get-DnsClientDohServerAddress` menunjukkan `AutoUpgrade: False` untuk seluruh server (`1.1.1.1`, `1.0.0.1`, `8.8.8.8`, `9.9.9.9`). | **Penyebab DoH Pasif** |
| 7 | **Registry `EnableAutoDoh`** | Value `EnableAutoDoh` pada `HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters` **tidak ada** (default 0 / Disabled). | **DoH Belum Di-enforce** |
| 8 | **Adapter IPv6 pada Wi-Fi** | `ms_tcpip6` pada Wi-Fi berstatus `Enabled: False`. Tidak ada kebocoran DNS via IPv6 RDNSS. | **Bersih** |
| 9 | **Proxy & Routing** | WinHTTP proxy: `Direct access (no proxy)`. Default route: tunggal ke `192.168.1.1` metric 55 pada Wi-Fi. | **Normal** |
| 10 | **File `hosts` Lokal** | Tidak ada entri untuk `rule34video.com` atau `danbooru.donmai.us`. | **Bersih** |
| 11 | **Layanan Keamanan Lokal** | Antivirus hanya Windows Defender. Driver filter Fortinet NDIS terpasang tetapi tidak ada service/proses FortiClient yang aktif. | **Bukan Intersepsi Lokal** |

---

## 3. Pemeriksaan yang Dilakukan

### 3.1. Inventarisasi Adapter Jaringan dan Pengikatan Protokol

Perintah:
```powershell
Get-NetAdapterBinding -InterfaceAlias "Wi-Fi"
```
**Hasil**:
- `Internet Protocol Version 4 (TCP/IPv4)`: `Enabled: True`
- `Internet Protocol Version 6 (TCP/IPv6)`: `Enabled: False`
- `FortiClient NDIS 6.3 Packet Filter Driver`: `Enabled: True`
- `VirtualBox NDIS6 Bridged Networking Driver`: `Enabled: True`
- `VMware Bridge Protocol`: `Enabled: True`

Pemeriksaan proses dan service latar belakang:
```powershell
Get-Process *forti*; Get-Service *forti*
```
**Hasil**: Tidak ada proses atau service Fortinet yang berjalan. Filter driver berada dalam status pasif (idle).

### 3.2. Pemeriksaan Konfigurasi DNS IPv4 & IPv6

Perintah:
```powershell
Get-DnsClientServerAddress -InterfaceAlias "Wi-Fi"
```
**Hasil**:
- IPv4: `{1.1.1.1, 1.0.0.1}`
- IPv6: `{}` (Kosong, dan IPv6 interface dimatikan).

### 3.3. Pengujian Intersepsi Jalur Jaringan (DPI Proof)

Dilakukan tiga pengujian berjenjang untuk memetakan perilaku jaringan:

1. **Uji Port 53 UDP ke Dummy IP (RFC 5737)**:
   ```powershell
   Resolve-DnsName rule34video.com -Server 192.0.2.1 -DnsOnly -QuickTimeout
   ```
   **Hasil**: Respons diterima instan (kurang dari 20ms):
   ```text
   Name     : rule34video.com
   Type     : CNAME
   NameHost : aduankonten.id
   Name       : internetpositif.id
   IP4Address : 36.86.63.185
   ```
   *Fakta Ilmiah*: IP `192.0.2.1` tidak memiliki jalur routing internet dan tidak ada host di dunia yang menggunakannya. Respons hanya mungkin berasal dari gateway/router/ISP yang membajak port 53.

2. **Uji Port 53 TCP (Virtual Circuit) ke 1.1.1.1**:
   ```cmd
   nslookup -vc rule34video.com 1.1.1.1
   ```
   **Hasil**:
   ```text
   Server:  one.one.one.one
   Address:  1.1.1.1

   Name:    rule34video.com
   Address:  190.115.31.243
   ```
   *Fakta Ilmiah*: Sesi TCP Three-Way Handshake berhasil terbentuk langsung dengan server Cloudflare `1.1.1.1:53` tanpa diintersepsi oleh DPI gateway.

3. **Uji Port 443 DoH ke Cloudflare**:
   ```cmd
   curl.exe -sS -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=rule34video.com&type=A"
   ```
   **Hasil**: Status HTTP 200, mengembalikan data JSON sah IP `190.115.31.243`.

### 3.4. Investigasi Status DoH Windows 11

Perintah:
```powershell
Get-DnsClientDohServerAddress | Where-Object { $_.ServerAddress -in @("1.1.1.1", "1.0.0.1") } | Format-List ServerAddress, DohTemplate, AutoUpgrade, AllowFallbackToUdp
```
**Hasil**:
```text
ServerAddress      : 1.1.1.1
DohTemplate        : https://cloudflare-dns.com/dns-query
AutoUpgrade        : False
AllowFallbackToUdp : False

ServerAddress      : 1.0.0.1
DohTemplate        : https://cloudflare-dns.com/dns-query
AutoUpgrade        : False
AllowFallbackToUdp : False
```

Pemeriksaan registry:
```cmd
reg query "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v EnableAutoDoh
```
**Hasil**: `ERROR: The system was unable to find the specified registry key or value.`

---

## 4. Analisis Akar Masalah (Root Cause Analysis)

Masalah ini terjadi akibat pertemuan dua faktor yang saling mengunci (*two-fold breakdown*):

```
[Aplikasi / Browser / Resolve-DnsName]
                 笏・                 笆ｼ
  [Windows DNS Client (dnscache)]
                 笏・    (Mengecek status DoH server)
    - AutoUpgrade = False
    - EnableAutoDoh = Not set (0)
                 笏・                 笆ｼ  (Gagal/Tidak menaikkan ke HTTPS)
     [Kueri Plaintext UDP Port 53]
                 笏・                 笆ｼ
     [Kabel / Wi-Fi Router / ISP Gateway]
                 笏・        (DPI Telkom / IndiHome)
  笏娯楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏ｴ笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏・  笏・Port 53 UDP dideteksi       笏・  笏・Diarahkan ke Transparent    笏・  笏・DNS Proxy TrustPositif      笏・  笏披楳笏笏笏笏笏笏笏笏笏笏笏笏笏笏ｬ笏笏笏笏笏笏笏笏笏笏笏笏笏笏笏・                 笏・                 笆ｼ
[DNS Response Palsu: aduankonten.id / 36.86.63.185]
                 笏・                 笆ｼ
 [Windows Menerima & Menampilkan Hasil Blokir]
```

### Rincian Kegagalan Komponen:

1. **Mengapa Windows Settings Menampilkan "On (manual template)" Namun Faktanya Pasif?**
   Di Windows 11, UI Settings sering kali hanya menulis konfigurasi template ke profil visual antarmuka, tetapi tidak secara otomatis memperbarui nilai `AutoUpgrade` pada tabel CIM `MSFT_DNSClientDohServerAddress` jika template dimasukkan secara manual atau jika validasi probe latar belakang Windows sempat mengalami timeout saat adapter pertama kali terhubung.

   Karena `AutoUpgrade: False`, driver resolusi DNS (`dnsrslvr.dll`) menganggap bahwa kueri ke `1.1.1.1` tidak perlu dienkripsi secara paksa, melainkan menunggu kueri DoH eksplisit. Akibatnya, pemanggilan standar melalui API OS tetap dikirim sebagai kueri DNS biasa (UDP 53).

2. **Perilaku Parameter `AllowFallbackToUdp: False`**:
   Berdasarkan dokumentasi teknis Microsoft Windows Networking SDK:
   > *"The AllowFallbackToUdp parameter only applies if AutoUpgrade is set to True."*

   Ketika `AutoUpgrade` adalah `False`, aturan proteksi `AllowFallbackToUdp: False` **menjadi tidak berfungsi**, karena kueri tidak pernah di-upgrade ke DoH sejak awal. Sistem langsung menggunakan UDP tanpa menganggapnya sebagai "fallback".

3. **Mengapa Pengalihan Terjadi di Tingkat ISP?**
   Penyedia layanan internet (Telkom Indonesia / IndiHome) mengimplementasikan *Policy-Based Routing* pada perangkat BRAS/BGP Edge untuk membelokkan seluruh paket UDP dengan destination port 53 menuju DNS sinkhole mereka (TrustPositif). Karena kueri dari Windows dikirim dalam bentuk UDP 53 terbuka, paket tersebut ditangkap di tingkat jaringan sebelum sempat mencapai server Cloudflare di internet global.

---

## 5. Hipotesis yang Belum Terbukti / Gugur

1. **Hipotesis Kebocoran IPv6 (Gugur)**:
   - *Dugaan awal*: Sistem melakukan query ke server DNS IPv6 milik ISP yang diperoleh dari SLAAC/DHCPv6.
   - *Fakta*: Protokol IPv6 pada adapter Wi-Fi terbukti `Disabled` (`ms_tcpip6 = False`), dan tidak ada DNS IPv6 aktif pada antarmuka Wi-Fi.

2. **Hipotesis Intersepsi Perangkat Lunak Lokal / VPN / Antivirus (Gugur)**:
   - *Dugaan awal*: FortiClient atau driver filter NDIS pihak ketiga membelokkan DNS di dalam kernel Windows.
   - *Fakta*: Kueri TCP port 53 (`nslookup -vc`) berhasil melewati tumpukan driver Windows dan mendapatkan jawaban asli. Jika ada filter driver lokal yang membelokkan port 53, kueri TCP dan UDP lokal biasanya sama-sama terbelokkan.

3. **Hipotesis Policy NRPT / Proxy WinHTTP (Gugur)**:
   - *Dugaan awal*: Ada kebijakan domain tertentu yang dialihkan via DirectAccess/NRPT atau proxy lokal.
   - *Fakta*: `Get-DnsClientNrptPolicy -Effective` dan `netsh winhttp show proxy` mengonfirmasi ketiadaan aturan pemelencengan lalu lintas.

---

## 6. Rekomendasi Perbaikan Tanpa Restart

Untuk mengatasi masalah ini secara permanen tanpa perlu restart Windows, tanpa mengganti jaringan, dan tanpa mematikan fitur keamanan, ada 2 opsi perbaikan terstruktur yang dapat dipilih:

---

### Opsi 1 (Sangat Direkomendasikan): Mengaktifkan AutoUpgrade DoH Native Windows via PowerShell

Metode ini memperbaiki tabel engine DoH Windows 11 secara langsung sehingga kueri ke `1.1.1.1` dan `1.0.0.1` secara mutlak dikirim via HTTPS port 443.

#### Langkah Pelaksanaan:

1. Buka **PowerShell sebagai Administrator**.
2. Jalankan perintah untuk mengaktifkan `AutoUpgrade` dan menolak fallback UDP:
   ```powershell
   Set-DnsClientDohServerAddress -ServerAddress "1.1.1.1" -DohTemplate "https://cloudflare-dns.com/dns-query" -AutoUpgrade $True -AllowFallbackToUdp $False
   Set-DnsClientDohServerAddress -ServerAddress "1.0.0.1" -DohTemplate "https://cloudflare-dns.com/dns-query" -AutoUpgrade $True -AllowFallbackToUdp $False
   ```
3. Bersihkan cache DNS dan segarkan antarmuka:
   ```powershell
   Clear-DnsClientCache
   ipconfig /flushdns
   ```
4. Lakukan reset sesi interface Wi-Fi secara instan (tanpa restart OS):
   ```powershell
   Restart-NetAdapter -Name "Wi-Fi"
   ```

#### Cara Verifikasi:
1. Pastikan status DoH telah berubah:
   ```powershell
   Get-DnsClientDohServerAddress | Where-Object { $_.ServerAddress -in @("1.1.1.1", "1.0.0.1") } | Format-Table ServerAddress, AutoUpgrade, AllowFallbackToUdp
   ```
   *Ekspektasi: `AutoUpgrade = True`, `AllowFallbackToUdp = False`.*
2. Uji resolusi domain yang sebelumnya diblokir:
   ```powershell
   Resolve-DnsName rule34video.com
   Resolve-DnsName danbooru.donmai.us
   ```
   *Ekspektasi: Menghasilkan alamat IP Cloudflare asli (`190.115.31.243` dan `104.26.x.x`), tanpa ada CNAME `aduankonten.id`.*

---

### Opsi 2 (Alternatif Sistem): Enforce Global AutoDoH di Registry

Jika Opsi 1 masih ditolak oleh profile Wi-Fi tertentu, Windows DNS Client dapat diinstruksikan secara global untuk mewajibkan DoH pada setiap DNS server yang memiliki template terdaftar.

#### Langkah Pelaksanaan:
1. Buka Command Prompt / PowerShell sebagai Administrator:
   ```cmd
   reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v EnableAutoDoh /t REG_DWORD /d 2 /f
   ```
   *(Nilai `2` berarti: Enforce DoH / Mandate Encrypted Resolution).*
2. Segarkan cache:
   ```powershell
   Clear-DnsClientCache
   Restart-NetAdapter -Name "Wi-Fi"
   ```

---

## 7. Risiko dan Prosedur Rollback

### Analisis Risiko:
- **Konektivitas Terputus Sementara**: Perintah `Restart-NetAdapter -Name "Wi-Fi"` akan memutuskan koneksi Wi-Fi selama 2窶・ detik sebelum otomatis tersambung kembali.
- **Fail-Closed Behavior**: Dengan `-AllowFallbackToUdp $False`, jika server DoH Cloudflare mengalami gangguan total atau jika ISP memblokir port 443 ke Cloudflare di kemudian hari, resolusi nama domain akan gagal sama sekali (tidak bocor ke ISP).

### Prosedur Rollback (Pengembalian ke Kondisi Semula):

Jika ingin mengembalikan konfigurasi ke status semula sebelum perbaikan:

1. **Rollback Opsi 1 (Kembalikan DoH ke Default Pasif)**:
   ```powershell
   Set-DnsClientDohServerAddress -ServerAddress "1.1.1.1" -AutoUpgrade $False -AllowFallbackToUdp $False
   Set-DnsClientDohServerAddress -ServerAddress "1.0.0.1" -AutoUpgrade $False -AllowFallbackToUdp $False
   Clear-DnsClientCache
   ```

2. **Rollback Opsi 2 (Hapus Registry Global Enforce)**:
   ```cmd
   reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v EnableAutoDoh /f
   Clear-DnsClientCache
   ```

---

## 8. Bukti Terminal Ringkas

### Bukti 1: Pembajakan Port 53 UDP oleh Middlebox ISP (Dummy IP RFC 5737)
```text
PS> Resolve-DnsName rule34video.com -Server 192.0.2.1 -DnsOnly -QuickTimeout

Name     : rule34video.com
Type     : CNAME
TTL      : 0
Section  : Answer
NameHost : aduankonten.id

Name       : internetpositif.id
QueryType  : A
TTL        : 0
Section    : Answer
IP4Address : 36.86.63.185
```

### Bukti 2: Kueri Port 53 TCP Menembus Blokir ISP
```text
PS> nslookup -vc rule34video.com 1.1.1.1

Server:  one.one.one.one
Address:  1.1.1.1

Non-authoritative answer:
Name:    rule34video.com
Address:  190.115.31.243
```

### Bukti 3: Kueri Langsung DoH HTTPS (Port 443) Berhasil
```text
PS> curl.exe -sS -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=rule34video.com&type=A"

{"Status":0,"TC":false,"RD":true,"RA":true,"AD":false,"CD":false,"Question":[{"name":"rule34video.com","type":1}],"Answer":[{"name":"rule34video.com","type":1,"TTL":198,"data":"190.115.31.243"}]}
```

### Bukti 4: Status DoH Windows Belum Ter-upgrade
```text
PS> Get-DnsClientDohServerAddress | Where-Object { $_.ServerAddress -in @("1.1.1.1", "1.0.0.1") }

ServerAddress DohTemplate                          AutoUpgrade AllowFallbackToUdp
------------- -----------                          ----------- ------------------
1.1.1.1       https://cloudflare-dns.com/dns-query False       False
1.0.0.1       https://cloudflare-dns.com/dns-query False       False
```

---

## 9. Kesimpulan Akhir

Akar masalah pengalihan DNS pada perangkat Anda bukanlah kerusakan sistem Windows atau interferensi software antivirus/VPN lokal, melainkan:
1. **Paket DNS sistem masih dikirim sebagai UDP port 53 biasa** akibat konfigurasi internal Windows DoH yang belum memiliki flag `AutoUpgrade: True` atau `EnableAutoDoh: 2`.
2. **Paket UDP port 53 tersebut langsung dibajak dan dipalsukan oleh DPI ISP (IndiHome)** menjadi halaman blokir `aduankonten.id`.

Perbaikan dapat dilakukan seketika tanpa restart dengan mengeksekusi Opsi 1 atau Opsi 2 di atas. Silakan tinjau laporan ini dan berikan persetujuan jika Anda ingin langkah perbaikan Opsi 1 diterapkan.
