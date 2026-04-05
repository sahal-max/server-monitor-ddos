#!/bin/bash
# =============================================================================
# ADVANCED SERVER MONITOR & DDoS DETECTOR WITH SOC CREDENTIAL ANALYSIS
# Version: 2.0.0
# Description: Comprehensive server monitoring with Telegram notifications
# Features:
#   - Network monitoring (RX/TX Mbps) with DDoS detection
#   - CPU, RAM, Disk monitoring with alerts
#   - Active connection monitoring with top IPs/ports
#   - ASCII sparkline graphs for trends
#   - Top processes by CPU and RAM
#   - SOC credential analysis (failed logins, brute force, SSH sessions)
#   - Telegram notifications with formatted HTML messages
# =============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# =============================================================================
# KONFIGURASI — Sesuaikan sebelum dijalankan
# =============================================================================
THRESHOLD_MBPS=150            # Ambang batas DDoS dalam Mbps (integer)
THRESHOLD_CPU=85              # Ambang batas CPU (%)
THRESHOLD_RAM=90              # Ambang batas RAM (%)
THRESHOLD_DISK=90             # Ambang batas Disk (%)
THRESHOLD_CONN=5000           # Ambang batas koneksi aktif
THRESHOLD_FAILED_LOGIN=20     # Ambang batas failed login per 5 menit

INTERFACE="ens3"              # Interface jaringan (contoh: eth0, ens3, ens18)
SLEEP_INTERVAL=1              # Interval sampling (detik)
SAMPLE_COUNT=10               # Jumlah sampel untuk rata-rata network

TELEGRAM_TOKEN="7628118358:AAGmaZ5gziNQ_nO8CX5uMUuWkZ8IKrnIpt4"
CHAT_ID="-1002440680876"

LOG_FILE="/var/log/server-monitor.log"
REPORT_DIR="/var/log/soc-reports"
GRAPH_HISTORY=20              # Jumlah titik data untuk grafik sparkline

# Interval notifikasi (detik)
NOTIFY_INTERVAL_DDOS=10       # Notifikasi DDoS setiap 10 detik
NOTIFY_INTERVAL_NORMAL=1800   # Laporan normal setiap 30 menit
NOTIFY_INTERVAL_ALERT=300     # Alert CPU/RAM/Disk setiap 5 menit
NOTIFY_INTERVAL_SOC=600       # Laporan SOC setiap 10 menit

# =============================================================================
# STATE VARIABLES
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
declare -a CONN_HISTORY=()
declare -a NET_SAMPLES=()

CPU_USAGE="0.0"
RAM_PERCENT="0.0"
RAM_USED_MB=0
RAM_TOTAL_MB=0
RAM_AVAILABLE_MB=0
SWAP_USED_MB=0
SWAP_TOTAL_MB=0
RX_MBPS="0.00"
TX_MBPS="0.00"
AVG_RX_MBPS="0.00"
ACTIVE_CONN=0
CURR_RX_BYTES=0
CURR_TX_BYTES=0

# =============================================================================
# UTILITAS DASAR
# =============================================================================

log() {
    local msg="$1"
    local level="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg" >> "$LOG_FILE"
}

init_dirs() {
    mkdir -p "$REPORT_DIR"
    touch "$LOG_FILE" 2>/dev/null || { LOG_FILE="/tmp/server-monitor.log"; touch "$LOG_FILE"; }
    log "Server Monitor v2.0 started | interface=$INTERFACE"
}

get_domain() {
    if [ -f /etc/xray/domain ]; then
        cat /etc/xray/domain
    elif hostname -f &>/dev/null 2>&1; then
        hostname -f
    else
        hostname 2>/dev/null || echo "server"
    fi
}

# Perbandingan float menggunakan awk (pengganti bc)
float_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'
}

float_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 > b+0)}'
}

send_telegram() {
    local message="$1"
    local response

    response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${message}" \
        --data-urlencode "parse_mode=HTML" \
        --connect-timeout 10 \
        --max-time 20 2>/dev/null)

    if echo "$response" | grep -q '"ok":true'; then
        log "Telegram OK"
        return 0
    else
        log "Telegram FAIL: $(echo "$response" | head -c 200)" "ERROR"
        return 1
    fi
}

# =============================================================================
# MONITORING JARINGAN
# =============================================================================

get_rx_bytes() {
    awk '/'"$INTERFACE"':/{print $2}' /proc/net/dev 2>/dev/null || echo 0
}

get_tx_bytes() {
    awk '/'"$INTERFACE"':/{print $10}' /proc/net/dev 2>/dev/null || echo 0
}

calc_mbps() {
    local bytes=$1
    local interval=${2:-1}
    awk -v b="$bytes" -v i="$interval" 'BEGIN{printf "%.2f", (b*8)/(1000000*i)}'
}

get_network_stats() {
    local prev_rx=$1
    local prev_tx=$2
    local curr_rx curr_tx rx_diff tx_diff

    curr_rx=$(get_rx_bytes)
    curr_tx=$(get_tx_bytes)

    rx_diff=$((curr_rx - prev_rx))
    tx_diff=$((curr_tx - prev_tx))
    [ "$rx_diff" -lt 0 ] && rx_diff=0
    [ "$tx_diff" -lt 0 ] && tx_diff=0

    RX_MBPS=$(calc_mbps "$rx_diff" "$SLEEP_INTERVAL")
    TX_MBPS=$(calc_mbps "$tx_diff" "$SLEEP_INTERVAL")
    CURR_RX_BYTES=$curr_rx
    CURR_TX_BYTES=$curr_tx
}

update_net_samples() {
    NET_SAMPLES+=("$RX_MBPS")
    if [ "${#NET_SAMPLES[@]}" -gt "$SAMPLE_COUNT" ]; then
        NET_SAMPLES=("${NET_SAMPLES[@]:1}")
    fi
}

get_avg_rx() {
    local count=${#NET_SAMPLES[@]}
    [ "$count" -eq 0 ] && echo "0.00" && return

    local vals=""
    for s in "${NET_SAMPLES[@]}"; do
        vals="$vals $s"
    done

    awk -v vals="$vals" -v n="$count" 'BEGIN{
        split(vals,a," ")
        t=0; for(i in a) t+=a[i]
        printf "%.2f", t/n
    }'
}

# =============================================================================
# MONITORING CPU
# =============================================================================

get_cpu_usage() {
    if [ ! -f /proc/stat ]; then
        echo "0.0"; return
    fi

    local snap1 snap2
    snap1=$(awk 'NR==1{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)
    sleep 0.5
    snap2=$(awk 'NR==1{print $2,$3,$4,$5,$6,$7,$8}' /proc/stat)

    awk -v s1="$snap1" -v s2="$snap2" 'BEGIN{
        n=split(s1,a," "); split(s2,b," ")
        t1=0; t2=0
        for(i=1;i<=n;i++){t1+=a[i]; t2+=b[i]}
        di=b[4]-a[4]; dt=t2-t1
        if(dt>0) printf "%.1f",(dt-di)*100/dt
        else print "0.0"
    }'
}

get_cpu_load() {
    uptime 2>/dev/null | awk -F'load average:' '{gsub(/,/,"",$2); print $2}' | xargs || echo "0 0 0"
}

get_top_cpu_processes() {
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6{
        cmd=$11; if(length(cmd)>28) cmd=substr(cmd,1,25)"..."
        printf "%-8s %5s%%  %-28s\n",$1,$3,cmd
    }' 2>/dev/null || echo "N/A"
}

# =============================================================================
# MONITORING RAM
# =============================================================================

get_ram_usage() {
    local total avail used

    total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 1)
    avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    used=$((total - avail))

    RAM_TOTAL_MB=$((total / 1024))
    RAM_USED_MB=$((used / 1024))
    RAM_AVAILABLE_MB=$((avail / 1024))
    RAM_PERCENT=$(awk -v u="$used" -v t="$total" 'BEGIN{
        if(t>0) printf "%.1f",u*100/t; else print "0.0"
    }')

    local swap_total swap_free
    swap_total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    swap_free=$(awk '/^SwapFree:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
    SWAP_USED_MB=$(( (swap_total - swap_free) / 1024 ))
    SWAP_TOTAL_MB=$((swap_total / 1024))
}

get_top_ram_processes() {
    ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=6{
        cmd=$11; if(length(cmd)>28) cmd=substr(cmd,1,25)"..."
        printf "%-8s %5s%%  %-28s\n",$1,$4,cmd
    }' 2>/dev/null || echo "N/A"
}

# =============================================================================
# MONITORING DISK
# =============================================================================

get_disk_info() {
    df -h / 2>/dev/null | awk 'NR==2{
        gsub(/%/,"",$5)
        print $2","$3","$4","$5
    }' || echo "N/A,N/A,N/A,0"
}

get_biggest_dirs() {
    du -sh /var /home /tmp /usr /opt 2>/dev/null | sort -rh | head -5 | \
    awk '{printf "  %-8s %s\n",$1,$2}' || echo "  N/A"
}

# =============================================================================
# MONITORING KONEKSI
# =============================================================================

get_active_connections() {
    local count=0
    if command -v ss &>/dev/null; then
        count=$(ss -tan 2>/dev/null | awk 'NR>1 && $1=="ESTAB"' | wc -l)
    elif command -v netstat &>/dev/null; then
        count=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
    fi
    echo "${count:-0}"
}

get_connection_states() {
    if command -v ss &>/dev/null; then
        ss -tan 2>/dev/null | awk 'NR>1{states[$1]++}
        END{for(s in states) printf "%s:%d\n",s,states[s]}' | \
        sort -t: -k2 -rn | head -5 | awk '{printf "  %-12s %s\n",$1,$2}' FS=':'
    fi
}

get_top_ips() {
    if command -v ss &>/dev/null; then
        ss -tan 2>/dev/null | awk 'NR>1 && $1=="ESTAB"{
            n=split($5,a,":")
            ip=(n>=4) ? a[1]":"a[2]":"a[3]":"a[4] : a[1]
            count[ip]++
        }END{for(ip in count) print count[ip],ip}' | \
        sort -rn | head -5 | awk '{printf "  %-6s %s\n",$1,$2}'
    fi
}

get_top_ports() {
    if command -v ss &>/dev/null; then
        ss -tan 2>/dev/null | awk 'NR>1 && $1=="ESTAB"{
            n=split($4,a,":"); port=a[n]; count[port]++
        }END{for(p in count) print count[p],p}' | \
        sort -rn | head -5 | awk '{printf "  %-6s port %s\n",$1,$2}'
    fi
}

# =============================================================================
# SOC - ANALISIS KEAMANAN DAN LOG CREDENTIAL
# =============================================================================

find_auth_log() {
    for f in /var/log/auth.log /var/log/secure /var/log/messages; do
        [ -f "$f" ] && echo "$f" && return
    done
    echo ""
}

get_failed_ssh_count() {
    local logfile
    logfile=$(find_auth_log)
    [ -z "$logfile" ] && echo 0 && return

    grep -c "Failed password\|Invalid user\|authentication failure" "$logfile" 2>/dev/null || echo 0
}

get_top_failed_ips() {
    local logfile
    logfile=$(find_auth_log)
    [ -z "$logfile" ] && echo "  (auth log tidak ditemukan)" && return

    grep -i "Failed password\|Invalid user" "$logfile" 2>/dev/null | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
    sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  %-6s %s\n",$1,$2}' || echo "  Tidak ada"
}

get_brute_force_ips() {
    local logfile
    logfile=$(find_auth_log)
    [ -z "$logfile" ] && echo "  (auth log tidak ditemukan)" && return

    local result
    result=$(grep -i "Failed password" "$logfile" 2>/dev/null | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
    sort | uniq -c | sort -rn | awk '$1>=10{printf "  %-6s %s (%d percobaan)\n",$1,$2,$1}' | head -5)

    echo "${result:-  Tidak ada}"
}

get_successful_logins() {
    local logfile
    logfile=$(find_auth_log)
    [ -z "$logfile" ] && echo "  (auth log tidak ditemukan)" && return

    grep -i "Accepted password\|Accepted publickey" "$logfile" 2>/dev/null | \
    tail -5 | awk '{
        for(i=1;i<=NF;i++){
            if($i=="user") user=$(i+1)
            if($i=="from") ip=$(i+1)
        }
        printf "  %-12s dari %s\n", user, ip
    }' || echo "  Tidak ada"
}

get_active_ssh_sessions() {
    local sessions
    sessions=$(who 2>/dev/null | awk '{print "  "$1,$5}')
    echo "${sessions:-  Tidak ada sesi aktif}"
}

get_sudo_events() {
    local logfile
    logfile=$(find_auth_log)
    [ -z "$logfile" ] && echo "  (auth log tidak ditemukan)" && return

    grep "sudo:" "$logfile" 2>/dev/null | tail -5 | \
    awk '{
        user=""; cmd=""
        for(i=1;i<=NF;i++){
            if($i ~ /USER=/) user=substr($i,6)
            if($i ~ /COMMAND=/) {cmd=substr($i,9); break}
        }
        if(user) printf "  %-12s -> %s\n",user,substr(cmd,1,40)
    }' || echo "  Tidak ada"
}

get_port_scan_count() {
    local count=0
    for f in /var/log/syslog /var/log/messages /var/log/kern.log; do
        if [ -f "$f" ]; then
            count=$(grep -ci "port scan\|SCAN\|SYN flood\|nmap\|masscan" "$f" 2>/dev/null || echo 0)
            break
        fi
    done
    echo "$count"
}

generate_soc_report() {
    local ts
    ts=$(date '+%Y-%m-%d_%H-%M-%S')
    local rfile="${REPORT_DIR}/soc_${ts}.txt"

    {
        echo "══════════════════════════════════════════════════"
        echo "   SOC SECURITY & CREDENTIAL ANALYSIS REPORT"
        echo "   Host   : $(get_domain)"
        echo "   Time   : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "══════════════════════════════════════════════════"
        printf "\n[FAILED LOGIN ATTEMPTS - 5min]\n"
        echo "  Total: $(get_failed_ssh_count)"
        printf "\n[TOP ATTACKER IPs]\n"
        get_top_failed_ips
        printf "\n[BRUTE FORCE (>=10 attempts)]\n"
        get_brute_force_ips
        printf "\n[SUCCESSFUL LOGINS]\n"
        get_successful_logins
        printf "\n[ACTIVE SSH SESSIONS]\n"
        get_active_ssh_sessions
        printf "\n[SUDO EVENTS]\n"
        get_sudo_events
        printf "\n[PORT SCAN ATTEMPTS]\n"
        echo "  Count: $(get_port_scan_count)"
        printf "\n[CONNECTION STATES]\n"
        get_connection_states
        printf "\n[TOP CONNECTED IPs]\n"
        get_top_ips
        echo ""
        echo "══════════════════════════════════════════════════"
    } > "$rfile"

    echo "$rfile"
}

# =============================================================================
# GRAFIK ASCII (SPARKLINE)
# =============================================================================

make_bar() {
    local value=$1
    local max=${2:-100}
    local width=${3:-20}

    awk -v v="$value" -v m="$max" -v w="$width" 'BEGIN{
        filled=int(v*w/m)
        if(filled>w) filled=w
        bar=""
        for(i=0;i<filled;i++) bar=bar"█"
        for(i=filled;i<w;i++) bar=bar"░"
        print bar
    }'
}

make_sparkline() {
    local -a arr=("$@")
    [ ${#arr[@]} -eq 0 ] && echo "▁▁▁▁▁" && return

    local vals=""
    for v in "${arr[@]}"; do vals="$vals $v"; done

    awk -v vals="$vals" 'BEGIN{
        n=split(vals,a," ")
        chars[0]="▁"; chars[1]="▂"; chars[2]="▃"; chars[3]="▄"
        chars[4]="▅"; chars[5]="▆"; chars[6]="▇"; chars[7]="█"
        mx=0
        for(i=1;i<=n;i++) if(a[i]+0>mx) mx=a[i]+0
        if(mx==0) mx=1
        line=""
        for(i=1;i<=n;i++){
            idx=int(a[i]*7/mx)
            if(idx>7) idx=7
            if(idx<0) idx=0
            line=line chars[idx]
        }
        print line
    }'
}

update_history() {
    local net_int cpu_int ram_int
    net_int=$(awk -v v="$AVG_RX_MBPS" 'BEGIN{printf "%d",v+0}')
    cpu_int=$(awk -v v="$CPU_USAGE" 'BEGIN{printf "%d",v+0}')
    ram_int=$(awk -v v="$RAM_PERCENT" 'BEGIN{printf "%d",v+0}')

    NET_HISTORY+=("$net_int")
    CPU_HISTORY+=("$cpu_int")
    RAM_HISTORY+=("$ram_int")
    CONN_HISTORY+=("$ACTIVE_CONN")

    [ "${#NET_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && NET_HISTORY=("${NET_HISTORY[@]:1}")
    [ "${#CPU_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && CPU_HISTORY=("${CPU_HISTORY[@]:1}")
    [ "${#RAM_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && RAM_HISTORY=("${RAM_HISTORY[@]:1}")
    [ "${#CONN_HISTORY[@]}" -gt "$GRAPH_HISTORY" ] && CONN_HISTORY=("${CONN_HISTORY[@]:1}")
}

status_icon() {
    local val=$1
    local hi=$2
    local warn
    warn=$(awk -v h="$hi" 'BEGIN{printf "%d",h*0.75}')

    if float_ge "$val" "$hi"; then
        echo "🔴"
    elif float_ge "$val" "$warn"; then
        echo "🟡"
    else
        echo "🟢"
    fi
}

# =============================================================================
# PESAN TELEGRAM
# =============================================================================

msg_ddos_alert() {
    local domain="$1"
    local avg_rx="$2"
    local net_spark="$3"
    cat <<MSG
━━━━━━━━━━━━━━━━━━━━━━━━━
🚨 <b>DDOS ATTACK DETECTED</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Domain :</b> ${domain}
🕐 <b>Waktu  :</b> $(date '+%Y-%m-%d %H:%M:%S')

📊 <b>Trafik Jaringan</b>
├ ⬇ RX Avg : <b>${avg_rx} Mb/s</b>
├ ⬇ RX Now : ${RX_MBPS} Mb/s
├ ⬆ TX Now : ${TX_MBPS} Mb/s
└ 🔗 Koneksi: <b>${ACTIVE_CONN}</b>

📈 <b>Tren (${GRAPH_HISTORY}s):</b> <code>${net_spark}</code>
⚡ <b>Ambang :</b> ${THRESHOLD_MBPS} Mb/s

━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ <b>Tindakan yang disarankan:</b>
• Periksa dan blokir IP penyerang
• Aktifkan rate limiting di firewall
• Hubungi provider upstream
━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

msg_status_report() {
    local domain="$1"
    local avg_rx="$2"

    local disk_info disk_size disk_used disk_avail disk_pct
    disk_info=$(get_disk_info)
    IFS=',' read -r disk_size disk_used disk_avail disk_pct <<< "$disk_info"

    local net_icon cpu_icon ram_icon disk_icon conn_icon
    net_icon=$(status_icon "${AVG_RX_MBPS%.*}" "$THRESHOLD_MBPS")
    cpu_icon=$(status_icon "${CPU_USAGE%.*}" "$THRESHOLD_CPU")
    ram_icon=$(status_icon "${RAM_PERCENT%.*}" "$THRESHOLD_RAM")
    disk_icon=$(status_icon "${disk_pct:-0}" "$THRESHOLD_DISK")
    conn_icon=$(status_icon "$ACTIVE_CONN" "$THRESHOLD_CONN")

    local net_spark cpu_spark ram_spark
    net_spark=$(make_sparkline "${NET_HISTORY[@]}")
    cpu_spark=$(make_sparkline "${CPU_HISTORY[@]}")
    ram_spark=$(make_sparkline "${RAM_HISTORY[@]}")

    local cpu_bar ram_bar disk_bar
    cpu_bar=$(make_bar "${CPU_USAGE%.*}" 100 18)
    ram_bar=$(make_bar "${RAM_PERCENT%.*}" 100 18)
    disk_bar=$(make_bar "${disk_pct:-0}" 100 18)

    local load
    load=$(get_cpu_load)

    cat <<MSG
━━━━━━━━━━━━━━━━━━━━━━━━━
📡 <b>SERVER STATUS REPORT</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Domain :</b> ${domain}
🕐 <b>Waktu  :</b> $(date '+%Y-%m-%d %H:%M:%S')
⏱ <b>Uptime :</b> $(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | cut -d',' -f1-2)

━━━ 🌐 JARINGAN ━━━━━━━━━
${net_icon} RX avg : <b>${avg_rx} Mb/s</b>  TX: ${TX_MBPS} Mb/s
📈 Tren : <code>${net_spark}</code>

━━━ 💻 CPU ━━━━━━━━━━━━━━
${cpu_icon} Pakai : <b>${CPU_USAGE}%</b>  Load: ${load}
<code>${cpu_bar}</code> ${CPU_USAGE}%
📈 Tren: <code>${cpu_spark}</code>

━━━ 🧠 RAM ━━━━━━━━━━━━━━
${ram_icon} Pakai : <b>${RAM_PERCENT}%</b>  (${RAM_USED_MB}/${RAM_TOTAL_MB} MB)
<code>${ram_bar}</code> ${RAM_PERCENT}%
🔄 Swap: ${SWAP_USED_MB}/${SWAP_TOTAL_MB} MB
📈 Tren: <code>${ram_spark}</code>

━━━ 💿 DISK ━━━━━━━━━━━━━
${disk_icon} Pakai : <b>${disk_pct}%</b>  (${disk_used}/${disk_size}, sisa ${disk_avail})
<code>${disk_bar}</code> ${disk_pct}%

━━━ 🔗 KONEKSI ━━━━━━━━━━
${conn_icon} Aktif : <b>${ACTIVE_CONN}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
✅ <b>Status: NORMAL</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

msg_top_processes() {
    local domain="$1"
    local top_cpu top_ram
    top_cpu=$(get_top_cpu_processes)
    top_ram=$(get_top_ram_processes)

    cat <<MSG
━━━━━━━━━━━━━━━━━━━━━━━━━
🔬 <b>TOP PROSES SERVER</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Domain:</b> ${domain}
🕐 <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')

💻 <b>CPU (Top 5):</b>
<code>USER      CPU%    COMMAND
${top_cpu}</code>

🧠 <b>RAM (Top 5):</b>
<code>USER      MEM%    COMMAND
${top_ram}</code>
━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

msg_resource_alert() {
    local domain="$1"
    local alert_type="$2"
    local value="$3"
    local threshold="$4"
    local detail="$5"

    cat <<MSG
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ <b>ALERT: ${alert_type}</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Domain    :</b> ${domain}
🕐 <b>Waktu     :</b> $(date '+%Y-%m-%d %H:%M:%S')
📊 <b>Nilai     :</b> <b>${value}</b>
⚡ <b>Threshold :</b> ${threshold}

${detail}
━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ <b>Segera periksa server!</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

msg_soc_report() {
    local domain="$1"
    local failed_count="$2"

    local threat_level="✅ RENDAH"
    if [ "${failed_count:-0}" -ge "$THRESHOLD_FAILED_LOGIN" ]; then
        threat_level="🔴 TINGGI"
    elif [ "${failed_count:-0}" -ge $((THRESHOLD_FAILED_LOGIN / 2)) ]; then
        threat_level="🟡 SEDANG"
    fi

    local top_failed brute_ips active_sess port_scans
    top_failed=$(get_top_failed_ips)
    brute_ips=$(get_brute_force_ips)
    active_sess=$(get_active_ssh_sessions)
    port_scans=$(get_port_scan_count)

    cat <<MSG
━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ <b>SOC CREDENTIAL REPORT</b>
━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 <b>Domain:</b> ${domain}
🕐 <b>Waktu:</b> $(date '+%Y-%m-%d %H:%M:%S')
🚦 <b>Level Ancaman:</b> ${threat_level}

🔐 <b>LOGIN GAGAL (5 menit):</b>
  Jumlah: <b>${failed_count}</b>

📍 <b>TOP IP PENYERANG:</b>
<code>${top_failed}</code>

🚫 <b>BRUTE FORCE (≥10 attempt):</b>
<code>${brute_ips}</code>

👥 <b>SESI SSH AKTIF:</b>
<code>${active_sess}</code>

🔍 <b>PORT SCAN TERDETEKSI:</b> ${port_scans}
━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

# =============================================================================
# CEK DAN KIRIM NOTIFIKASI
# =============================================================================

notify_ddos() {
    local domain="$1"
    local current_time="$2"
    local avg_rx="$3"

    if float_gt "$avg_rx" "$THRESHOLD_MBPS"; then
        if (( current_time - LAST_NOTIFY_DDOS >= NOTIFY_INTERVAL_DDOS )); then
            log "DDoS detected: avg_rx=${avg_rx} Mbps threshold=${THRESHOLD_MBPS} Mbps" "WARN"
            local net_spark
            net_spark=$(make_sparkline "${NET_HISTORY[@]}")
            local msg
            msg=$(msg_ddos_alert "$domain" "$avg_rx" "$net_spark")
            send_telegram "$msg" && LAST_NOTIFY_DDOS=$current_time
        fi
        return 0
    fi
    return 1
}

notify_normal() {
    local domain="$1"
    local current_time="$2"
    local avg_rx="$3"

    if (( current_time - LAST_NOTIFY_NORMAL >= NOTIFY_INTERVAL_NORMAL )); then
        log "Normal status report: avg_rx=${avg_rx} Mbps"
        local msg
        msg=$(msg_status_report "$domain" "$avg_rx")
        send_telegram "$msg" && LAST_NOTIFY_NORMAL=$current_time

        local proc_msg
        proc_msg=$(msg_top_processes "$domain")
        send_telegram "$proc_msg"
    fi
}

notify_cpu_alert() {
    local domain="$1"
    local current_time="$2"

    if float_ge "$CPU_USAGE" "$THRESHOLD_CPU"; then
        if (( current_time - LAST_NOTIFY_CPU >= NOTIFY_INTERVAL_ALERT )); then
            log "CPU alert: ${CPU_USAGE}% >= ${THRESHOLD_CPU}%" "WARN"
            local top_procs
            top_procs=$(get_top_cpu_processes)
            local detail
            detail="💻 <b>Top Proses CPU:</b>
<code>USER      CPU%    COMMAND
${top_procs}</code>"
            local msg
            msg=$(msg_resource_alert "$domain" "CPU TINGGI" "${CPU_USAGE}%" "${THRESHOLD_CPU}%" "$detail")
            send_telegram "$msg" && LAST_NOTIFY_CPU=$current_time
        fi
    fi
}

notify_ram_alert() {
    local domain="$1"
    local current_time="$2"

    if float_ge "$RAM_PERCENT" "$THRESHOLD_RAM"; then
        if (( current_time - LAST_NOTIFY_RAM >= NOTIFY_INTERVAL_ALERT )); then
            log "RAM alert: ${RAM_PERCENT}% >= ${THRESHOLD_RAM}%" "WARN"
            local top_procs
            top_procs=$(get_top_ram_processes)
            local detail
            detail="🧠 <b>Top Proses RAM:</b>
<code>USER      MEM%    COMMAND
${top_procs}</code>
🔄 Swap: ${SWAP_USED_MB}/${SWAP_TOTAL_MB} MB"
            local msg
            msg=$(msg_resource_alert "$domain" "RAM TINGGI" "${RAM_PERCENT}%" "${THRESHOLD_RAM}%" "$detail")
            send_telegram "$msg" && LAST_NOTIFY_RAM=$current_time
        fi
    fi
}

notify_disk_alert() {
    local domain="$1"
    local current_time="$2"

    local disk_info disk_size disk_used disk_avail disk_pct
    disk_info=$(get_disk_info)
    IFS=',' read -r disk_size disk_used disk_avail disk_pct <<< "$disk_info"

    if [ -n "$disk_pct" ] && float_ge "$disk_pct" "$THRESHOLD_DISK"; then
        if (( current_time - LAST_NOTIFY_DISK >= NOTIFY_INTERVAL_ALERT )); then
            log "Disk alert: ${disk_pct}% >= ${THRESHOLD_DISK}%" "WARN"
            local big_dirs
            big_dirs=$(get_biggest_dirs)
            local detail
            detail="💿 ${disk_used} dipakai dari ${disk_size} (sisa ${disk_avail})

📂 <b>Direktori Terbesar:</b>
<code>${big_dirs}</code>"
            local msg
            msg=$(msg_resource_alert "$domain" "DISK HAMPIR PENUH" "${disk_pct}%" "${THRESHOLD_DISK}%" "$detail")
            send_telegram "$msg" && LAST_NOTIFY_DISK=$current_time
        fi
    fi
}

notify_conn_alert() {
    local domain="$1"
    local current_time="$2"

    if (( ACTIVE_CONN >= THRESHOLD_CONN )); then
        if (( current_time - LAST_NOTIFY_CONN >= NOTIFY_INTERVAL_ALERT )); then
            log "Connection alert: ${ACTIVE_CONN} >= ${THRESHOLD_CONN}" "WARN"
            local top_ips top_ports conn_states
            top_ips=$(get_top_ips)
            top_ports=$(get_top_ports)
            conn_states=$(get_connection_states)
            local detail
            detail="🔗 <b>State Koneksi:</b>
<code>${conn_states}</code>

📍 <b>Top IP:</b>
<code>${top_ips}</code>

🔌 <b>Top Port:</b>
<code>${top_ports}</code>"
            local msg
            msg=$(msg_resource_alert "$domain" "KONEKSI BERLEBIHAN" "$ACTIVE_CONN" "$THRESHOLD_CONN" "$detail")
            send_telegram "$msg" && LAST_NOTIFY_CONN=$current_time
        fi
    fi
}

notify_soc() {
    local domain="$1"
    local current_time="$2"

    if (( current_time - LAST_NOTIFY_SOC >= NOTIFY_INTERVAL_SOC )); then
        local failed_count
        failed_count=$(get_failed_ssh_count)
        log "SOC check: failed_logins=$failed_count"

        local rfile
        rfile=$(generate_soc_report)
        log "SOC report saved: $rfile"

        local msg
        msg=$(msg_soc_report "$domain" "$failed_count")
        send_telegram "$msg" && LAST_NOTIFY_SOC=$current_time
    fi
}

# =============================================================================
# MAIN LOOP
# =============================================================================

main() {
    init_dirs

    local domain
    domain=$(get_domain)
    log "Starting monitor | domain=$domain | iface=$INTERFACE | thresholds: net=${THRESHOLD_MBPS}Mbps cpu=${THRESHOLD_CPU}% ram=${THRESHOLD_RAM}% disk=${THRESHOLD_DISK}%"

    local prev_rx prev_tx
    prev_rx=$(get_rx_bytes)
    prev_tx=$(get_tx_bytes)

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

        log "RX:${RX_MBPS} TX:${TX_MBPS} AvgRX:${AVG_RX_MBPS} CPU:${CPU_USAGE}% RAM:${RAM_PERCENT}% Conn:${ACTIVE_CONN}"

        local now
        now=$(date +%s)

        if ! notify_ddos "$domain" "$now" "$AVG_RX_MBPS"; then
            notify_normal "$domain" "$now" "$AVG_RX_MBPS"
        fi

        notify_cpu_alert "$domain" "$now"
        notify_ram_alert "$domain" "$now"
        notify_disk_alert "$domain" "$now"
        notify_conn_alert "$domain" "$now"
        notify_soc "$domain" "$now"
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================

case "${1:-start}" in
    start)
        main
        ;;

    test-telegram)
        domain=$(get_domain)
        echo "Mengirim test notifikasi ke Telegram..."
        send_telegram "🧪 <b>TEST NOTIFIKASI</b>
🌐 Domain: ${domain}
🕐 Waktu: $(date '+%Y-%m-%d %H:%M:%S')
✅ Script monitor aktif dan siap berjalan"
        echo "Selesai. Cek Telegram Anda."
        ;;

    test-soc)
        echo "=== SOC CREDENTIAL ANALYSIS TEST ==="
        echo ""
        echo "Failed login count: $(get_failed_ssh_count)"
        echo ""
        echo "Top failed IPs:"
        get_top_failed_ips
        echo ""
        echo "Brute force IPs (>=10 attempts):"
        get_brute_force_ips
        echo ""
        echo "Active SSH sessions:"
        get_active_ssh_sessions
        echo ""
        echo "Sudo events:"
        get_sudo_events
        echo ""
        echo "Port scan count: $(get_port_scan_count)"
        echo ""
        rfile=$(generate_soc_report)
        echo "Full report saved to: $rfile"
        ;;

    test-resources)
        echo "=== RESOURCE MONITORING TEST ==="
        get_ram_usage
        CPU_USAGE=$(get_cpu_usage)
        ACTIVE_CONN=$(get_active_connections)
        echo ""
        echo "CPU    : ${CPU_USAGE}%  (load: $(get_cpu_load))"
        echo "RAM    : ${RAM_PERCENT}%  (${RAM_USED_MB}MB used / ${RAM_TOTAL_MB}MB total)"
        echo "Swap   : ${SWAP_USED_MB}MB / ${SWAP_TOTAL_MB}MB"
        echo "Disk   : $(get_disk_info | tr ',' ' ' | awk '{print $4"%  ("$2"used/"$1"total, "$3" avail)"}')"
        echo "Conn   : ${ACTIVE_CONN} active"
        echo ""
        echo "Top CPU processes:"
        get_top_cpu_processes
        echo ""
        echo "Top RAM processes:"
        get_top_ram_processes
        echo ""
        echo "Connection states:"
        get_connection_states
        echo ""
        echo "Top IPs:"
        get_top_ips
        ;;

    test-network)
        echo "=== NETWORK MONITORING TEST ==="
        INTERFACE="${2:-$INTERFACE}"
        echo "Interface: $INTERFACE"
        prev_rx=$(get_rx_bytes)
        prev_tx=$(get_tx_bytes)
        sleep 2
        get_network_stats "$prev_rx" "$prev_tx"
        echo "RX: ${RX_MBPS} Mb/s"
        echo "TX: ${TX_MBPS} Mb/s"
        ;;

    test-graphs)
        echo "=== GRAFIK ASCII TEST ==="
        declare -a test_vals=(10 25 40 55 70 85 60 45 30 80 90 75 50 35 65 55 45 70 80 60)
        echo "Test sparkline:"
        make_sparkline "${test_vals[@]}"
        echo ""
        echo "Test bar 65%:"
        make_bar 65 100 20
        echo ""
        echo "Test bar 30%:"
        make_bar 30 100 20
        ;;

    status)
        if pgrep -f "monitor-server.sh start" > /dev/null 2>&1; then
            echo "Monitor status: RUNNING"
            echo "PID: $(pgrep -f "monitor-server.sh start")"
        else
            echo "Monitor status: NOT RUNNING"
        fi
        ;;

    stop)
        if pgrep -f "monitor-server.sh start" > /dev/null 2>&1; then
            pkill -f "monitor-server.sh start"
            echo "Monitor dihentikan."
        else
            echo "Monitor tidak sedang berjalan."
        fi
        ;;

    *)
        cat <<USAGE
Penggunaan: $0 <perintah>

Perintah:
  start            Mulai monitoring (mode daemon)
  stop             Hentikan monitoring
  status           Cek status monitoring

  test-telegram    Test kirim notifikasi ke Telegram
  test-soc         Test analisis log keamanan/credential
  test-resources   Test monitoring CPU, RAM, disk, koneksi
  test-network     Test monitoring jaringan
  test-graphs      Test grafik ASCII sparkline

Contoh:
  $0 start
  $0 test-telegram
  $0 test-resources
USAGE
        exit 1
        ;;
esac
