<div align="center">

<h1>🛡️ Advanced Server Monitor & DDoS Detector</h1>

<p>
  <strong>Script Bash lengkap untuk monitoring server Linux dan deteksi serangan DDoS<br>dengan notifikasi Telegram real-time dan analisis keamanan SOC</strong>
</p>

<p>
  <img src="https://img.shields.io/badge/version-2.0.0-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/platform-Linux-orange?style=for-the-badge&logo=linux" alt="Platform">
  <img src="https://img.shields.io/badge/shell-Bash-green?style=for-the-badge&logo=gnubash" alt="Shell">
  <img src="https://img.shields.io/badge/notify-Telegram-26A5E4?style=for-the-badge&logo=telegram" alt="Telegram">
  <img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License">
</p>

<br>

<p>
  <a href="#-fitur">Fitur</a> •
  <a href="#-instalasi">Instalasi</a> •
  <a href="#-konfigurasi">Konfigurasi</a> •
  <a href="#-perintah">Perintah</a> •
  <a href="#-update">Update</a> •
  <a href="#-uninstall">Uninstall</a> •
  <a href="#-notifikasi-telegram">Notifikasi</a> •
  <a href="#-soc--analisis-keamanan">SOC</a>
</p>

</div>

---

## 📋 Deskripsi

Script ini adalah solusi monitoring server all-in-one yang dirancang untuk administrator sistem dan tim SOC *(Security Operations Center)*. Script berjalan sebagai **systemd service** di background dan secara otomatis:

- Memantau trafik jaringan dan mendeteksi serangan DDoS
- Memonitor penggunaan CPU, RAM, dan disk secara real-time
- Menganalisis log keamanan dan mencari aktivitas mencurigakan
- Mengirimkan notifikasi ke **Telegram** dengan format yang informatif dan mudah dibaca

---

## ✨ Fitur

<table>
<tr>
<td width="50%">

**🌐 Monitoring Jaringan**
- Pengukuran RX/TX Mbps secara real-time
- Rata-rata bergerak dari 10 sampel terakhir
- Deteksi otomatis serangan DDoS
- Notifikasi langsung saat threshold terlampaui

**💻 Monitoring CPU**
- Persentase penggunaan CPU real-time
- Load average (1m, 5m, 15m)
- Top 5 proses berdasarkan CPU
- Grafik tren sparkline ASCII

**🧠 Monitoring RAM**
- Penggunaan RAM dalam MB dan persen
- Monitoring Swap memory
- Top 5 proses berdasarkan RAM
- Grafik tren sparkline ASCII

</td>
<td width="50%">

**💿 Monitoring Disk**
- Persentase penggunaan disk `/`
- Alert saat disk hampir penuh
- Tampil ukuran used/available/total
- Daftar direktori terbesar

**🔗 Monitoring Koneksi**
- Total koneksi aktif (ESTABLISHED)
- Breakdown by state (SYN, TIME_WAIT, dll)
- Top 5 IP berdasarkan jumlah koneksi
- Top 5 port aktif

**🛡️ SOC & Analisis Keamanan**
- Deteksi failed login SSH
- Identifikasi IP brute force (≥10 percobaan)
- Monitor sesi SSH aktif
- Tracking penggunaan sudo
- Deteksi port scan
- Laporan SOC otomatis tersimpan ke file

</td>
</tr>
</table>

**📊 Visualisasi**
- Grafik sparkline: `▁▂▃▄▅▆▇█` untuk tren CPU, RAM, Network
- Bar chart: `████████░░░░` untuk utilization saat ini
- Notifikasi Telegram dengan format HTML yang rapi

---

## 🚀 Instalasi

<a id="-instalasi"></a>

### Prasyarat

- Linux dengan systemd (Ubuntu 18+, Debian 9+, CentOS 7+)
- Akses `root` atau `sudo`
- Koneksi internet (untuk notifikasi Telegram)
- Telegram Bot Token dan Chat ID

### Langkah 1 — Download Script

```bash
# Clone repositori
git clone https://github.com/YOUR_USERNAME/server-monitor-ddos.git
cd server-monitor-ddos
```

*atau download langsung:*

```bash
# Download kedua file sekaligus
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/server-monitor-ddos/main/monitor-server.sh
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/server-monitor-ddos/main/install-monitor.sh
```

### Langkah 2 — Konfigurasi Telegram Bot

Sebelum install, edit bagian konfigurasi di `monitor-server.sh`:

```bash
nano monitor-server.sh
```

Cari dan ubah bagian berikut:

```bash
TELEGRAM_TOKEN="ISI_TOKEN_BOT_TELEGRAM_ANDA"
CHAT_ID="ISI_CHAT_ID_ANDA"
INTERFACE="ens3"   # Ganti dengan interface jaringan server Anda
```

> **Cara mendapatkan Token Bot:** Buka [@BotFather](https://t.me/BotFather) di Telegram → `/newbot` → ikuti instruksi
>
> **Cara mendapatkan Chat ID:** Buka [@userinfobot](https://t.me/userinfobot) → kirim pesan → catat ID-nya

### Langkah 3 — Test Konfigurasi

```bash
# Pastikan script bisa dieksekusi
chmod +x monitor-server.sh install-monitor.sh

# Test notifikasi Telegram
bash monitor-server.sh test-telegram

# Test monitoring resource
bash monitor-server.sh test-resources

# Test analisis keamanan SOC
bash monitor-server.sh test-soc
```

### Langkah 4 — Install sebagai Service

```bash
# Jalankan installer (membutuhkan root)
sudo bash install-monitor.sh
```

Installer akan secara otomatis:
1. ✅ Memeriksa dan menginstal dependencies yang dibutuhkan
2. ✅ Menyalin script ke `/usr/local/bin/monitor-server.sh`
3. ✅ Mendeteksi interface jaringan aktif
4. ✅ Membuat file systemd service di `/etc/systemd/system/`
5. ✅ Mengatur log rotation otomatis
6. ✅ Mengaktifkan dan menjalankan service

### Langkah 5 — Verifikasi Instalasi

```bash
# Cek status service
systemctl status server-monitor

# Lihat log real-time
tail -f /var/log/server-monitor.log

# Cek service berjalan
bash /usr/local/bin/monitor-server.sh status
```

**Output yang diharapkan:**

```
● server-monitor.service - Advanced Server Monitor & DDoS Detector with SOC Analysis
     Loaded: loaded (/etc/systemd/system/server-monitor.service; enabled)
     Active: active (running) since ...
```

---

## ⚙️ Konfigurasi

<a id="-konfigurasi"></a>

Edit file `/usr/local/bin/monitor-server.sh` untuk mengubah konfigurasi:

```bash
sudo nano /usr/local/bin/monitor-server.sh
```

### Parameter Utama

<table>
<thead>
<tr>
<th>Parameter</th>
<th>Default</th>
<th>Deskripsi</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>THRESHOLD_MBPS</code></td>
<td><code>150</code></td>
<td>Ambang batas RX dalam Mbps untuk trigger alert DDoS</td>
</tr>
<tr>
<td><code>THRESHOLD_CPU</code></td>
<td><code>85</code></td>
<td>Persentase CPU yang memicu notifikasi alert</td>
</tr>
<tr>
<td><code>THRESHOLD_RAM</code></td>
<td><code>90</code></td>
<td>Persentase RAM yang memicu notifikasi alert</td>
</tr>
<tr>
<td><code>THRESHOLD_DISK</code></td>
<td><code>90</code></td>
<td>Persentase disk yang memicu notifikasi alert</td>
</tr>
<tr>
<td><code>THRESHOLD_CONN</code></td>
<td><code>5000</code></td>
<td>Jumlah koneksi aktif yang memicu notifikasi alert</td>
</tr>
<tr>
<td><code>THRESHOLD_FAILED_LOGIN</code></td>
<td><code>20</code></td>
<td>Jumlah failed login per 5 menit untuk SOC alert</td>
</tr>
<tr>
<td><code>INTERFACE</code></td>
<td><code>ens3</code></td>
<td>Interface jaringan yang dimonitor (eth0, ens3, ens18, dll)</td>
</tr>
<tr>
<td><code>TELEGRAM_TOKEN</code></td>
<td><em>isi sendiri</em></td>
<td>Token bot Telegram dari @BotFather</td>
</tr>
<tr>
<td><code>CHAT_ID</code></td>
<td><em>isi sendiri</em></td>
<td>Chat ID tujuan notifikasi Telegram</td>
</tr>
</tbody>
</table>

### Interval Notifikasi

<table>
<thead>
<tr>
<th>Parameter</th>
<th>Default</th>
<th>Keterangan</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>NOTIFY_INTERVAL_DDOS</code></td>
<td><code>10</code> detik</td>
<td>Jeda minimum antar notifikasi DDoS</td>
</tr>
<tr>
<td><code>NOTIFY_INTERVAL_NORMAL</code></td>
<td><code>1800</code> detik (30 menit)</td>
<td>Laporan status normal berkala</td>
</tr>
<tr>
<td><code>NOTIFY_INTERVAL_ALERT</code></td>
<td><code>300</code> detik (5 menit)</td>
<td>Jeda minimum antar alert CPU/RAM/Disk</td>
</tr>
<tr>
<td><code>NOTIFY_INTERVAL_SOC</code></td>
<td><code>600</code> detik (10 menit)</td>
<td>Laporan SOC credential analysis berkala</td>
</tr>
</tbody>
</table>

Setelah mengubah konfigurasi, restart service:

```bash
sudo systemctl restart server-monitor
```

---

## 📟 Perintah

<a id="-perintah"></a>

### Kontrol Service

```bash
# Mulai service
sudo systemctl start server-monitor

# Hentikan service
sudo systemctl stop server-monitor

# Restart service
sudo systemctl restart server-monitor

# Cek status service
sudo systemctl status server-monitor

# Aktifkan otomatis saat boot
sudo systemctl enable server-monitor

# Nonaktifkan otomatis saat boot
sudo systemctl disable server-monitor
```

### Perintah Test

```bash
# Test kirim notifikasi ke Telegram
bash /usr/local/bin/monitor-server.sh test-telegram

# Test monitoring CPU, RAM, Disk, Koneksi
bash /usr/local/bin/monitor-server.sh test-resources

# Test analisis log keamanan SOC
bash /usr/local/bin/monitor-server.sh test-soc

# Test monitoring jaringan
bash /usr/local/bin/monitor-server.sh test-network

# Test grafik ASCII sparkline
bash /usr/local/bin/monitor-server.sh test-graphs

# Cek apakah monitor sedang berjalan
bash /usr/local/bin/monitor-server.sh status
```

### Melihat Log

```bash
# Log utama real-time
tail -f /var/log/server-monitor.log

# Log systemd
journalctl -u server-monitor -f

# Log systemd 100 baris terakhir
journalctl -u server-monitor -n 100

# Laporan SOC terbaru
ls -lt /var/log/soc-reports/ | head -5
cat /var/log/soc-reports/soc_*.txt | tail -50
```

---

## 🔄 Update

<a id="-update"></a>

### Update Otomatis (dari GitHub)

```bash
# Download versi terbaru
cd /tmp
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/server-monitor-ddos/main/monitor-server.sh
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/server-monitor-ddos/main/install-monitor.sh

# Backup konfigurasi lama
sudo cp /usr/local/bin/monitor-server.sh /usr/local/bin/monitor-server.sh.bak

# Stop service
sudo systemctl stop server-monitor

# Salin script baru
sudo cp monitor-server.sh /usr/local/bin/monitor-server.sh
sudo chmod +x /usr/local/bin/monitor-server.sh

# Terapkan kembali konfigurasi lama (edit token & interface)
sudo nano /usr/local/bin/monitor-server.sh

# Restart service
sudo systemctl restart server-monitor

# Verifikasi
sudo systemctl status server-monitor
```

### Update Manual

```bash
# 1. Stop service terlebih dahulu
sudo systemctl stop server-monitor

# 2. Edit script dengan konfigurasi yang diinginkan
sudo nano /usr/local/bin/monitor-server.sh

# 3. Restart service
sudo systemctl restart server-monitor

# 4. Cek apakah berjalan dengan baik
tail -f /var/log/server-monitor.log
```

---

## 🗑️ Uninstall

<a id="-uninstall"></a>

### Uninstall Otomatis

```bash
# Gunakan script installer dengan perintah uninstall
sudo bash install-monitor.sh uninstall
```

Perintah ini akan:
- ✅ Menghentikan service yang sedang berjalan
- ✅ Menonaktifkan auto-start saat boot
- ✅ Menghapus file service dari systemd
- ✅ Menghapus script dari `/usr/local/bin/`
- ✅ Menghapus konfigurasi log rotation

### Uninstall Manual

```bash
# 1. Hentikan dan nonaktifkan service
sudo systemctl stop server-monitor
sudo systemctl disable server-monitor

# 2. Hapus file service systemd
sudo rm -f /etc/systemd/system/server-monitor.service

# 3. Reload systemd daemon
sudo systemctl daemon-reload

# 4. Hapus script
sudo rm -f /usr/local/bin/monitor-server.sh

# 5. Hapus log rotation (opsional)
sudo rm -f /etc/logrotate.d/server-monitor

# 6. Hapus log dan laporan SOC (opsional - DATA AKAN TERHAPUS)
sudo rm -f /var/log/server-monitor.log
sudo rm -rf /var/log/soc-reports/
```

> ⚠️ **Perhatian:** Langkah 6 akan menghapus semua log dan laporan SOC secara permanen. Backup dulu jika diperlukan.

---

## 📨 Notifikasi Telegram

<a id="-notifikasi-telegram"></a>

Script mengirimkan berbagai jenis notifikasi ke Telegram:

### 🚨 Alert DDoS

Dikirim **setiap 10 detik** saat trafik melebihi threshold:

```
━━━━━━━━━━━━━━━━━━━━━━━━━
🚨 DDOS ATTACK DETECTED
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 Domain : server.example.com
🕐 Waktu  : 2026-04-05 14:30:00

📊 Trafik Jaringan
├ ⬇ RX Avg : 185.42 Mb/s
├ ⬇ RX Now : 191.20 Mb/s
├ ⬆ TX Now : 12.50 Mb/s
└ 🔗 Koneksi: 8423

📈 Tren (20s): ▁▂▄▆▇███████████████
⚡ Ambang  : 150 Mb/s

━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ Tindakan yang disarankan:
• Periksa dan blokir IP penyerang
• Aktifkan rate limiting di firewall
• Hubungi provider upstream
━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 📡 Laporan Status Normal

Dikirim **setiap 30 menit** saat trafik normal:

```
━━━━━━━━━━━━━━━━━━━━━━━━━
📡 SERVER STATUS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 Domain : server.example.com
🕐 Waktu  : 2026-04-05 14:00:00
⏱ Uptime : up 15 days, 4 hours

━━━ 🌐 JARINGAN ━━━━━━━━━
🟢 RX avg : 2.45 Mb/s  TX: 1.20 Mb/s
📈 Tren : ▁▁▂▁▂▁▁▂▃▂▁▂▁▁▂▁▂▂▁▁

━━━ 💻 CPU ━━━━━━━━━━━━━━
🟢 Pakai : 12.5%  Load: 0.85 0.72 0.68
████░░░░░░░░░░░░░░░░ 12.5%
📈 Tren: ▂▁▂▃▂▁▁▂▁▂▁▁▂▃▂▁▁▂▁▁

━━━ 🧠 RAM ━━━━━━━━━━━━━━
🟢 Pakai : 45.2%  (2905/6430 MB)
█████████░░░░░░░░░░░ 45.2%
🔄 Swap: 0/0 MB
📈 Tren: ▄▄▄▄▅▄▄▄▄▄▄▄▄▄▄▅▅▄▄▄

━━━ 💿 DISK ━━━━━━━━━━━━━
🟢 Pakai : 38%  (76G/200G, sisa 124G)
███████░░░░░░░░░░░░░ 38%

━━━ 🔗 KONEKSI ━━━━━━━━━━
🟢 Aktif : 142
━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Status: NORMAL
━━━━━━━━━━━━━━━━━━━━━━━━━
```

### ⚠️ Alert Resource (CPU / RAM / Disk)

Dikirim saat threshold terlampaui:

```
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ ALERT: CPU TINGGI
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 Domain     : server.example.com
🕐 Waktu      : 2026-04-05 15:20:00
📊 Nilai      : 92.3%
⚡ Threshold  : 85%

💻 Top Proses CPU:
USER      CPU%    COMMAND
www-data  45.2%   php-fpm: pool www
mysql     28.1%   /usr/sbin/mysqld
root      12.4%   /usr/bin/python3
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ Segera periksa server!
━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🛡️ SOC & Analisis Keamanan

<a id="-soc--analisis-keamanan"></a>

Script secara otomatis menganalisis log keamanan server dan mengirimkan laporan SOC **setiap 10 menit**:

### Notifikasi SOC Telegram

```
━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ SOC CREDENTIAL REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 Domain: server.example.com
🕐 Waktu: 2026-04-05 14:40:00
🚦 Level Ancaman: 🔴 TINGGI

🔐 LOGIN GAGAL (5 menit):
  Jumlah: 47

📍 TOP IP PENYERANG:
   23    192.168.1.100
   18    10.0.0.55
   6     203.0.113.42

🚫 BRUTE FORCE (≥10 attempt):
   23    192.168.1.100 (23 percobaan)
   18    10.0.0.55 (18 percobaan)

👥 SESI SSH AKTIF:
  admin    (192.168.1.1)
  deploy   (10.0.0.10)

🔍 PORT SCAN TERDETEKSI: 3
━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Laporan SOC File

Laporan detail tersimpan otomatis di `/var/log/soc-reports/`:

```bash
# Lihat laporan terbaru
ls -lt /var/log/soc-reports/

# Contoh nama file:
# soc_2026-04-05_14-40-00.txt
# soc_2026-04-05_14-30-00.txt
# ...
```

---

## 📁 Struktur File

```
server-monitor-ddos/
├── monitor-server.sh      # Script monitoring utama
├── install-monitor.sh     # Script installer / uninstaller
└── README.md              # Dokumentasi ini

Setelah install, file tersimpan di:
├── /usr/local/bin/monitor-server.sh         # Script (installed)
├── /etc/systemd/system/server-monitor.service  # Service file
├── /etc/logrotate.d/server-monitor             # Log rotation
├── /var/log/server-monitor.log                 # Log utama
└── /var/log/soc-reports/                       # Laporan SOC
```

---

## 🔧 Troubleshooting

<details>
<summary><strong>Service gagal start</strong></summary>

```bash
# Lihat error detail
journalctl -u server-monitor -n 50 --no-pager

# Periksa apakah script ada dan executable
ls -la /usr/local/bin/monitor-server.sh

# Periksa konfigurasi service
cat /etc/systemd/system/server-monitor.service
```
</details>

<details>
<summary><strong>Notifikasi Telegram tidak terkirim</strong></summary>

```bash
# Test koneksi dan konfigurasi
bash /usr/local/bin/monitor-server.sh test-telegram

# Cek token dan chat ID di script
grep -E "TELEGRAM_TOKEN|CHAT_ID" /usr/local/bin/monitor-server.sh

# Test manual curl
curl -s "https://api.telegram.org/botTOKEN_ANDA/getMe"
```
</details>

<details>
<summary><strong>Interface jaringan tidak terdeteksi</strong></summary>

```bash
# Lihat interface yang tersedia
ip link show
# atau
ifconfig

# Edit interface di script
sudo nano /usr/local/bin/monitor-server.sh
# Ubah: INTERFACE="ens3" → sesuai interface Anda

# Restart service
sudo systemctl restart server-monitor
```
</details>

<details>
<summary><strong>Log tidak muncul</strong></summary>

```bash
# Periksa permission folder log
ls -la /var/log/server-monitor.log

# Buat file log jika belum ada
sudo touch /var/log/server-monitor.log
sudo chmod 644 /var/log/server-monitor.log

# Restart service
sudo systemctl restart server-monitor
```
</details>

---

## 📋 Persyaratan Sistem

| Komponen | Minimum |
|----------|---------|
| OS | Linux dengan systemd (Ubuntu 18+, Debian 9+, CentOS 7+) |
| Bash | 4.0+ |
| RAM | 32 MB (untuk script) |
| Disk | 100 MB (untuk log) |
| Akses | root / sudo |
| Internet | Ya (untuk notifikasi Telegram) |

### Dependencies

Diinstal otomatis oleh installer jika belum ada:

- `curl` — Kirim notifikasi ke Telegram API
- `awk` — Parsing data sistem
- `ss` / `netstat` — Monitor koneksi jaringan
- `ps` — Monitor proses
- `jq` *(opsional)* — Format JSON

---

## 📄 Lisensi

Script ini dirilis di bawah lisensi **MIT**. Bebas digunakan, dimodifikasi, dan didistribusikan dengan tetap mencantumkan atribusi.

---

<div align="center">

**Dibuat untuk administrator sistem dan tim SOC**

⭐ Jika script ini membantu, berikan bintang di GitHub!

</div>
