#!/bin/bash
# =============================================================================
# ADVANCED SERVER MONITOR + DDoS DETECTOR + TELEGRAM BOT
# Version: 3.0.0
# Features:
#   ✅ Monitoring jaringan (RX/TX) + deteksi DDoS
#   ✅ Monitoring CPU, RAM, Disk, Koneksi
#   ✅ SOC Credential Analysis (brute force, SSH, sudo)
#   ✅ Telegram Bot interaktif dengan menu inline keyboard
#   ✅ Manajemen IP: block / unblock / lihat daftar
#   ✅ Notifikasi rapi dan konsisten
#   ✅ Grafik sparkline ASCII
# =============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# =============================================================================
# ⚙️  KONFIGURASI — Edit sesuai kebutuhan
# =============================================================================
THRESHOLD_MBPS=150
THRESHOLD_CPU=85
THRESHOLD_RAM=90
THRESHOLD_DISK=90
THRESHOLD_CONN=5000
THRESHOLD_FAILED_LOGIN=20

INTERFACE="ens3"
SLEEP_INTERVAL=1
SAMPLE_COUNT=10

TELEGRAM_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"

LOG_FILE="/var/log/server-monitor.log"
REPORT_DIR="/var/log/soc-reports"
IP_BLOCK_LIST="/var/log/server-monitor-blocked-ips.txt"
GRAPH_HISTORY=20

NOTIFY_INTERVAL_DDOS=10
NOTIFY_INTERVAL_NORMAL=1800
NOTIFY_INTERVAL_ALERT=300
NOTIFY_INTERVAL_SOC=600

# =============================================================================
# 🔧 STATE
# =============================================================================
LAST_NOTIFY_DDOS=0
LAST_NOTIFY_NORMAL=0
LAST_NOTIFY_CPU=0
LAST_NOTIFY_RAM=0
LAST_NOTIFY_DISK=0
LAST_NOTIFY_CONN=0
LAST_NOTIFY_SOC=0

declare -a NET_HISTORY=()
declare -a CPU_HISTORY=()
declare -a RAM_HISTORY=()
declare -a NET_SAMPLES=()

CPU_USAGE="0.0"
RAM_PERCENT="0.0"
RAM_USED_MB=0; RAM_TOTAL_MB=0; SWAP_USED_MB=0; SWAP_TOTAL_MB=0
RX_MBPS="0.00"; TX_MBPS="0.00"; AVG_RX_MBPS="0.00"
ACTIVE_CONN=0; CURR_RX_BYTES=0; CURR_TX_BYTES=0

BOT_OFFSET=0
BOT_WAITING_IP=""     # chat_id yang sedang menunggu input IP
BOT_WAITING_ACTION="" # "block" atau "unblock"

# =============================================================================
# 📋 UTILITAS
# =============================================================================

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [${2:-INFO}] $1" >> "$LOG_FILE"; }

init_dirs() {
    mkdir -p "$REPORT_DIR"
    touch "$LOG_FILE" "$IP_BLOCK_LIST" 2>/dev/null || LOG_FILE="/tmp/server-monitor.log"
    log "Server Monitor v3.0 started | iface=$INTERFACE"
}

get_domain() {
    [ -f /etc/xray/domain ] && cat /etc/xray/domain && return
    hostname -f 2>/dev/null || hostname 2>/dev/null || echo "server"
}

float_ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }
float_gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 > b+0)}'; }

# =============================================================================
# 📡 TELEGRAM API
# =============================================================================

tg_post() {
    local endpoint="$1"; shift
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/${endpoint}" \
        "$@" --connect-timeout 10 --max-time 20 2>/dev/null
}

send_telegram() {
    local text="$1"
    tg_post "sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=HTML" > /dev/null
    log "Notification sent"
}

send_telegram_chat() {
    local chat_id="$1" text="$2"
    tg_post "sendMessage" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=HTML" > /dev/null
}

send_menu() {
    local chat_id="$1" text="$2" keyboard="$3"
    tg_post "sendMessage" \
        -d "chat_id=${chat_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" > /dev/null
}

edit_menu() {
    local chat_id="$1" msg_id="$2" text="$3" keyboard="$4"
    tg_post "editMessageText" \
        -d "chat_id=${chat_id}" \
        -d "message_id=${msg_id}" \
        --data-urlencode "text=${text}" \
        -d "parse_mode=HTML" \
        -d "reply_markup=${keyboard}" > /dev/null
}

answer_callback() {
    local callback_id="$1" text="$2"
    tg_post "answerCallbackQuery" \
        -d "callback_query_id=${callback_id}" \
        --data-urlencode "text=${text}" > /dev/null
}

delete_message() {
    local chat_id="$1" msg_id="$2"
    tg_post "deleteMessage" -d "chat_id=${chat_id}" -d "message_id=${msg_id}" > /dev/null
}

get_updates() {
    tg_post "getUpdates" \
        -d "offset=${BOT_OFFSET}" \
        -d "timeout=3" \
        -d "allowed_updates=[\"message\",\"callback_query\"]"
}

# =============================================================================
# 🌐 MONITORING JARINGAN
# =============================================================================

get_rx_bytes() { awk '/'"$INTERFACE"':/{print $2}' /proc/net/dev 2>/dev/null || echo 0; }
get_tx_bytes() { awk '/'"$INTERFACE"':/{print $10}' /proc/net/dev 2>/dev/null || echo 0; }

calc_mbps() {
    awk -v b="$1" -v i="${2:-1}" 'BEGIN{printf "%.2f",(b*8)/(1000000*i)}'
}

get_network_stats() {
    local curr_rx curr_tx rx_diff tx_diff
    curr_rx=$(get_rx_bytes); curr_tx=$(get_tx_bytes)
    rx_diff=$((curr_rx - $1)); tx_diff=$((curr_tx - $2))
    [ "$rx_diff" -lt 0 ] && rx_diff=0
    [ "$tx_diff" -lt 0 ] && tx_diff=0
    RX_MBPS=$(calc_mbps "$rx_diff" "$SLEEP_INTERVAL")
    TX_MBPS=$(calc_mbps "$tx_diff" "$SLEEP_INTERVAL")
    CURR_RX_BYTES=$curr_rx; CURR_TX_BYTES=$curr_tx
}

update_net_samples() {
    NET_SAMPLES+=("$RX_MBPS")
    [ "${#NET_SAMPLES[@]}" -gt "$SAMPLE_COUNT" ] && NET_SAMPLES=("${NET_SAMPLES[@]:1}")
}

get_avg_rx() {
    local count=${#NET_SAMPLES[@]}; [ "$count" -eq 0 ] && echo "0.00" && return
    local vals=""; for s in "${NET_SAMPLES[@]}"; do vals="$vals $s"; done
    awk -v vals="$vals" -v n="$count" 'BEGIN{split(vals,a," ");t=0;for(i in a)t+=a[i];printf "%.2f",t/n}'
}

# =============================================================================
# 💻 MONITORING CPU
# =============================================================================

get_cpu_usage() {
    [ ! -f /proc/stat ] && echo "0.0" && return
    local s1 s2
    s1=$(awk 'NR==1{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
    sleep 0.3
    s2=$(awk 'NR==1{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
    awk -v s1="$s1" -v s2="$s2" 'BEGIN{
        n=split(s1,a," "); split(s2,b," ")
        t1=0;t2=0; for(i=1;i<=n;i++){t1+=a[i];t2+=b[i]}
        di=b[4]-a[4]; dt=t2-t1
        printf "%.1f",(dt>0)?(dt-di)*100/dt:0
    }'
}

get_cpu_load() {
    uptime 2>/dev/null | awk -F'load average:' '{gsub(/,/,"",$2);print $2}' | xargs || echo "0 0 0"
}

get_top_cpu_procs() {
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1&&NR<=6{
        cmd=$11; if(length(cmd)>22) cmd=substr(cmd,1,19)"..."
        printf "  %-8s %5s%%  %s\n",$1,$3,cmd
    }' || echo "  N/A"
}

# =============================================================================
# 🧠 MONITORING RAM
# =============================================================================

get_ram_usage() {
    local total avail used
    total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 1)
    avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    used=$((total - avail))
    RAM_TOTAL_MB=$((total/1024)); RAM_USED_MB=$((used/1024))
    RAM_PERCENT=$(awk -v u="$used" -v t="$total" 'BEGIN{printf "%.1f",(t>0)?u*100/t:0}')
    local st sf
    st=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    sf=$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    SWAP_USED_MB=$(( (st-sf)/1024 )); SWAP_TOTAL_MB=$((st/1024))
}

get_top_ram_procs() {
    ps aux --sort=-%mem 2>/dev/null | awk 'NR>1&&NR<=6{
        cmd=$11; if(length(cmd)>22) cmd=substr(cmd,1,19)"..."
        printf "  %-8s %5s%%  %s\n",$1,$4,cmd
    }' || echo "  N/A"
}

# =============================================================================
# 💿 MONITORING DISK & KONEKSI
# =============================================================================

get_disk_info() {
    df -h / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $2","$3","$4","$5}' || echo "N/A,N/A,N/A,0"
}

get_active_connections() {
    local c=0
    command -v ss &>/dev/null && c=$(ss -tan 2>/dev/null | awk 'NR>1&&$1=="ESTAB"' | wc -l) || \
    command -v netstat &>/dev/null && c=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
    echo "${c:-0}"
}

get_top_ips() {
    ss -tan 2>/dev/null | awk 'NR>1&&$1=="ESTAB"{
        n=split($5,a,":"); ip=(n>=4)?a[1]":"a[2]":"a[3]":"a[4]:a[1]; count[ip]++
    }END{for(ip in count) print count[ip],ip}' | sort -rn | head -5 | \
    awk '{printf "  %-5s %s\n",$1,$2}' || echo "  N/A"
}

get_conn_states() {
    ss -tan 2>/dev/null | awk 'NR>1{s[$1]++}END{for(x in s) printf "  %-12s %d\n",x,s[x]}' | \
    sort -t' ' -k2 -rn | head -5 || echo "  N/A"
}

# =============================================================================
# 🛡️  IP MANAGEMENT
# =============================================================================

ip_block() {
    local ip="$1"
    # Validate IP format
    if ! echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]+)?$'; then
        echo "INVALID"
        return 1
    fi
    # Check if already blocked
    if grep -qF "$ip" "$IP_BLOCK_LIST" 2>/dev/null; then
        echo "EXISTS"
        return 1
    fi
    # Block with iptables if available
    if command -v iptables &>/dev/null; then
        iptables -I INPUT -s "$ip" -j DROP 2>/dev/null
        iptables -I FORWARD -s "$ip" -j DROP 2>/dev/null
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $ip" >> "$IP_BLOCK_LIST"
    log "IP blocked: $ip" "WARN"
    echo "OK"
}

ip_unblock() {
    local ip="$1"
    if ! grep -qF "$ip" "$IP_BLOCK_LIST" 2>/dev/null; then
        echo "NOT_FOUND"
        return 1
    fi
    if command -v iptables &>/dev/null; then
        iptables -D INPUT -s "$ip" -j DROP 2>/dev/null
        iptables -D FORWARD -s "$ip" -j DROP 2>/dev/null
    fi
    sed -i "/$ip/d" "$IP_BLOCK_LIST"
    log "IP unblocked: $ip"
    echo "OK"
}

ip_list() {
    if [ ! -s "$IP_BLOCK_LIST" ]; then
        echo "  (Tidak ada IP yang diblokir)"
        return
    fi
    local count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        count=$((count+1))
        local ts ip
        ts=$(echo "$line" | awk '{print $1,$2}')
        ip=$(echo "$line" | awk '{print $3}')
        printf "  %2d. %-18s %s\n" "$count" "$ip" "$ts"
    done < "$IP_BLOCK_LIST"
}

ip_count() {
    grep -c '.' "$IP_BLOCK_LIST" 2>/dev/null || echo 0
}

# =============================================================================
# 🔍 SOC
# =============================================================================

find_auth_log() {
    for f in /var/log/auth.log /var/log/secure /var/log/messages; do
        [ -f "$f" ] && echo "$f" && return
    done; echo ""
}

get_failed_ssh_count() {
    local lf; lf=$(find_auth_log); [ -z "$lf" ] && echo 0 && return
    grep -c "Failed password\|Invalid user\|authentication failure" "$lf" 2>/dev/null || echo 0
}

get_top_failed_ips() {
    local lf; lf=$(find_auth_log)
    [ -z "$lf" ] && echo "  (auth log tidak ditemukan)" && return
    grep -i "Failed password\|Invalid user" "$lf" 2>/dev/null | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  %-5s %s\n",$1,$2}' || echo "  Tidak ada"
}

get_brute_force_ips() {
    local lf; lf=$(find_auth_log)
    [ -z "$lf" ] && echo "  (auth log tidak ditemukan)" && return
    local r; r=$(grep -i "Failed password" "$lf" 2>/dev/null | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | \
    awk '$1>=10{printf "  %-5s %s\n",$1,$2}' | head -5)
    echo "${r:-  Tidak ada}"
}

get_active_ssh() {
    local s; s=$(who 2>/dev/null | awk '{print "  "$1" ("$5")"}')
    echo "${s:-  Tidak ada sesi aktif}"
}

generate_soc_report() {
    local ts; ts=$(date '+%Y-%m-%d_%H-%M-%S')
    local rf="${REPORT_DIR}/soc_${ts}.txt"
    {
        echo "══════════════════════════════════════════"
        echo "  SOC SECURITY REPORT — $(get_domain)"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "══════════════════════════════════════════"
        printf "\n[FAILED LOGIN]\nTotal: $(get_failed_ssh_count)\n"
        printf "\n[TOP ATTACKER IPs]\n"; get_top_failed_ips
        printf "\n[BRUTE FORCE (>=10)]\n"; get_brute_force_ips
        printf "\n[ACTIVE SSH]\n"; get_active_ssh
        printf "\n[BLOCKED IPs]\n"; ip_list
        echo "══════════════════════════════════════════"
    } > "$rf"
    echo "$rf"
}

# =============================================================================
# 📊 GRAFIK ASCII
# =============================================================================

make_bar() {
    local v=$1 m=${2:-100} w=${3:-16}
    awk -v v="$v" -v m="$m" -v w="$w" 'BEGIN{
        f=int(v*w/m); if(f>w)f=w
        b=""; for(i=0;i<f;i++)b=b"█"; for(i=f;i<w;i++)b=b"░"
        print b
    }'
}

make_sparkline() {
    local -a arr=("$@"); [ ${#arr[@]} -eq 0 ] && echo "▁" && return
    local vals=""; for v in "${arr[@]}"; do vals="$vals $v"; done
    awk -v vals="$vals" 'BEGIN{
        n=split(vals,a," ")
        c[0]="▁";c[1]="▂";c[2]="▃";c[3]="▄";c[4]="▅";c[5]="▆";c[6]="▇";c[7]="█"
        mx=0; for(i=1;i<=n;i++) if(a[i]+0>mx) mx=a[i]+0; if(mx==0)mx=1
        s=""; for(i=1;i<=n;i++){idx=int(a[i]*7/mx);if(idx>7)idx=7;s=s c[idx]}
        print s
    }'
}

update_history() {
    local ni ci ri
    ni=$(awk -v v="$AVG_RX_MBPS" 'BEGIN{printf "%d",v}')
    ci=$(awk -v v="$CPU_USAGE"   'BEGIN{printf "%d",v}')
    ri=$(awk -v v="$RAM_PERCENT" 'BEGIN{printf "%d",v}')
    NET_HISTORY+=("$ni"); CPU_HISTORY+=("$ci"); RAM_HISTORY+=("$ri")
    [ "${#NET_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && NET_HISTORY=("${NET_HISTORY[@]:1}")
    [ "${#CPU_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && CPU_HISTORY=("${CPU_HISTORY[@]:1}")
    [ "${#RAM_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && RAM_HISTORY=("${RAM_HISTORY[@]:1}")
}

status_dot() {
    local v=$1 hi=$2
    local warn; warn=$(awk -v h="$hi" 'BEGIN{printf "%d",h*0.75}')
    float_ge "$v" "$hi" && echo "🔴" && return
    float_ge "$v" "$warn" && echo "🟡" && return
    echo "🟢"
}

# =============================================================================
# 💬 PESAN NOTIFIKASI (Format rapi)
# =============================================================================

LINE="▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰"

msg_ddos() {
    local dom="$1" avg="$2" spark="$3"
    cat <<MSG
${LINE}
🚨 <b>SERANGAN DDoS TERDETEKSI!</b>
${LINE}
🖥 Server  : <b>${dom}</b>
📅 Waktu   : $(date '+%d/%m/%Y %H:%M:%S')

📶 <b>Trafik Masuk</b>
├ Rata-rata : <b>${avg} Mbps</b>
├ Sekarang  : ${RX_MBPS} Mbps ↑  ${TX_MBPS} Mbps ↓
└ Koneksi   : <b>${ACTIVE_CONN}</b> aktif

📈 Tren 20 detik:
<code>${spark}</code>

⚡ Batas aman : ${THRESHOLD_MBPS} Mbps
${LINE}
⚠️ <b>Segera blokir IP penyerang!</b>
MSG
}

msg_status() {
    local dom="$1" avg="$2"
    local di ds du da dp
    IFS=',' read -r ds du da dp <<< "$(get_disk_info)"

    local nd cd rd
    nd=$(status_dot "${AVG_RX_MBPS%.*}" "$THRESHOLD_MBPS")
    cd=$(status_dot "${CPU_USAGE%.*}" "$THRESHOLD_CPU")
    rd=$(status_dot "${RAM_PERCENT%.*}" "$THRESHOLD_RAM")
    local dd; dd=$(status_dot "${dp:-0}" "$THRESHOLD_DISK")
    local od; od=$(status_dot "$ACTIVE_CONN" "$THRESHOLD_CONN")

    local nsp csp rsp
    nsp=$(make_sparkline "${NET_HISTORY[@]}")
    csp=$(make_sparkline "${CPU_HISTORY[@]}")
    rsp=$(make_sparkline "${RAM_HISTORY[@]}")

    local cb rb
    cb=$(make_bar "${CPU_USAGE%.*}" 100 14)
    rb=$(make_bar "${RAM_PERCENT%.*}" 100 14)

    cat <<MSG
${LINE}
📊 <b>LAPORAN STATUS SERVER</b>
${LINE}
🖥 Server  : <b>${dom}</b>
📅 Waktu   : $(date '+%d/%m/%Y %H:%M:%S')
⏱ Uptime  : $(uptime -p 2>/dev/null || echo "N/A")

${nd} <b>Jaringan</b>
   ↑ RX : ${avg} Mbps (avg)  ↓ TX : ${TX_MBPS} Mbps
   <code>${nsp}</code>

${cd} <b>CPU</b> — ${CPU_USAGE}%
   <code>${cb}</code> Load: $(get_cpu_load | awk '{print $1}')
   <code>${csp}</code>

${rd} <b>RAM</b> — ${RAM_PERCENT}% (${RAM_USED_MB}/${RAM_TOTAL_MB} MB)
   <code>${rb}</code> Swap: ${SWAP_USED_MB}/${SWAP_TOTAL_MB} MB
   <code>${rsp}</code>

${dd} <b>Disk</b> — ${dp}% (${du}/${ds}, sisa ${da})

${od} <b>Koneksi</b> — ${ACTIVE_CONN} aktif
${LINE}
✅ <i>Semua dalam batas normal</i>
MSG
}

msg_alert() {
    local dom="$1" type="$2" val="$3" thr="$4" detail="$5"
    cat <<MSG
${LINE}
⚠️ <b>ALERT: ${type}</b>
${LINE}
🖥 Server : <b>${dom}</b>
📅 Waktu  : $(date '+%d/%m/%Y %H:%M:%S')
📊 Nilai  : <b>${val}</b>
🔴 Batas  : ${thr}

${detail}
${LINE}
MSG
}

msg_soc() {
    local dom="$1" failed="$2"
    local lvl="✅ Rendah"
    [ "${failed:-0}" -ge "$THRESHOLD_FAILED_LOGIN" ] && lvl="🔴 TINGGI"
    [ "${failed:-0}" -ge $((THRESHOLD_FAILED_LOGIN/2)) ] && \
        [ "${failed:-0}" -lt "$THRESHOLD_FAILED_LOGIN" ] && lvl="🟡 Sedang"
    cat <<MSG
${LINE}
🛡 <b>LAPORAN KEAMANAN SOC</b>
${LINE}
🖥 Server : <b>${dom}</b>
📅 Waktu  : $(date '+%d/%m/%Y %H:%M:%S')
🚦 Ancaman: ${lvl}

🔐 <b>Login Gagal (5 mnt):</b> <b>${failed}</b>

📍 <b>Top IP Penyerang:</b>
<code>$(get_top_failed_ips)</code>

🚫 <b>Brute Force (≥10x):</b>
<code>$(get_brute_force_ips)</code>

👤 <b>SSH Aktif:</b>
<code>$(get_active_ssh)</code>

🔒 <b>IP Diblokir:</b> $(ip_count)
${LINE}
MSG
}

msg_top_procs() {
    local dom="$1"
    cat <<MSG
${LINE}
🔬 <b>TOP PROSES SERVER</b>
${LINE}
🖥 Server : <b>${dom}</b>
📅 Waktu  : $(date '+%d/%m/%Y %H:%M:%S')

💻 <b>CPU teratas:</b>
<code>$(get_top_cpu_procs)</code>

🧠 <b>RAM teratas:</b>
<code>$(get_top_ram_procs)</code>
${LINE}
MSG
}

# =============================================================================
# 🤖 TELEGRAM BOT — MENU & KEYBOARD
# =============================================================================

KB_MAIN='{"inline_keyboard":[
  [{"text":"📊 Status Server","callback_data":"status"},{"text":"🌐 Info Jaringan","callback_data":"network"}],
  [{"text":"🔒 Kelola IP Block","callback_data":"ip_menu"},{"text":"🛡 Laporan SOC","callback_data":"soc"}],
  [{"text":"📋 Top Proses","callback_data":"procs"},{"text":"🔄 Refresh","callback_data":"refresh"}]
]}'

KB_IP='{"inline_keyboard":[
  [{"text":"📋 Lihat IP Blocked","callback_data":"ip_list"}],
  [{"text":"🚫 Tambah Block IP","callback_data":"ip_add"},{"text":"✅ Hapus Block IP","callback_data":"ip_del"}],
  [{"text":"🔙 Kembali","callback_data":"main_menu"}]
]}'

KB_BACK='{"inline_keyboard":[[{"text":"🔙 Kembali ke Menu","callback_data":"main_menu"}]]}'

build_status_menu() {
    local dom; dom=$(get_domain)
    get_ram_usage; CPU_USAGE=$(get_cpu_usage); ACTIVE_CONN=$(get_active_connections)
    AVG_RX_MBPS=$(get_avg_rx)

    local di ds du da dp; IFS=',' read -r ds du da dp <<< "$(get_disk_info)"
    local nd cd rd dd od
    nd=$(status_dot "${AVG_RX_MBPS%.*}" "$THRESHOLD_MBPS")
    cd=$(status_dot "${CPU_USAGE%.*}" "$THRESHOLD_CPU")
    rd=$(status_dot "${RAM_PERCENT%.*}" "$THRESHOLD_RAM")
    dd=$(status_dot "${dp:-0}" "$THRESHOLD_DISK")
    od=$(status_dot "$ACTIVE_CONN" "$THRESHOLD_CONN")

    cat <<MSG
${LINE}
📊 <b>STATUS SERVER</b>
${LINE}
🖥 <b>${dom}</b>
📅 $(date '+%d/%m/%Y %H:%M:%S')
⏱ $(uptime -p 2>/dev/null || echo "N/A")

${nd} Jaringan  : ${AVG_RX_MBPS} Mbps
${cd} CPU       : ${CPU_USAGE}% | Load $(get_cpu_load | awk '{print $1}')
${rd} RAM       : ${RAM_PERCENT}% (${RAM_USED_MB}/${RAM_TOTAL_MB} MB)
${dd} Disk      : ${dp}% (sisa ${da})
${od} Koneksi   : ${ACTIVE_CONN} aktif
${LINE}
MSG
}

build_network_menu() {
    local dom; dom=$(get_domain)
    local nsp; nsp=$(make_sparkline "${NET_HISTORY[@]}")
    cat <<MSG
${LINE}
🌐 <b>INFO JARINGAN</b>
${LINE}
🖥 <b>${dom}</b>
📅 $(date '+%d/%m/%Y %H:%M:%S')

↑ RX Avg : <b>${AVG_RX_MBPS} Mbps</b>
↑ RX Now : ${RX_MBPS} Mbps
↓ TX Now : ${TX_MBPS} Mbps
🔌 Koneksi: ${ACTIVE_CONN}
⚡ Batas  : ${THRESHOLD_MBPS} Mbps

📈 Tren RX:
<code>${nsp}</code>

📍 <b>Top Koneksi IP:</b>
<code>$(get_top_ips)</code>

📡 <b>State Koneksi:</b>
<code>$(get_conn_states)</code>
${LINE}
MSG
}

build_ip_list_msg() {
    local cnt; cnt=$(ip_count)
    cat <<MSG
${LINE}
🔒 <b>DAFTAR IP BLOCKED</b>
${LINE}
Total: <b>${cnt}</b> IP diblokir

<code>$(ip_list)</code>
${LINE}
MSG
}

# =============================================================================
# 🤖 BOT — HANDLER PESAN & CALLBACK
# =============================================================================

handle_command() {
    local chat_id="$1" text="$2"

    case "$text" in
        /start|/menu|/help)
            send_menu "$chat_id" \
"${LINE}
🤖 <b>SERVER MONITOR BOT</b>
${LINE}
Halo! Saya memantau server Anda secara real-time.
Pilih menu di bawah ini:" \
                "$KB_MAIN"
            ;;
        /status)
            local smsg; smsg=$(build_status_menu)
            send_menu "$chat_id" "$smsg" "$KB_BACK"
            ;;
        /block*)
            local ip; ip=$(echo "$text" | awk '{print $2}')
            if [ -z "$ip" ]; then
                send_telegram_chat "$chat_id" "Gunakan: /block 1.2.3.4"
            else
                local res; res=$(ip_block "$ip")
                case "$res" in
                    OK)        send_telegram_chat "$chat_id" "✅ IP <code>${ip}</code> berhasil diblokir" ;;
                    EXISTS)    send_telegram_chat "$chat_id" "ℹ️ IP <code>${ip}</code> sudah diblokir sebelumnya" ;;
                    INVALID)   send_telegram_chat "$chat_id" "❌ Format IP tidak valid: <code>${ip}</code>" ;;
                esac
            fi
            ;;
        /unblock*)
            local ip; ip=$(echo "$text" | awk '{print $2}')
            if [ -z "$ip" ]; then
                send_telegram_chat "$chat_id" "Gunakan: /unblock 1.2.3.4"
            else
                local res; res=$(ip_unblock "$ip")
                case "$res" in
                    OK)        send_telegram_chat "$chat_id" "✅ IP <code>${ip}</code> berhasil di-unblock" ;;
                    NOT_FOUND) send_telegram_chat "$chat_id" "ℹ️ IP <code>${ip}</code> tidak ada di daftar block" ;;
                esac
            fi
            ;;
        /listip)
            send_menu "$chat_id" "$(build_ip_list_msg)" "$KB_BACK"
            ;;
    esac
}

handle_callback() {
    local chat_id="$1" msg_id="$2" cb_id="$3" data="$4"

    answer_callback "$cb_id" ""

    case "$data" in
        main_menu)
            edit_menu "$chat_id" "$msg_id" \
"${LINE}
🤖 <b>SERVER MONITOR BOT</b>
${LINE}
🖥 Server: <b>$(get_domain)</b>
📅 $(date '+%d/%m/%Y %H:%M:%S')

Pilih menu:" "$KB_MAIN"
            ;;
        status)
            local smsg; smsg=$(build_status_menu)
            edit_menu "$chat_id" "$msg_id" "$smsg" "$KB_BACK"
            ;;
        network)
            edit_menu "$chat_id" "$msg_id" "$(build_network_menu)" "$KB_BACK"
            ;;
        ip_menu)
            edit_menu "$chat_id" "$msg_id" \
"${LINE}
🔒 <b>KELOLA IP BLOCK</b>
${LINE}
Total diblokir: <b>$(ip_count)</b> IP

Pilih tindakan:" "$KB_IP"
            ;;
        ip_list)
            edit_menu "$chat_id" "$msg_id" "$(build_ip_list_msg)" "$KB_BACK"
            ;;
        ip_add)
            BOT_WAITING_IP="$chat_id"
            BOT_WAITING_ACTION="block"
            edit_menu "$chat_id" "$msg_id" \
"${LINE}
🚫 <b>TAMBAH IP BLOCK</b>
${LINE}
Kirim IP address yang ingin diblokir.

Contoh: <code>192.168.1.100</code>
Atau dengan prefix: <code>10.0.0.0/24</code>

Ketik /batal untuk membatalkan." "$KB_BACK"
            ;;
        ip_del)
            if [ "$(ip_count)" -eq 0 ]; then
                answer_callback "$cb_id" "Tidak ada IP yang diblokir"
                return
            fi
            BOT_WAITING_IP="$chat_id"
            BOT_WAITING_ACTION="unblock"
            edit_menu "$chat_id" "$msg_id" \
"${LINE}
✅ <b>HAPUS BLOCK IP</b>
${LINE}
<b>IP yang sedang diblokir:</b>
<code>$(ip_list)</code>

Kirim IP yang ingin di-unblock.
Ketik /batal untuk membatalkan." "$KB_BACK"
            ;;
        soc)
            get_ram_usage; CPU_USAGE=$(get_cpu_usage)
            local failed; failed=$(get_failed_ssh_count)
            local smsg; smsg=$(msg_soc "$(get_domain)" "$failed")
            edit_menu "$chat_id" "$msg_id" "$smsg" "$KB_BACK"
            ;;
        procs)
            edit_menu "$chat_id" "$msg_id" "$(msg_top_procs "$(get_domain)")" "$KB_BACK"
            ;;
        refresh)
            answer_callback "$cb_id" "🔄 Memperbarui data..."
            get_ram_usage; CPU_USAGE=$(get_cpu_usage); ACTIVE_CONN=$(get_active_connections)
            local smsg; smsg=$(build_status_menu)
            edit_menu "$chat_id" "$msg_id" "$smsg" "$KB_BACK"
            ;;
    esac
}

handle_ip_input() {
    local chat_id="$1" text="$2"

    if [ "$text" = "/batal" ]; then
        BOT_WAITING_IP=""
        BOT_WAITING_ACTION=""
        send_menu "$chat_id" "❌ Dibatalkan." "$KB_IP"
        return
    fi

    local ip; ip=$(echo "$text" | tr -d ' ')
    local res

    if [ "$BOT_WAITING_ACTION" = "block" ]; then
        res=$(ip_block "$ip")
        case "$res" in
            OK)
                send_menu "$chat_id" \
"✅ <b>IP Berhasil Diblokir!</b>

🚫 IP: <code>${ip}</code>
📅 $(date '+%d/%m/%Y %H:%M:%S')
📋 Total blokir: $(ip_count) IP" "$KB_IP"
                ;;
            EXISTS)
                send_menu "$chat_id" "ℹ️ IP <code>${ip}</code> sudah ada di daftar block." "$KB_IP"
                ;;
            INVALID)
                send_telegram_chat "$chat_id" \
"❌ <b>Format IP tidak valid!</b>

Contoh yang benar:
• <code>192.168.1.100</code>
• <code>10.0.0.0/24</code>

Coba kirim lagi:"
                return
                ;;
        esac
    elif [ "$BOT_WAITING_ACTION" = "unblock" ]; then
        res=$(ip_unblock "$ip")
        case "$res" in
            OK)
                send_menu "$chat_id" \
"✅ <b>IP Berhasil Di-unblock!</b>

🔓 IP: <code>${ip}</code>
📅 $(date '+%d/%m/%Y %H:%M:%S')
📋 Sisa blokir: $(ip_count) IP" "$KB_IP"
                ;;
            NOT_FOUND)
                send_menu "$chat_id" \
"❌ IP <code>${ip}</code> tidak ditemukan di daftar block.

<b>IP yang tersedia:</b>
<code>$(ip_list)</code>" "$KB_IP"
                ;;
        esac
    fi

    BOT_WAITING_IP=""
    BOT_WAITING_ACTION=""
}

# =============================================================================
# 🔄 BOT POLLING LOOP
# =============================================================================

run_bot_listener() {
    log "Bot listener started (polling)"

    while true; do
        local resp
        resp=$(get_updates 2>/dev/null)

        if ! echo "$resp" | grep -q '"ok":true'; then
            sleep 5; continue
        fi

        # Count updates
        local count
        count=$(echo "$resp" | grep -o '"update_id"' | wc -l)
        [ "$count" -eq 0 ] && sleep 1 && continue

        # Process each update
        local i=1
        while [ "$i" -le "$count" ]; do
            local upd
            upd=$(echo "$resp" | awk -v n="$i" 'BEGIN{d=0;c=0}
                /"update_id"/{c++;if(c==n)d=1}
                d{print}
                d&&/^\s*\}/{if(d){d=0;exit}}' 2>/dev/null || echo "")

            local upd_id chat_id text data msg_id cb_id

            upd_id=$(echo "$resp" | grep -o '"update_id":[0-9]*' | awk -v n="$i" 'NR==n{gsub(/[^0-9]/,"",$0);print}')

            if [ -n "$upd_id" ]; then
                BOT_OFFSET=$((upd_id + 1))
            fi

            # Try to parse via raw grep on the full response (per update_id offset)
            local raw_update
            raw_update=$(echo "$resp" | grep -A 100 "\"update_id\":${upd_id}" | head -80)

            # Extract message fields
            chat_id=$(echo "$raw_update" | grep -o '"id":-\?[0-9]*' | head -1 | grep -o '-\?[0-9]*')
            msg_id=$(echo "$raw_update" | grep -o '"message_id":[0-9]*' | head -1 | grep -o '[0-9]*$')
            text=$(echo "$raw_update" | grep '"text"' | head -1 | sed 's/.*"text":"\(.*\)".*/\1/' | sed 's/\\//g')
            cb_id=$(echo "$raw_update" | grep '"callback_query"' | head -1)
            data=$(echo "$raw_update" | grep '"data"' | head -1 | sed 's/.*"data":"\(.*\)".*/\1/')

            if [ -n "$cb_id" ] && [ -n "$data" ]; then
                # It's a callback query
                local cq_id
                cq_id=$(echo "$raw_update" | grep '"id"' | grep -v '"user"\|"chat"\|"message"' | head -1 | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
                chat_id=$(echo "$raw_update" | grep -o '"id":-\?[0-9]*' | head -2 | tail -1 | grep -o '-\?[0-9]*')
                cq_id=$(echo "$raw_update" | sed -n 's/.*"callback_query".*"id":"\([^"]*\)".*/\1/p' | head -1)
                msg_id=$(echo "$raw_update" | grep -o '"message_id":[0-9]*' | head -1 | grep -o '[0-9]*$')
                handle_callback "$chat_id" "$msg_id" "$cq_id" "$data"
            elif [ -n "$text" ] && [ -n "$chat_id" ]; then
                # It's a message
                if [ "$chat_id" = "$BOT_WAITING_IP" ] && [ -n "$BOT_WAITING_ACTION" ]; then
                    handle_ip_input "$chat_id" "$text"
                elif echo "$text" | grep -q '^/'; then
                    handle_command "$chat_id" "$text"
                fi
            fi

            i=$((i+1))
        done

        sleep 1
    done
}

# =============================================================================
# 🔔 NOTIFIKASI MONITORING
# =============================================================================

notify_ddos() {
    local dom="$1" now="$2" avg="$3"
    float_gt "$avg" "$THRESHOLD_MBPS" || return 1
    (( now - LAST_NOTIFY_DDOS >= NOTIFY_INTERVAL_DDOS )) || return 0
    log "DDoS detected: avg=${avg} Mbps" "WARN"
    local spark; spark=$(make_sparkline "${NET_HISTORY[@]}")
    send_telegram "$(msg_ddos "$dom" "$avg" "$spark")"
    LAST_NOTIFY_DDOS=$now
    return 0
}

notify_normal() {
    local dom="$1" now="$2" avg="$3"
    (( now - LAST_NOTIFY_NORMAL >= NOTIFY_INTERVAL_NORMAL )) || return
    log "Normal status report"
    send_telegram "$(msg_status "$dom" "$avg")"
    send_telegram "$(msg_top_procs "$dom")"
    LAST_NOTIFY_NORMAL=$now
}

notify_cpu() {
    local dom="$1" now="$2"
    float_ge "$CPU_USAGE" "$THRESHOLD_CPU" || return
    (( now - LAST_NOTIFY_CPU >= NOTIFY_INTERVAL_ALERT )) || return
    log "CPU alert: ${CPU_USAGE}%" "WARN"
    local detail; detail="💻 <b>Top CPU:</b>
<code>$(get_top_cpu_procs)</code>"
    send_telegram "$(msg_alert "$dom" "CPU TINGGI" "${CPU_USAGE}%" "${THRESHOLD_CPU}%" "$detail")"
    LAST_NOTIFY_CPU=$now
}

notify_ram() {
    local dom="$1" now="$2"
    float_ge "$RAM_PERCENT" "$THRESHOLD_RAM" || return
    (( now - LAST_NOTIFY_RAM >= NOTIFY_INTERVAL_ALERT )) || return
    log "RAM alert: ${RAM_PERCENT}%" "WARN"
    local detail; detail="🧠 <b>Top RAM:</b>
<code>$(get_top_ram_procs)</code>
🔄 Swap: ${SWAP_USED_MB}/${SWAP_TOTAL_MB} MB"
    send_telegram "$(msg_alert "$dom" "RAM TINGGI" "${RAM_PERCENT}%" "${THRESHOLD_RAM}%" "$detail")"
    LAST_NOTIFY_RAM=$now
}

notify_disk() {
    local dom="$1" now="$2"
    local di ds du da dp; IFS=',' read -r ds du da dp <<< "$(get_disk_info)"
    [ -z "$dp" ] || [ "$dp" = "0" ] && return
    float_ge "$dp" "$THRESHOLD_DISK" || return
    (( now - LAST_NOTIFY_DISK >= NOTIFY_INTERVAL_ALERT )) || return
    log "Disk alert: ${dp}%" "WARN"
    local detail; detail="💿 ${du} terpakai dari ${ds} (sisa ${da})"
    send_telegram "$(msg_alert "$dom" "DISK HAMPIR PENUH" "${dp}%" "${THRESHOLD_DISK}%" "$detail")"
    LAST_NOTIFY_DISK=$now
}

notify_conn() {
    local dom="$1" now="$2"
    (( ACTIVE_CONN >= THRESHOLD_CONN )) || return
    (( now - LAST_NOTIFY_CONN >= NOTIFY_INTERVAL_ALERT )) || return
    log "Connection alert: ${ACTIVE_CONN}" "WARN"
    local detail; detail="📡 <b>Top IP:</b>
<code>$(get_top_ips)</code>
📊 <b>States:</b>
<code>$(get_conn_states)</code>"
    send_telegram "$(msg_alert "$dom" "KONEKSI BERLEBIHAN" "$ACTIVE_CONN" "$THRESHOLD_CONN" "$detail")"
    LAST_NOTIFY_CONN=$now
}

notify_soc() {
    local dom="$1" now="$2"
    (( now - LAST_NOTIFY_SOC >= NOTIFY_INTERVAL_SOC )) || return
    local failed; failed=$(get_failed_ssh_count)
    log "SOC check: failed=${failed}"
    local rf; rf=$(generate_soc_report)
    log "SOC report: $rf"
    send_telegram "$(msg_soc "$dom" "$failed")"
    LAST_NOTIFY_SOC=$now
}

# =============================================================================
# 🚀 MAIN LOOP
# =============================================================================

main() {
    init_dirs

    local domain; domain=$(get_domain)
    log "Starting | domain=${domain} | iface=${INTERFACE}"

    # Kirim notifikasi startup
    send_menu "$CHAT_ID" \
"${LINE}
✅ <b>SERVER MONITOR AKTIF</b>
${LINE}
🖥 Server : <b>${domain}</b>
📅 Mulai  : $(date '+%d/%m/%Y %H:%M:%S')
🌐 Iface  : ${INTERFACE}
⚡ Batas DDoS : ${THRESHOLD_MBPS} Mbps

Gunakan menu untuk kontrol bot:" "$KB_MAIN"

    # Jalankan bot listener di background
    run_bot_listener &
    BOT_PID=$!
    log "Bot listener PID: $BOT_PID"

    local prev_rx prev_tx
    prev_rx=$(get_rx_bytes); prev_tx=$(get_tx_bytes)

    # Monitoring loop
    while true; do
        sleep "$SLEEP_INTERVAL"

        get_network_stats "$prev_rx" "$prev_tx"
        update_net_samples
        AVG_RX_MBPS=$(get_avg_rx)
        get_ram_usage
        CPU_USAGE=$(get_cpu_usage)
        ACTIVE_CONN=$(get_active_connections)
        update_history

        prev_rx=$CURR_RX_BYTES
        prev_tx=$CURR_TX_BYTES

        log "RX:${RX_MBPS} TX:${TX_MBPS} Avg:${AVG_RX_MBPS} CPU:${CPU_USAGE}% RAM:${RAM_PERCENT}% Conn:${ACTIVE_CONN}"

        local now; now=$(date +%s)

        if ! notify_ddos "$domain" "$now" "$AVG_RX_MBPS"; then
            notify_normal "$domain" "$now" "$AVG_RX_MBPS"
        fi

        notify_cpu "$domain" "$now"
        notify_ram "$domain" "$now"
        notify_disk "$domain" "$now"
        notify_conn "$domain" "$now"
        notify_soc "$domain" "$now"
    done
}

# =============================================================================
# 📌 ENTRY POINT
# =============================================================================

case "${1:-start}" in
    start)
        main
        ;;
    bot-only)
        init_dirs
        log "Bot-only mode started"
        run_bot_listener
        ;;
    test-telegram)
        dom=$(get_domain)
        send_menu "$CHAT_ID" \
"${LINE}
🧪 <b>TEST KONEKSI BOT</b>
${LINE}
🖥 Server : ${dom}
📅 Waktu  : $(date '+%d/%m/%Y %H:%M:%S')
✅ Bot berfungsi dengan baik!

Gunakan menu di bawah:" \
"$KB_MAIN"
        echo "✅ Test berhasil. Cek Telegram Anda."
        ;;
    test-resources)
        echo "=== RESOURCE TEST ==="
        get_ram_usage; CPU_USAGE=$(get_cpu_usage); ACTIVE_CONN=$(get_active_connections)
        echo "CPU    : ${CPU_USAGE}%  (load: $(get_cpu_load))"
        echo "RAM    : ${RAM_PERCENT}%  (${RAM_USED_MB}/${RAM_TOTAL_MB} MB)"
        echo "Swap   : ${SWAP_USED_MB}/${SWAP_TOTAL_MB} MB"
        IFS=',' read -r ds du da dp <<< "$(get_disk_info)"
        echo "Disk   : ${dp}%  (${du}/${ds}, sisa ${da})"
        echo "Conn   : ${ACTIVE_CONN} aktif"
        echo ""; echo "Top CPU:"; get_top_cpu_procs
        echo ""; echo "Top RAM:"; get_top_ram_procs
        ;;
    test-soc)
        echo "=== SOC TEST ==="
        echo "Failed logins: $(get_failed_ssh_count)"
        echo ""; echo "Top failed IPs:"; get_top_failed_ips
        echo ""; echo "Brute force:"; get_brute_force_ips
        echo ""; echo "Active SSH:"; get_active_ssh
        rf=$(generate_soc_report)
        echo ""; echo "Report: $rf"
        ;;
    block)
        [ -z "$2" ] && echo "Usage: $0 block <IP>" && exit 1
        r=$(ip_block "$2")
        case "$r" in
            OK)        echo "✅ IP $2 diblokir" ;;
            EXISTS)    echo "ℹ️ IP $2 sudah diblokir" ;;
            INVALID)   echo "❌ Format IP tidak valid: $2" ;;
        esac
        ;;
    unblock)
        [ -z "$2" ] && echo "Usage: $0 unblock <IP>" && exit 1
        r=$(ip_unblock "$2")
        case "$r" in
            OK)        echo "✅ IP $2 di-unblock" ;;
            NOT_FOUND) echo "ℹ️ IP $2 tidak ditemukan di daftar block" ;;
        esac
        ;;
    listip)
        echo "=== IP BLOCKED LIST ==="
        ip_list
        echo "Total: $(ip_count) IP"
        ;;
    status)
        pgrep -f "monitor-server.sh start" >/dev/null 2>&1 && \
            echo "✅ Monitor RUNNING (PID: $(pgrep -f 'monitor-server.sh start'))" || \
            echo "❌ Monitor NOT running"
        ;;
    stop)
        pkill -f "monitor-server.sh start" 2>/dev/null && echo "⛔ Monitor dihentikan." || echo "Tidak ada proses yang berjalan."
        ;;
    *)
        cat <<USAGE
Penggunaan: $0 <perintah>

  start          Mulai monitoring + bot Telegram
  stop           Hentikan monitoring
  status         Cek status

  block <IP>     Blokir IP address
  unblock <IP>   Hapus blokir IP
  listip         Tampilkan daftar IP blocked

  test-telegram  Test koneksi Telegram + tampilkan menu
  test-resources Test monitoring CPU/RAM/Disk
  test-soc       Test analisis keamanan SOC
USAGE
        exit 1
        ;;
esac
