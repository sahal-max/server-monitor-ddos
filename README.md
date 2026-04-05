<div align="center">

<h1>🛡️ Advanced Server Monitor & DDoS Detector</h1>

<p>
  <strong>Script Bash lengkap untuk monitoring server Linux dan deteksi serangan DDoS<br>
  dengan Telegram Bot interaktif, manajemen IP block, dan notifikasi SOC real-time</strong>
</p>

<p>
  <img src="https://img.shields.io/badge/version-3.0.0-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/platform-Linux-orange?style=for-the-badge&logo=linux" alt="Platform">
  <img src="https://img.shields.io/badge/shell-Bash-green?style=for-the-badge&logo=gnubash" alt="Shell">
  <img src="https://img.shields.io/badge/notify-Telegram-26A5E4?style=for-the-badge&logo=telegram" alt="Telegram">
  <img src="https://img.shields.io/badge/license-MIT-yellow?style=for-the-badge" alt="License">
</p>

<br>

<p>
  <a href="#-fitur">Fitur</a> •
  <a href="#-telegram-bot">Telegram Bot</a> •
  <a href="#-instalasi">Instalasi</a> •
  <a href="#-konfigurasi">Konfigurasi</a> •
  <a href="#-perintah">Perintah</a> •
  <a href="#-notifikasi">Notifikasi</a> •
  <a href="#-update--uninstall">Update & Uninstall</a> •
  <a href="#-soc--keamanan">SOC</a>
</p>

</div>

---

## ✨ Fitur

<table>
<tr>
<td width="50%">

### 🤖 Telegram Bot Interaktif
- Menu inline keyboard (tanpa ketik perintah)
- Tambah / hapus IP block langsung dari bot
- Lihat status server real-time
- Laporan SOC on-demand
- Info jaringan & koneksi detail
- Top proses CPU dan RAM

</td>
<td width="50%">

### 🛡️ Monitoring & Deteksi
- Deteksi DDoS berdasarkan threshold Mbps
- Monitoring CPU, RAM, Disk, Koneksi
- Grafik sparkline ASCII tren 20 titik
- Analisis keamanan SOC (brute force, SSH)
- Blokir IP otomatis via `iptables`
- Laporan terjadwal dengan interval konfigurasi

</td>
</tr>
</table>

---

## 🤖 Telegram Bot

Script ini dilengkapi **bot Telegram interaktif** yang berjalan paralel dengan monitoring.

### Tampilan Menu Bot

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🤖 SERVER MONITOR BOT
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰

[ 📊 Status Server ] [ 🌐 Info Jaringan ]
[ 🔒 Kelola IP Block ] [ 🛡 Laporan SOC ]
[ 📋 Top Proses ] [ 🔄 Refresh ]
```

### Menu IP Block

Klik **🔒 Kelola IP Block** untuk masuk ke submenu:

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🔒 KELOLA IP BLOCK
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
Total diblokir: 3 IP

[ 📋 Lihat IP Blocked    ]
[ 🚫 Tambah Block IP ] [ ✅ Hapus Block IP ]
[ 🔙 Kembali              ]
```

**Cara tambah IP:**
1. Klik **🚫 Tambah Block IP**
2. Bot akan meminta input IP address
3. Kirim IP (contoh: `192.168.1.100` atau `10.0.0.0/24`)
4. Bot langsung memblokir dan konfirmasi

**Perintah langsung (tanpa menu):**

| Perintah | Fungsi |
|----------|--------|
| `/start` atau `/menu` | Buka menu utama |
| `/status` | Status server singkat |
| `/block 1.2.3.4` | Blokir IP langsung |
| `/unblock 1.2.3.4` | Hapus blokir IP |
| `/listip` | Daftar semua IP blocked |

---

## 📦 Instalasi

### Prasyarat
- Linux dengan `systemd` (Ubuntu 18+, Debian 9+, CentOS 7+)
- `curl`, `awk`, `ss` / `netstat` tersedia
- Akses `root` / `sudo`
- Bot Telegram aktif (buat via [@BotFather](https://t.me/BotFather))

### Langkah Instalasi

**1. Download script**

```bash
cd /tmp
curl -O https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/monitor-server.sh
curl -O https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh
chmod +x monitor-server.sh install-monitor.sh
```

**2. Konfigurasi Telegram**

Edit bagian konfigurasi di `monitor-server.sh`:

```bash
nano monitor-server.sh
```

```bash
TELEGRAM_TOKEN="ISIKAN_TOKEN_BOT_ANDA"
CHAT_ID="ISIKAN_CHAT_ID_GRUP_ATAU_PRIBADI"
INTERFACE="eth0"          # Sesuaikan interface jaringan
THRESHOLD_MBPS=150        # Batas DDoS dalam Mbps
```

> **Cara dapat Chat ID:** Tambahkan bot ke grup → kirim pesan → buka `https://api.telegram.org/bot<TOKEN>/getUpdates`

**3. Test sebelum install**

```bash
# Test koneksi Telegram + tampilkan menu bot
bash monitor-server.sh test-telegram

# Test baca resource sistem
bash monitor-server.sh test-resources
```

**4. Install sebagai systemd service**

```bash
sudo bash install-monitor.sh
```

Installer otomatis:
- Salin script ke `/usr/local/bin/`
- Buat systemd service
- Setup log rotation
- Aktifkan auto-start saat boot

**5. Verifikasi aktif**

```bash
systemctl status server-monitor
journalctl -u server-monitor -f
```

---

## ⚙️ Konfigurasi

### Parameter Utama

| Parameter | Default | Keterangan |
|-----------|---------|------------|
| `TELEGRAM_TOKEN` | *(wajib diisi)* | Token bot dari @BotFather |
| `CHAT_ID` | *(wajib diisi)* | ID chat/grup tujuan notifikasi |
| `INTERFACE` | `ens3` | Interface jaringan aktif (`ip link show`) |
| `THRESHOLD_MBPS` | `150` | Batas trafik DDoS (Mbps) |
| `THRESHOLD_CPU` | `85` | Batas alert CPU (%) |
| `THRESHOLD_RAM` | `90` | Batas alert RAM (%) |
| `THRESHOLD_DISK` | `90` | Batas alert Disk (%) |
| `THRESHOLD_CONN` | `5000` | Batas jumlah koneksi aktif |
| `THRESHOLD_FAILED_LOGIN` | `20` | Batas login gagal untuk SOC alert |

### Interval Notifikasi

| Parameter | Default | Keterangan |
|-----------|---------|------------|
| `NOTIFY_INTERVAL_DDOS` | `10` detik | Jeda minimal antara notif DDoS |
| `NOTIFY_INTERVAL_NORMAL` | `1800` detik | Laporan status rutin (30 menit) |
| `NOTIFY_INTERVAL_ALERT` | `300` detik | Alert CPU/RAM/Disk/Koneksi (5 menit) |
| `NOTIFY_INTERVAL_SOC` | `600` detik | Laporan keamanan SOC (10 menit) |

---

## 🖥️ Perintah

### Service Management

```bash
systemctl start server-monitor      # Mulai
systemctl stop server-monitor       # Hentikan
systemctl restart server-monitor    # Restart
systemctl status server-monitor     # Status
```

### IP Block via CLI

```bash
# Blokir IP
/usr/local/bin/monitor-server.sh block 1.2.3.4

# Hapus blokir
/usr/local/bin/monitor-server.sh unblock 1.2.3.4

# Lihat daftar blocked
/usr/local/bin/monitor-server.sh listip
```

### Diagnostik

```bash
# Cek proses berjalan
/usr/local/bin/monitor-server.sh status

# Test resource monitoring
/usr/local/bin/monitor-server.sh test-resources

# Test laporan SOC
/usr/local/bin/monitor-server.sh test-soc

# Lihat log real-time
tail -f /var/log/server-monitor.log
```

---

## 📬 Notifikasi

### 🚨 Alert DDoS

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🚨 SERANGAN DDoS TERDETEKSI!
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🖥 Server  : server.example.com
📅 Waktu   : 05/04/2026 14:22:31

📶 Trafik Masuk
├ Rata-rata : 287.44 Mbps
├ Sekarang  : 312.80 Mbps ↑  4.20 Mbps ↓
└ Koneksi   : 8,421 aktif

📈 Tren 20 detik:
▃▅▆▇█████████████████

⚡ Batas aman : 150 Mbps
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
⚠️ Segera blokir IP penyerang!
```

### 📊 Status Normal (setiap 30 menit)

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
📊 LAPORAN STATUS SERVER
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🖥 Server  : server.example.com
📅 Waktu   : 05/04/2026 14:00:00
⏱ Uptime  : up 12 days, 3 hours

🟢 Jaringan
   ↑ RX : 2.45 Mbps (avg)  ↓ TX : 0.80 Mbps
   ▁▁▂▁▁▂▁▃▂▁▁▂▁▁▁▂▁▁▂▁

🟢 CPU — 12.4%
   ██░░░░░░░░░░░░ Load: 0.32
   ▁▁▂▁▁▂▃▂▁▁▁▂▁▁▃▂▁▁▂▁

🟢 RAM — 38.2% (1,528/4,096 MB)
   ██████░░░░░░░░ Swap: 0/2,048 MB
   ▃▃▄▃▃▄▃▃▄▃▄▃▃▄▃▃▄▃▃▄

🟢 Disk — 42% (42G/100G, sisa 58G)
🟢 Koneksi — 124 aktif
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
✅ Semua dalam batas normal
```

### ⚠️ Alert Resource

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
⚠️ ALERT: CPU TINGGI
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🖥 Server : server.example.com
📅 Waktu  : 05/04/2026 14:10:00
📊 Nilai  : 91.2%
🔴 Batas  : 85%

💻 Top CPU:
  root      91.2%  /usr/bin/python3
  www-data  4.5%   /usr/sbin/nginx
  mysql     2.1%   /usr/sbin/mysqld
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
```

---

## 🛡 SOC & Keamanan

Script secara otomatis menganalisis log sistem dan mengirim laporan keamanan setiap 10 menit:

```
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🛡 LAPORAN KEAMANAN SOC
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
🖥 Server : server.example.com
📅 Waktu  : 05/04/2026 14:00:00
🚦 Ancaman: 🔴 TINGGI

🔐 Login Gagal (5 mnt): 47

📍 Top IP Penyerang:
  47    192.168.1.105
  23    10.20.30.41
  11    172.16.0.8

🚫 Brute Force (≥10x):
  47    192.168.1.105

👤 SSH Aktif:
  admin (192.168.1.1)

🔒 IP Diblokir: 3
▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰
```

---

## 🔄 Update & Uninstall

### Update Otomatis

```bash
curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/monitor-server.sh \
    -o /usr/local/bin/monitor-server.sh && \
systemctl restart server-monitor && \
echo "✅ Update berhasil!"
```

### Update Manual

```bash
cd /tmp
curl -O https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/monitor-server.sh
# Edit ulang konfigurasi (token, chat_id, interface)
nano monitor-server.sh
sudo cp monitor-server.sh /usr/local/bin/
sudo systemctl restart server-monitor
```

### Uninstall

**Otomatis:**

```bash
sudo bash /tmp/install-monitor.sh uninstall
```

**Manual:**

```bash
systemctl stop server-monitor
systemctl disable server-monitor
rm -f /etc/systemd/system/server-monitor.service
rm -f /usr/local/bin/monitor-server.sh
rm -f /etc/logrotate.d/server-monitor
systemctl daemon-reload
echo "✅ Uninstall selesai"
```

> ⚠️ Data di `/var/log/server-monitor.log`, `/var/log/soc-reports/`, dan `/var/log/server-monitor-blocked-ips.txt` tidak ikut terhapus.

---

## 📁 Struktur File

**Repositori GitHub:**
```
server-monitor-ddos/          ← https://github.com/sahal-max/server-monitor-ddos
├── monitor-server.sh          # Script utama (monitor + bot)
├── install-monitor.sh         # Installer / uninstaller
└── README.md                  # Dokumentasi ini
```

**Setelah install di server:**
```
/usr/local/bin/monitor-server.sh            # Script (installed)
/etc/systemd/system/server-monitor.service  # Service systemd
/etc/logrotate.d/server-monitor             # Log rotation
/var/log/server-monitor.log                 # Log monitoring
/var/log/server-monitor-blocked-ips.txt     # Daftar IP blocked
/var/log/soc-reports/                       # Laporan SOC
```

---

## 🔧 Troubleshooting

<details>
<summary><b>Bot tidak merespons perintah Telegram</b></summary>

```bash
# Cek apakah monitoring berjalan
systemctl status server-monitor

# Cek log untuk error bot
grep "Bot listener" /var/log/server-monitor.log
grep "ERROR" /var/log/server-monitor.log

# Test koneksi ke API Telegram
curl -s "https://api.telegram.org/bot<TOKEN>/getMe"
```

Pastikan Token dan Chat ID sudah benar, dan server punya akses internet ke `api.telegram.org`.
</details>

<details>
<summary><b>IP block tidak efektif (iptables tidak tersedia)</b></summary>

```bash
# Cek ketersediaan iptables
which iptables

# Install iptables
apt-get install iptables -y   # Debian/Ubuntu
yum install iptables -y       # CentOS/RHEL

# Cek rules yang aktif
iptables -L INPUT -n --line-numbers
```

Jika `iptables` tidak tersedia, IP tetap dicatat di `/var/log/server-monitor-blocked-ips.txt` namun tidak diblokir di kernel.
</details>

<details>
<summary><b>Interface jaringan tidak terdeteksi</b></summary>

```bash
# Cek nama interface aktif
ip route | grep default
ip link show

# Contoh output: eth0, ens3, ens18, enp0s3
# Edit INTERFACE di monitor-server.sh sesuai nama yang muncul
```
</details>

<details>
<summary><b>Tidak ada data di log SOC (failed login)</b></summary>

```bash
# Cek keberadaan auth log
ls -la /var/log/auth.log        # Debian/Ubuntu
ls -la /var/log/secure          # CentOS/RHEL

# Test SOC secara manual
/usr/local/bin/monitor-server.sh test-soc
```
</details>

---

## 📋 Persyaratan Sistem

| Komponen | Minimum |
|----------|---------|
| OS | Linux dengan systemd (Ubuntu 18+, Debian 9+, CentOS 7+) |
| Bash | 4.0+ |
| RAM | 32 MB |
| Disk | 100 MB (untuk log) |
| Akses | root / sudo |
| Internet | Ya (notifikasi Telegram) |

**Dependencies** (diinstal otomatis oleh installer):

- `curl` — Telegram API & download
- `awk` — Parsing data sistem
- `ss` / `netstat` — Monitor koneksi
- `iptables` — IP blocking *(opsional)*
- `ps` — Monitor proses

---

## 📄 Lisensi

Script ini dirilis di bawah lisensi **MIT**. Bebas digunakan, dimodifikasi, dan didistribusikan.

---

<div align="center">

**Dibuat untuk administrator sistem dan tim SOC**

⭐ Jika script ini membantu, berikan bintang di GitHub!

</div>
