#!/bin/bash
# =============================================================================
# INSTALLER UNTUK SERVER MONITOR & DDoS DETECTOR
# Memasang script sebagai systemd service
# =============================================================================

set -e

SCRIPT_NAME="monitor-server"
INSTALL_PATH="/usr/local/bin/${SCRIPT_NAME}.sh"
SERVICE_FILE="/etc/systemd/system/${SCRIPT_NAME}.service"
LOG_DIR="/var/log"
REPORT_DIR="/var/log/soc-reports"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   SERVER MONITOR & DDoS DETECTOR INSTALLER v2.0      ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Script ini harus dijalankan sebagai root"
        echo "Gunakan: sudo bash install-monitor.sh"
        exit 1
    fi
}

check_dependencies() {
    echo -e "${BLUE}[*]${NC} Memeriksa dependencies..."
    local missing=()

    for cmd in bc curl jq ss ps awk; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!]${NC} Dependency yang hilang: ${missing[*]}"
        echo -e "${BLUE}[*]${NC} Menginstal dependencies..."

        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            apt-get install -y -qq bc curl jq iproute2 procps gawk
        elif command -v yum &>/dev/null; then
            yum install -y -q bc curl jq iproute procps gawk
        elif command -v dnf &>/dev/null; then
            dnf install -y -q bc curl jq iproute procps gawk
        else
            echo -e "${RED}[ERROR]${NC} Package manager tidak ditemukan. Install manual: ${missing[*]}"
            exit 1
        fi
    fi

    echo -e "${GREEN}[✓]${NC} Semua dependencies tersedia"
}

install_script() {
    echo -e "${BLUE}[*]${NC} Menginstal script monitor..."

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [ ! -f "${script_dir}/monitor-server.sh" ]; then
        echo -e "${RED}[ERROR]${NC} File monitor-server.sh tidak ditemukan di ${script_dir}"
        exit 1
    fi

    cp "${script_dir}/monitor-server.sh" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"

    echo -e "${GREEN}[✓]${NC} Script diinstal ke: $INSTALL_PATH"
}

create_service() {
    echo -e "${BLUE}[*]${NC} Membuat systemd service..."

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Advanced Server Monitor & DDoS Detector with SOC Analysis
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

# Security
NoNewPrivileges=yes
ProtectSystem=full
ReadWritePaths=/var/log /var/log/soc-reports

# Environment
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}[✓]${NC} Service file dibuat: $SERVICE_FILE"
}

setup_logrotate() {
    echo -e "${BLUE}[*]${NC} Mengatur log rotation..."

    cat > /etc/logrotate.d/server-monitor <<EOF
/var/log/server-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        systemctl kill -s HUP ${SCRIPT_NAME}.service 2>/dev/null || true
    endscript
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

    echo -e "${GREEN}[✓]${NC} Log rotation dikonfigurasi"
}

enable_service() {
    echo -e "${BLUE}[*]${NC} Mengaktifkan dan memulai service..."

    systemctl daemon-reload
    systemctl enable "${SCRIPT_NAME}.service"
    systemctl start "${SCRIPT_NAME}.service"

    sleep 2

    if systemctl is-active --quiet "${SCRIPT_NAME}.service"; then
        echo -e "${GREEN}[✓]${NC} Service berhasil berjalan"
    else
        echo -e "${RED}[!]${NC} Service gagal start. Cek log: journalctl -u ${SCRIPT_NAME}"
    fi
}

configure_interface() {
    echo ""
    echo -e "${YELLOW}[?]${NC} Mendeteksi interface jaringan..."
    local default_iface
    default_iface=$(ip route | grep default | awk '{print $5}' | head -1)

    echo -e "    Interface yang terdeteksi: ${GREEN}${default_iface}${NC}"
    read -rp "    Gunakan interface ini? [Y/n] (default: Y): " confirm
    confirm="${confirm:-Y}"

    if [[ "$confirm" =~ ^[Nn] ]]; then
        read -rp "    Masukkan nama interface: " custom_iface
        if [ -n "$custom_iface" ]; then
            sed -i "s/^INTERFACE=.*/INTERFACE=\"${custom_iface}\"/" "$INSTALL_PATH"
            echo -e "${GREEN}[✓]${NC} Interface diatur ke: $custom_iface"
        fi
    else
        if [ -n "$default_iface" ]; then
            sed -i "s/^INTERFACE=.*/INTERFACE=\"${default_iface}\"/" "$INSTALL_PATH"
            echo -e "${GREEN}[✓]${NC} Interface diatur ke: $default_iface"
        fi
    fi
}

configure_telegram() {
    echo ""
    echo -e "${YELLOW}[?]${NC} Konfigurasi Telegram (Enter untuk lewati jika sudah dikonfigurasi):"

    read -rp "    Telegram Bot Token [kosongkan jika sudah ada]: " new_token
    if [ -n "$new_token" ]; then
        sed -i "s|^TELEGRAM_TOKEN=.*|TELEGRAM_TOKEN=\"${new_token}\"|" "$INSTALL_PATH"
        echo -e "${GREEN}[✓]${NC} Token diperbarui"
    fi

    read -rp "    Telegram Chat ID [kosongkan jika sudah ada]: " new_chat_id
    if [ -n "$new_chat_id" ]; then
        sed -i "s|^CHAT_ID=.*|CHAT_ID=\"${new_chat_id}\"|" "$INSTALL_PATH"
        echo -e "${GREEN}[✓]${NC} Chat ID diperbarui"
    fi
}

print_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   INSTALASI BERHASIL!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  📍 Script      : ${INSTALL_PATH}"
    echo -e "  ⚙️  Service     : ${SCRIPT_NAME}.service"
    echo -e "  📄 Log utama   : /var/log/server-monitor.log"
    echo -e "  📁 SOC reports : ${REPORT_DIR}/"
    echo ""
    echo -e "  ${YELLOW}Perintah berguna:${NC}"
    echo -e "  ├ Cek status   : systemctl status ${SCRIPT_NAME}"
    echo -e "  ├ Lihat log    : tail -f /var/log/server-monitor.log"
    echo -e "  ├ Stop monitor : systemctl stop ${SCRIPT_NAME}"
    echo -e "  ├ Test Telegram: ${INSTALL_PATH} test-telegram"
    echo -e "  ├ Test SOC     : ${INSTALL_PATH} test-soc"
    echo -e "  └ Test resource: ${INSTALL_PATH} test-resources"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
}

main() {
    print_header
    check_root
    check_dependencies
    install_script
    configure_interface
    configure_telegram

    mkdir -p "$REPORT_DIR"

    create_service
    setup_logrotate
    enable_service
    print_summary
}

case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        check_root
        echo -e "${YELLOW}[*]${NC} Menghapus server monitor..."
        systemctl stop "${SCRIPT_NAME}.service" 2>/dev/null || true
        systemctl disable "${SCRIPT_NAME}.service" 2>/dev/null || true
        rm -f "$SERVICE_FILE" "$INSTALL_PATH" /etc/logrotate.d/server-monitor
        systemctl daemon-reload
        echo -e "${GREEN}[✓]${NC} Server monitor berhasil dihapus"
        ;;
    *)
        echo "Usage: $0 {install|uninstall}"
        exit 1
        ;;
esac
