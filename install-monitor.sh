#!/bin/bash
# =============================================================================
# INSTALLER — Server Monitor & DDoS Detector v3.0
#
# PENGGUNAAN:
#   Install baru:
#     bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) \
#       --token "TOKEN_BOT" --chatid "CHAT_ID"
#
#   Update script:
#     bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) --update
#
#   Uninstall:
#     bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) --uninstall
# =============================================================================

set -e

SCRIPT_NAME="server-monitor"
INSTALL_PATH="/usr/local/bin/monitor-server.sh"
SERVICE_FILE="/etc/systemd/system/${SCRIPT_NAME}.service"
REPORT_DIR="/var/log/soc-reports"
BLOCKED_IPS="/var/log/server-monitor-blocked-ips.txt"
RAW_URL="https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/monitor-server.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Parse argumen
# =============================================================================
TOKEN=""
CHAT_ID=""
IFACE=""
MODE="install"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)    TOKEN="$2";   shift 2 ;;
        --chatid)   CHAT_ID="$2"; shift 2 ;;
        --iface)    IFACE="$2";   shift 2 ;;
        --update)   MODE="update";    shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        -h|--help)  MODE="help";      shift ;;
        *) echo -e "${RED}[!]${NC} Argumen tidak dikenal: $1"; exit 1 ;;
    esac
done

# =============================================================================
# Utilitas
# =============================================================================

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${BLUE}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║   SERVER MONITOR & DDoS DETECTOR — INSTALLER v3.0   ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        err "Script ini harus dijalankan sebagai root"
        echo "   Gunakan: sudo bash atau jalankan sebagai root"
        exit 1
    fi
}

check_deps() {
    info "Memeriksa dependencies..."
    local missing=()
    for cmd in curl awk ss ps; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        warn "Dependency hilang: ${missing[*]} — menginstal..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq curl iproute2 procps gawk
        elif command -v yum &>/dev/null; then
            yum install -y -q curl iproute procps gawk
        elif command -v dnf &>/dev/null; then
            dnf install -y -q curl iproute procps gawk
        else
            err "Package manager tidak ditemukan. Install manual: ${missing[*]}"
            exit 1
        fi
    fi
    ok "Semua dependencies tersedia"
}

# =============================================================================
# Download script utama dari GitHub
# =============================================================================
download_monitor() {
    info "Mendownload monitor-server.sh dari GitHub..."
    if ! curl -fsSL "$RAW_URL" -o "$INSTALL_PATH"; then
        err "Gagal download dari GitHub. Cek koneksi internet."
        exit 1
    fi
    chmod +x "$INSTALL_PATH"
    ok "Download berhasil: $INSTALL_PATH"
}

# =============================================================================
# Konfigurasi token, chatid, interface
# =============================================================================
apply_config() {
    # Token
    if [ -n "$TOKEN" ]; then
        sed -i "s|^TELEGRAM_TOKEN=.*|TELEGRAM_TOKEN=\"${TOKEN}\"|" "$INSTALL_PATH"
        ok "Telegram token dikonfigurasi"
    else
        warn "Token tidak diberikan — edit manual: nano $INSTALL_PATH"
    fi

    # Chat ID
    if [ -n "$CHAT_ID" ]; then
        sed -i "s|^CHAT_ID=.*|CHAT_ID=\"${CHAT_ID}\"|" "$INSTALL_PATH"
        ok "Chat ID dikonfigurasi"
    else
        warn "Chat ID tidak diberikan — edit manual: nano $INSTALL_PATH"
    fi

    # Interface — auto-detect jika tidak disediakan
    local iface="$IFACE"
    if [ -z "$iface" ]; then
        iface=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
    fi
    if [ -n "$iface" ]; then
        sed -i "s|^INTERFACE=.*|INTERFACE=\"${iface}\"|" "$INSTALL_PATH"
        ok "Interface jaringan: $iface"
    else
        warn "Interface tidak terdeteksi — edit manual: nano $INSTALL_PATH"
    fi
}

# =============================================================================
# Buat systemd service
# =============================================================================
create_service() {
    info "Membuat systemd service..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Server Monitor & DDoS Detector v3.0
After=network.target network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${INSTALL_PATH} start
Restart=always
RestartSec=10
StandardOutput=append:/var/log/server-monitor.log
StandardError=append:/var/log/server-monitor.log
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF
    ok "Service file dibuat: $SERVICE_FILE"
}

setup_logrotate() {
    info "Mengatur log rotation..."
    cat > /etc/logrotate.d/server-monitor <<EOF
/var/log/server-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}

/var/log/soc-reports/*.txt {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
EOF
    ok "Log rotation dikonfigurasi"
}

enable_service() {
    info "Mengaktifkan dan menjalankan service..."
    systemctl daemon-reload
    systemctl enable "${SCRIPT_NAME}.service" &>/dev/null
    systemctl restart "${SCRIPT_NAME}.service" || systemctl start "${SCRIPT_NAME}.service"
    sleep 2
    if systemctl is-active --quiet "${SCRIPT_NAME}.service"; then
        ok "Service berjalan (active)"
    else
        warn "Service gagal start. Cek: journalctl -u ${SCRIPT_NAME} -n 30"
    fi
}

print_install_done() {
    local iface_used="${IFACE:-$(ip route 2>/dev/null | awk '/default/{print $5; exit}')}"
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║              ✅  INSTALASI BERHASIL!                  ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  📍 Script      : ${INSTALL_PATH}"
    echo -e "  ⚙️  Service     : ${SCRIPT_NAME}.service"
    echo -e "  📄 Log         : /var/log/server-monitor.log"
    echo -e "  🌐 Interface   : ${iface_used}"
    echo ""
    echo -e "  ${CYAN}${BOLD}Perintah berguna:${NC}"
    echo -e "  ├ Status       : systemctl status ${SCRIPT_NAME}"
    echo -e "  ├ Log live     : tail -f /var/log/server-monitor.log"
    echo -e "  ├ Block IP     : ${INSTALL_PATH} block 1.2.3.4"
    echo -e "  ├ Unblock IP   : ${INSTALL_PATH} unblock 1.2.3.4"
    echo -e "  ├ Lihat blokir : ${INSTALL_PATH} listip"
    echo -e "  └ Test bot     : ${INSTALL_PATH} test-telegram"
    echo ""
    echo -e "  ${YELLOW}Kirim /start ke bot Telegram untuk membuka menu! 🤖${NC}"
    echo ""
}

# =============================================================================
# MODE: INSTALL
# =============================================================================
do_install() {
    print_header
    check_root

    # Validasi parameter wajib
    if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
        err "Parameter --token dan --chatid wajib diisi untuk instalasi baru."
        echo ""
        echo -e "  Contoh:"
        echo -e "  ${CYAN}bash <(curl -s ${RAW_URL%monitor-server.sh}install-monitor.sh) --token \"TOKEN\" --chatid \"CHATID\"${NC}"
        echo ""
        exit 1
    fi

    check_deps

    # Download dari GitHub (selalu ambil versi terbaru)
    download_monitor

    # Terapkan konfigurasi
    apply_config

    # Setup dirs
    mkdir -p "$REPORT_DIR"
    touch "$BLOCKED_IPS" 2>/dev/null || true

    # Buat & aktifkan service
    create_service
    setup_logrotate
    enable_service
    print_install_done
}

# =============================================================================
# MODE: UPDATE
# =============================================================================
do_update() {
    print_header
    check_root

    info "Menghentikan service sementara..."
    systemctl stop "${SCRIPT_NAME}.service" 2>/dev/null || true

    # Backup konfigurasi yang ada
    local old_token old_chatid old_iface
    if [ -f "$INSTALL_PATH" ]; then
        old_token=$(grep  '^TELEGRAM_TOKEN=' "$INSTALL_PATH" | head -1 | sed 's/TELEGRAM_TOKEN="\(.*\)"/\1/')
        old_chatid=$(grep '^CHAT_ID='        "$INSTALL_PATH" | head -1 | sed 's/CHAT_ID="\(.*\)"/\1/')
        old_iface=$(grep  '^INTERFACE='      "$INSTALL_PATH" | head -1 | sed 's/INTERFACE="\(.*\)"/\1/')
        ok "Konfigurasi lama disimpan (token, chatid, interface)"
    fi

    # Download versi terbaru
    download_monitor

    # Restore konfigurasi lama (jika tidak ada yg baru dari argumen)
    [ -z "$TOKEN" ]   && TOKEN="$old_token"
    [ -z "$CHAT_ID" ] && CHAT_ID="$old_chatid"
    [ -z "$IFACE" ]   && IFACE="$old_iface"
    apply_config

    # Restart
    systemctl start "${SCRIPT_NAME}.service"
    sleep 2

    if systemctl is-active --quiet "${SCRIPT_NAME}.service"; then
        echo ""
        echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${GREEN}║              ✅  UPDATE BERHASIL!                     ║${NC}"
        echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  Script diperbarui ke versi terbaru dari GitHub."
        echo -e "  Konfigurasi token & interface dipertahankan."
        echo -e "  Service berjalan kembali: ${SCRIPT_NAME}.service"
        echo ""
    else
        err "Service gagal restart. Cek: journalctl -u ${SCRIPT_NAME} -n 30"
        exit 1
    fi
}

# =============================================================================
# MODE: UNINSTALL
# =============================================================================
do_uninstall() {
    print_header
    check_root

    info "Menghentikan dan menonaktifkan service..."
    systemctl stop    "${SCRIPT_NAME}.service" 2>/dev/null || true
    systemctl disable "${SCRIPT_NAME}.service" 2>/dev/null || true

    info "Menghapus file..."
    rm -f "$SERVICE_FILE"
    rm -f "$INSTALL_PATH"
    rm -f /etc/logrotate.d/server-monitor
    systemctl daemon-reload

    echo ""
    ok "Server monitor berhasil dihapus."
    echo -e "  Log masih tersimpan di: /var/log/server-monitor.log"
    echo -e "  IP blocked list       : $BLOCKED_IPS"
    echo ""
}

# =============================================================================
# MODE: HELP
# =============================================================================
do_help() {
    print_header
    cat <<HELP
${BOLD}PENGGUNAAN:${NC}

  ${CYAN}Install baru:${NC}
    bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) \\
      --token "TOKEN_BOT" --chatid "CHAT_ID"

  ${CYAN}Install dengan interface custom:${NC}
    bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) \\
      --token "TOKEN_BOT" --chatid "CHAT_ID" --iface "eth0"

  ${CYAN}Update ke versi terbaru:${NC}
    bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) --update

  ${CYAN}Uninstall:${NC}
    bash <(curl -s https://raw.githubusercontent.com/sahal-max/server-monitor-ddos/main/install-monitor.sh) --uninstall

${BOLD}PARAMETER:${NC}
  --token TOKEN     Telegram Bot Token dari @BotFather
  --chatid CHATID   Telegram Chat ID (grup atau pribadi)
  --iface IFACE     Interface jaringan (default: auto-detect)
  --update          Update script tanpa mengubah konfigurasi
  --uninstall       Hapus service dan script dari sistem
HELP
}

# =============================================================================
# ENTRY POINT
# =============================================================================
case "$MODE" in
    install)   do_install   ;;
    update)    do_update    ;;
    uninstall) do_uninstall ;;
    help)      do_help      ;;
esac
