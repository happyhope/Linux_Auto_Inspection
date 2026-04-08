#!/bin/bash
###############################################################################
# Linux 服务器巡检脚本 v2.0
# 功能：一键采集系统关键指标，生成 HTML 巡检报告
# 适用：CentOS 7/8, RHEL, Ubuntu, Debian 等主流发行版
# 用法：chmod +x linux_inspect.sh && ./linux_inspect.sh
# 作者：运维团队
# 日期：2026-04-08
###############################################################################

set -euo pipefail

# ======================== 配置区 ========================
REPORT_DIR="/tmp/inspect_report"
REPORT_FILE="${REPORT_DIR}/inspect_$(hostname)_$(date +%Y%m%d_%H%M%S).html"
# 阈值设置
CPU_WARN=80          # CPU 使用率告警阈值(%)
MEM_WARN=85          # 内存使用率告警阈值(%)
DISK_WARN=85         # 磁盘使用率告警阈值(%)
INODE_WARN=85        # Inode 使用率告警阈值(%)
SWAP_WARN=50         # Swap 使用率告警阈值(%)
LOAD_WARN_FACTOR=2   # 负载告警倍数(相对于CPU核数)
ZOMBIE_WARN=0        # 僵尸进程告警阈值
FD_WARN=80           # 文件描述符使用率告警阈值(%)
LOG_LINES=20         # 日志检查行数
LARGE_FILE_SIZE="+100M"  # 大文件阈值
# ========================================================

mkdir -p "$REPORT_DIR"

# 颜色定义(终端输出用)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 计数器
WARN_COUNT=0
CRITICAL_COUNT=0

# ======================== 工具函数 ========================
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN_COUNT++)) || true; }
log_error() { echo -e "${RED}[CRITICAL]${NC} $1"; ((CRITICAL_COUNT++)) || true; }

status_badge() {
    local val=${1:-0} warn=${2:-80}
    local critical=$((warn + 10))
    if (( val >= critical )); then
        echo '<span class="badge critical">严重</span>'
    elif (( val >= warn )); then
        echo '<span class="badge warning">警告</span>'
    else
        echo '<span class="badge ok">正常</span>'
    fi
}

get_color_class() {
    local val=${1:-0} warn=${2:-80}
    if (( val >= warn + 10 )); then echo "red"
    elif (( val >= warn )); then echo "orange"
    else echo "green"
    fi
}

# 字节转可读
human_bytes() {
    local bytes=${1:-0}
    if (( bytes >= 1073741824 )); then
        awk "BEGIN{printf \"%.1fG\", $bytes/1073741824}"
    elif (( bytes >= 1048576 )); then
        awk "BEGIN{printf \"%.1fM\", $bytes/1048576}"
    elif (( bytes >= 1024 )); then
        awk "BEGIN{printf \"%.1fK\", $bytes/1024}"
    else
        echo "${bytes}B"
    fi
}

# HTML 转义
html_escape() {
    local str="${1:-}"
    str="${str//&/&amp;}"
    str="${str//</&lt;}"
    str="${str//>/&gt;}"
    str="${str//\"/&quot;}"
    echo "$str"
}

# ======================== HTML 报告头 ========================
cat > "$REPORT_FILE" <<'HEADER'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Linux 服务器巡检报告</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, "Microsoft YaHei", sans-serif; background: #f0f2f5; color: #333; line-height: 1.6; }
  .container { max-width: 960px; margin: 20px auto; padding: 0 16px; }
  .header { background: linear-gradient(135deg, #1a73e8, #0d47a1); color: #fff; padding: 30px; border-radius: 12px; margin-bottom: 20px; text-align: center; }
  .header h1 { font-size: 24px; margin-bottom: 8px; }
  .header p { opacity: 0.9; font-size: 14px; }
  .summary { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; }
  .summary-card { flex: 1; min-width: 120px; background: #fff; border-radius: 10px; padding: 16px; text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
  .summary-card .num { font-size: 26px; font-weight: bold; }
  .summary-card .label { font-size: 12px; color: #888; margin-top: 4px; }
  .num.green { color: #52c41a; }
  .num.orange { color: #fa8c16; }
  .num.red { color: #f5222d; }
  .section { background: #fff; border-radius: 10px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }
  .section h2 { font-size: 17px; color: #1a73e8; border-left: 4px solid #1a73e8; padding-left: 10px; margin-bottom: 14px; }
  .section h3 { font-size: 14px; color: #666; margin: 14px 0 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { background: #fafafa; text-align: left; padding: 8px 10px; border-bottom: 2px solid #e8e8e8; white-space: nowrap; }
  td { padding: 8px 10px; border-bottom: 1px solid #f0f0f0; word-break: break-all; }
  tr:hover { background: #f9fbff; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
  .badge.ok { background: #f6ffed; color: #52c41a; }
  .badge.warning { background: #fff7e6; color: #fa8c16; }
  .badge.critical { background: #fff1f0; color: #f5222d; }
  .badge.info { background: #e6f7ff; color: #1890ff; }
  .info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 8px; }
  .info-item { display: flex; padding: 6px 0; border-bottom: 1px dashed #f0f0f0; }
  .info-item .key { color: #888; min-width: 130px; font-size: 13px; }
  .info-item .val { font-weight: 500; font-size: 13px; }
  pre { background: #f5f5f5; padding: 12px; border-radius: 6px; font-size: 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; max-height: 300px; overflow-y: auto; }
  .progress-bar { background: #f0f0f0; border-radius: 10px; height: 8px; overflow: hidden; display: inline-block; width: 100px; vertical-align: middle; }
  .progress-fill { height: 100%; border-radius: 10px; }
  .fill-ok { background: #52c41a; }
  .fill-warn { background: #fa8c16; }
  .fill-crit { background: #f5222d; }
  .footer { text-align: center; color: #aaa; font-size: 12px; padding: 20px 0; }
  .two-col { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  @media (max-width: 768px) { .two-col { grid-template-columns: 1fr; } }
  .mini-card { background: #fafafa; border-radius: 8px; padding: 14px; }
  .mini-card h4 { font-size: 13px; color: #666; margin-bottom: 8px; }
  .tag-list { display: flex; flex-wrap: wrap; gap: 6px; }
  .tag { display: inline-block; background: #f0f0f0; padding: 2px 8px; border-radius: 3px; font-size: 12px; color: #555; }
</style>
</head>
<body>
<div class="container">
HEADER

# ======================== 基本信息采集 ========================
log_info "开始巡检: $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"

HOSTNAME_VAL=$(hostname)
HOSTNAME_FQDN=$(hostname -f 2>/dev/null || echo "$HOSTNAME_VAL")
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
IP_ALL=$(hostname -I 2>/dev/null | xargs || echo "N/A")
OS_VERSION=$(grep "PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)
KERNEL=$(uname -r)
ARCH=$(uname -m)
UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')
UPTIME_DAYS=$(awk '{printf "%.0f", $1/86400}' /proc/uptime 2>/dev/null || echo "N/A")
CPU_MODEL=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "N/A")
CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "N/A")
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l || echo "N/A")
MEM_TOTAL=$(free -h 2>/dev/null | awk '/Mem:/{print $2}' || echo "N/A")
BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "N/A")
CURRENT_USERS=$(who 2>/dev/null | wc -l)
CURRENT_USERS_LIST=$(who 2>/dev/null | awk '{print $1}' | sort -u | xargs || echo "无")
PROCESS_COUNT=$(ps aux 2>/dev/null | wc -l)
THREAD_COUNT=$(ps -eLf 2>/dev/null | wc -l || echo "N/A")
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "N/A")
TIMEZONE=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || cat /etc/timezone 2>/dev/null || echo "N/A")
LOCALE=$(echo "$LANG" 2>/dev/null || echo "N/A")
DEFAULT_GW=$(ip route 2>/dev/null | awk '/default/{print $3}' | head -1 || echo "N/A")
DNS_SERVERS=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | xargs || echo "N/A")
FIREWALL_STATUS="inactive"
if systemctl is-active firewalld &>/dev/null; then
    FIREWALL_STATUS="firewalld (active)"
elif systemctl is-active ufw &>/dev/null; then
    FIREWALL_STATUS="ufw (active)"
elif systemctl is-active iptables &>/dev/null; then
    FIREWALL_STATUS="iptables (active)"
fi

# 硬件信息
VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "N/A")
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "N/A")
SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "N/A")
BIOS_VER=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "N/A")

# 虚拟化检测
VIRT_TYPE="物理机"
if command -v systemd-detect-virt &>/dev/null; then
    virt=$(systemd-detect-virt 2>/dev/null || true)
    [[ -n "$virt" && "$virt" != "none" ]] && VIRT_TYPE="$virt"
elif grep -qi "vmware\|virtualbox\|kvm\|qemu\|xen\|hyperv" /sys/class/dmi/id/product_name 2>/dev/null; then
    VIRT_TYPE=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
fi

log_info "采集基本信息完成"

cat >> "$REPORT_FILE" <<EOF
<div class="header">
  <h1>Linux 服务器巡检报告</h1>
  <p>${HOSTNAME_VAL} | ${IP_ADDR} | $(date '+%Y-%m-%d %H:%M:%S')</p>
</div>
EOF

# ======================== CPU 检查 ========================
log_info "检查 CPU 使用率..."
CPU_IDLE=""
# 方式1: top
if [[ -z "$CPU_IDLE" ]] || ! [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    CPU_IDLE=$(top -bn1 2>/dev/null | grep -i "cpu" | head -1 | grep -oP '[0-9.]+(?=\s*id)' || true)
fi
# 方式2: mpstat
if [[ -z "$CPU_IDLE" ]] || ! [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    CPU_IDLE=$(mpstat 1 1 2>/dev/null | awk '/Average|^[0-9]/{print $NF}' | tail -1 || true)
fi
# 方式3: vmstat
if [[ -z "$CPU_IDLE" ]] || ! [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    CPU_IDLE=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}' || true)
fi
# 方式4: /proc/stat
if [[ -z "$CPU_IDLE" ]] || ! [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    read -r _ u1 n1 s1 i1 _ < /proc/stat 2>/dev/null || true
    sleep 1
    read -r _ u2 n2 s2 i2 _ < /proc/stat 2>/dev/null || true
    if [[ -n "${i1:-}" && -n "${i2:-}" ]]; then
        total=$(( (u2+n2+s2+i2) - (u1+n1+s1+i1) ))
        idle=$(( i2 - i1 ))
        if (( total > 0 )); then
            CPU_IDLE=$(awk "BEGIN{printf \"%.1f\", $idle/$total*100}")
        fi
    fi
fi
if [[ -z "$CPU_IDLE" ]] || ! [[ "$CPU_IDLE" =~ ^[0-9.]+$ ]]; then
    CPU_IDLE="100"
fi
CPU_USAGE=$(awk "BEGIN{v=100-$CPU_IDLE; if(v<0) v=0; if(v>100) v=100; printf \"%.0f\", v}")
CPU_BADGE=$(status_badge "$CPU_USAGE" "$CPU_WARN")

if (( CPU_USAGE >= CPU_WARN + 10 )); then
    log_error "CPU 使用率: ${CPU_USAGE}%"
elif (( CPU_USAGE >= CPU_WARN )); then
    log_warn "CPU 使用率: ${CPU_USAGE}%"
else
    log_info "CPU 使用率: ${CPU_USAGE}%"
fi

# CPU 各状态详细
CPU_DETAIL=$(top -bn1 2>/dev/null | grep -i "cpu(s)" | head -1 || echo "N/A")

# 负载检查
LOAD_1=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
LOAD_5=$(awk '{print $2}' /proc/loadavg 2>/dev/null || echo "0")
LOAD_15=$(awk '{print $3}' /proc/loadavg 2>/dev/null || echo "0")
RUNNING_PROCS=$(awk '{print $4}' /proc/loadavg 2>/dev/null || echo "N/A")
LOAD_WARN_VAL=$((CPU_CORES * LOAD_WARN_FACTOR))
LOAD_INT=${LOAD_1%.*}
LOAD_INT=${LOAD_INT:-0}

if (( LOAD_INT >= LOAD_WARN_VAL )); then
    log_warn "系统负载偏高: ${LOAD_1} (核数: ${CPU_CORES})"
    LOAD_BADGE='<span class="badge warning">警告</span>'
else
    LOAD_BADGE='<span class="badge ok">正常</span>'
fi

# CPU 占用 TOP 10
CPU_TOP=$(ps aux --sort=-%cpu 2>/dev/null | head -11 | awk 'NR>1{printf "<tr><td>%s</td><td>%s</td><td>%s%%</td><td>%s%%</td><td>", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print "</td></tr>"}')

# ======================== 内存检查 ========================
log_info "检查内存使用率..."
MEM_INFO=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f %s %s %s %s %s %s", ($2-$7)/$2*100, $2, $3, $7, $4, $5, $6}')
MEM_USAGE=$(echo "$MEM_INFO" | awk '{print $1}')
MEM_USAGE=${MEM_USAGE:-0}
MEM_BADGE=$(status_badge "$MEM_USAGE" "$MEM_WARN")

MEM_DETAIL=$(free -h 2>/dev/null || echo "N/A")

# Swap
SWAP_INFO=$(free 2>/dev/null | awk '/Swap:/{if($2>0) printf "%.0f %s %s", $3/$2*100, $2, $3; else print "0 0 0"}')
SWAP_USAGE=$(echo "$SWAP_INFO" | awk '{print $1}')
SWAP_TOTAL=$(free -h 2>/dev/null | awk '/Swap:/{print $2}' || echo "N/A")
SWAP_USED=$(free -h 2>/dev/null | awk '/Swap:/{print $3}' || echo "N/A")
SWAP_BADGE=$(status_badge "${SWAP_USAGE}" "$SWAP_WARN")

if (( MEM_USAGE >= MEM_WARN + 10 )); then
    log_error "内存使用率: ${MEM_USAGE}%"
elif (( MEM_USAGE >= MEM_WARN )); then
    log_warn "内存使用率: ${MEM_USAGE}%"
else
    log_info "内存使用率: ${MEM_USAGE}%"
fi

# 内存占用 TOP 10
MEM_TOP=$(ps aux --sort=-%mem 2>/dev/null | head -11 | awk 'NR>1{printf "<tr><td>%s</td><td>%s</td><td>%s%%</td><td>%s%%</td><td>", $1, $2, $3, $4; for(i=11;i<=NF;i++) printf "%s ", $i; print "</td></tr>"}')

# ======================== 磁盘检查 ========================
log_info "检查磁盘使用率..."
DISK_ROWS=""
DISK_ALERT=0
while IFS= read -r line; do
    fs=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    used=$(echo "$line" | awk '{print $3}')
    avail=$(echo "$line" | awk '{print $4}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    [[ -z "$pct" || ! "$pct" =~ ^[0-9]+$ ]] && continue
    badge=$(status_badge "$pct" "$DISK_WARN")

    fill_class="fill-ok"
    if (( pct >= DISK_WARN + 10 )); then
        fill_class="fill-crit"
        log_error "磁盘 ${mount}: ${pct}%"
        ((DISK_ALERT++)) || true
    elif (( pct >= DISK_WARN )); then
        fill_class="fill-warn"
        log_warn "磁盘 ${mount}: ${pct}%"
        ((DISK_ALERT++)) || true
    fi

    DISK_ROWS+="<tr><td>${fs}</td><td>${size}</td><td>${used}</td><td>${avail}</td>"
    DISK_ROWS+="<td><div class=\"progress-bar\"><div class=\"progress-fill ${fill_class}\" style=\"width:${pct}%\"></div></div> ${pct}%</td>"
    DISK_ROWS+="<td>${mount}</td><td>${badge}</td></tr>"
done < <(df -hP 2>/dev/null | grep -vE "^Filesystem|tmpfs|devtmpfs|overlay|cdrom|udev" || true)

# Inode 检查
INODE_ROWS=""
while IFS= read -r line; do
    fs=$(echo "$line" | awk '{print $1}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')
    [[ -z "$pct" || "$pct" == "-" || ! "$pct" =~ ^[0-9]+$ ]] && continue
    badge=$(status_badge "$pct" "$INODE_WARN")
    if (( pct >= INODE_WARN )); then
        log_warn "Inode ${mount}: ${pct}%"
    fi
    INODE_ROWS+="<tr><td>${fs}</td><td>${pct}%</td><td>${mount}</td><td>${badge}</td></tr>"
done < <(df -iP 2>/dev/null | grep -vE "^Filesystem|tmpfs|devtmpfs|overlay" || true)

# 磁盘 I/O 统计
log_info "检查磁盘 I/O..."
DISK_IO_ROWS=""
if command -v iostat &>/dev/null; then
    while IFS= read -r line; do
        dev=$(echo "$line" | awk '{print $1}')
        tps=$(echo "$line" | awk '{print $2}')
        read_s=$(echo "$line" | awk '{print $3}')
        write_s=$(echo "$line" | awk '{print $4}')
        await=""
        [[ "$dev" =~ ^loop|^ram ]] && continue
        DISK_IO_ROWS+="<tr><td>${dev}</td><td>${tps}</td><td>${read_s}</td><td>${write_s}</td></tr>"
    done < <(iostat -d 2>/dev/null | awk 'NR>3 && NF>0{print}' || true)
fi

# 大文件 TOP 10
log_info "扫描大文件..."
LARGE_FILES=""
while IFS= read -r line; do
    fsize=$(echo "$line" | awk '{print $1}')
    fpath=$(echo "$line" | cut -d' ' -f2-)
    LARGE_FILES+="<tr><td>${fsize}</td><td>$(html_escape "$fpath")</td></tr>"
done < <(find / -xdev -type f -size "$LARGE_FILE_SIZE" -exec du -sh {} + 2>/dev/null | sort -rh | head -10 || true)

# 最近7天修改的大文件(>50M)
RECENT_LARGE=""
while IFS= read -r line; do
    fsize=$(echo "$line" | awk '{print $1}')
    fpath=$(echo "$line" | cut -d' ' -f2-)
    RECENT_LARGE+="<tr><td>${fsize}</td><td>$(html_escape "$fpath")</td></tr>"
done < <(find / -xdev -type f -size +50M -mtime -7 -exec du -sh {} + 2>/dev/null | sort -rh | head -10 || true)

# ======================== 文件描述符 ========================
log_info "检查文件描述符..."
FD_CURRENT=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $1}' || echo "0")
FD_MAX=$(cat /proc/sys/fs/file-nr 2>/dev/null | awk '{print $3}' || echo "1")
FD_PCT=$(awk "BEGIN{if($FD_MAX>0) printf \"%.0f\", $FD_CURRENT/$FD_MAX*100; else print 0}")
FD_BADGE=$(status_badge "$FD_PCT" "$FD_WARN")
if (( FD_PCT >= FD_WARN )); then
    log_warn "文件描述符使用率: ${FD_PCT}%"
fi

# 各进程 FD 使用 TOP 5
FD_TOP=""
for pid in $(ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | head -200); do
    fd_count=$(ls /proc/"$pid"/fd 2>/dev/null | wc -l || echo 0)
    name=$(cat /proc/"$pid"/comm 2>/dev/null || echo "unknown")
    echo "$fd_count $pid $name"
done 2>/dev/null | sort -rn | head -5 | while read -r cnt pid name; do
    echo "<tr><td>${name}</td><td>${pid}</td><td>${cnt}</td></tr>"
done > /tmp/.fd_top_$$ 2>/dev/null || true
FD_TOP=$(cat /tmp/.fd_top_$$ 2>/dev/null || true)
rm -f /tmp/.fd_top_$$ 2>/dev/null || true

# ======================== 网络检查 ========================
log_info "检查网络状态..."
NIC_ROWS=""
while IFS= read -r nic; do
    [[ "$nic" == "lo" ]] && continue
    state=$(cat /sys/class/net/"$nic"/operstate 2>/dev/null || echo "unknown")
    speed=$(cat /sys/class/net/"$nic"/speed 2>/dev/null || echo "N/A")
    [[ "$speed" == "-1" ]] && speed="N/A"
    ip=$(ip -4 addr show "$nic" 2>/dev/null | grep inet | awk '{print $2}' | head -1 || echo "N/A")
    mac=$(cat /sys/class/net/"$nic"/address 2>/dev/null || echo "N/A")
    # 流量统计
    rx_bytes=$(cat /sys/class/net/"$nic"/statistics/rx_bytes 2>/dev/null || echo "0")
    tx_bytes=$(cat /sys/class/net/"$nic"/statistics/tx_bytes 2>/dev/null || echo "0")
    rx_h=$(human_bytes "$rx_bytes")
    tx_h=$(human_bytes "$tx_bytes")
    rx_errors=$(cat /sys/class/net/"$nic"/statistics/rx_errors 2>/dev/null || echo "0")
    tx_errors=$(cat /sys/class/net/"$nic"/statistics/tx_errors 2>/dev/null || echo "0")
    rx_dropped=$(cat /sys/class/net/"$nic"/statistics/rx_dropped 2>/dev/null || echo "0")
    tx_dropped=$(cat /sys/class/net/"$nic"/statistics/tx_dropped 2>/dev/null || echo "0")
    badge='<span class="badge ok">UP</span>'
    [[ "$state" != "up" ]] && badge='<span class="badge warning">DOWN</span>'
    err_badge=""
    total_err=$((rx_errors + tx_errors + rx_dropped + tx_dropped))
    if (( total_err > 0 )); then
        err_badge=' <span class="badge warning">有错误</span>'
    fi
    NIC_ROWS+="<tr><td>${nic}</td><td>${ip}</td><td>${mac}</td><td>${speed}Mbps</td><td>RX:${rx_h} TX:${tx_h}</td><td>错误:${total_err} 丢包:$((rx_dropped+tx_dropped))</td><td>${badge}${err_badge}</td></tr>"
done < <(ls /sys/class/net/ 2>/dev/null || true)

# TCP 连接统计
CONN_ESTABLISHED=$(ss -tn state established 2>/dev/null | wc -l || echo "0")
CONN_TIME_WAIT=$(ss -tn state time-wait 2>/dev/null | wc -l || echo "0")
CONN_CLOSE_WAIT=$(ss -tn state close-wait 2>/dev/null | wc -l || echo "0")
CONN_SYN_RECV=$(ss -tn state syn-recv 2>/dev/null | wc -l || echo "0")
CONN_LISTEN=$(ss -tln 2>/dev/null | wc -l || echo "0")
CONN_TOTAL=$((CONN_ESTABLISHED + CONN_TIME_WAIT + CONN_CLOSE_WAIT + CONN_SYN_RECV))

if (( CONN_CLOSE_WAIT > 50 )); then
    log_warn "CLOSE_WAIT 连接数偏高: ${CONN_CLOSE_WAIT}"
fi

# 监听端口
LISTEN_PORTS=$(ss -tlnp 2>/dev/null | awk 'NR>1{printf "<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n", $4, $1, $NF}' | head -30 || echo "")

# 路由表
ROUTE_TABLE=$(ip route 2>/dev/null | head -20 | while IFS= read -r line; do echo "<tr><td>$(html_escape "$line")</td></tr>"; done || echo "")

# ======================== 进程检查 ========================
log_info "检查进程状态..."
ZOMBIE_COUNT=$(ps aux 2>/dev/null | awk '$8~/Z/{count++} END{print count+0}')
if (( ZOMBIE_COUNT > ZOMBIE_WARN )); then
    log_warn "发现 ${ZOMBIE_COUNT} 个僵尸进程"
    ZOMBIE_BADGE='<span class="badge warning">警告</span>'
    ZOMBIE_LIST=$(ps aux 2>/dev/null | awk '$8~/Z/' | head -10)
else
    ZOMBIE_BADGE='<span class="badge ok">正常</span>'
    ZOMBIE_LIST=""
fi

# D 状态进程(不可中断睡眠)
D_STATE_COUNT=$(ps aux 2>/dev/null | awk '$8~/D/{count++} END{print count+0}')
D_STATE_LIST=""
if (( D_STATE_COUNT > 0 )); then
    log_warn "发现 ${D_STATE_COUNT} 个 D 状态进程"
    D_STATE_LIST=$(ps aux 2>/dev/null | awk '$8~/D/' | head -5)
fi

# 运行时间最长的进程 TOP 5
LONG_RUNNING=$(ps -eo pid,user,etime,comm --sort=-etime 2>/dev/null | head -6 | awk 'NR>1{printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", $1, $2, $3, $4}' || echo "")

# ======================== 安全检查 ========================
log_info "执行安全检查..."

# SSH 配置
SSH_ROOT="N/A"
SSH_PORT="22"
SSH_PROTOCOL=""
SSH_MAXAUTH=""
SSH_PUBKEY=""
if [[ -f /etc/ssh/sshd_config ]]; then
    SSH_ROOT=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "默认(yes)")
    SSH_PORT=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    SSH_MAXAUTH=$(grep -i "^MaxAuthTries" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "默认(6)")
    SSH_PUBKEY=$(grep -i "^PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "默认(yes)")
fi
[[ -z "$SSH_ROOT" ]] && SSH_ROOT="默认(yes)"
[[ -z "$SSH_MAXAUTH" ]] && SSH_MAXAUTH="默认(6)"
[[ -z "$SSH_PUBKEY" ]] && SSH_PUBKEY="默认(yes)"

# 账户安全审计
# UID=0 的账户
ROOT_USERS=$(awk -F: '$3==0{print $1}' /etc/passwd 2>/dev/null | xargs || echo "root")
# 空密码账户
EMPTY_PASS=$(awk -F: '($2=="!" || $2=="*" || $2==""){print $1}' /etc/shadow 2>/dev/null | head -10 | xargs || echo "无")
# 可登录 shell 的账户
LOGIN_USERS=$(awk -F: '$7!~/nologin|false|sync|shutdown|halt/{print $1}' /etc/passwd 2>/dev/null | xargs || echo "N/A")
LOGIN_USER_COUNT=$(awk -F: '$7!~/nologin|false|sync|shutdown|halt/{count++} END{print count+0}' /etc/passwd 2>/dev/null || echo "0")

# 密码过期账户
EXPIRE_USERS=""
while IFS=: read -r user _ uid _ _ _ _; do
    (( uid < 1000 && uid != 0 )) && continue
    expire_info=$(chage -l "$user" 2>/dev/null | grep "Password expires" | cut -d: -f2 | xargs || true)
    if [[ -n "$expire_info" && "$expire_info" != "never" && "$expire_info" != "从不" ]]; then
        expire_epoch=$(date -d "$expire_info" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        if (( expire_epoch > 0 && expire_epoch < now_epoch )); then
            EXPIRE_USERS+="<tr><td>${user}</td><td>${expire_info}</td><td><span class=\"badge critical\">已过期</span></td></tr>"
        elif (( expire_epoch > 0 && expire_epoch - now_epoch < 604800 )); then
            EXPIRE_USERS+="<tr><td>${user}</td><td>${expire_info}</td><td><span class=\"badge warning\">即将过期</span></td></tr>"
        fi
    fi
done < /etc/passwd 2>/dev/null || true

# 最近登录失败
FAIL_LOGINS=$(lastb 2>/dev/null | head -10 | awk 'NF>3{printf "<tr><td>%s</td><td>%s</td><td>%s %s %s</td></tr>\n", $1, $3, $4, $5, $6}' || echo "")
FAIL_COUNT=$(lastb 2>/dev/null | grep -c "." 2>/dev/null || echo "0")

# 最近成功登录
SUCCESS_LOGINS=$(last -n 10 2>/dev/null | awk 'NF>3 && !/^$/ && !/wtmp/{printf "<tr><td>%s</td><td>%s</td><td>%s %s %s</td></tr>\n", $1, $3, $4, $5, $6}' || echo "")

# 可疑 SUID 文件
SUID_FILES=$(find /usr/local /opt /home /tmp /var/tmp -perm -4000 -type f 2>/dev/null | head -10 || echo "")
# 可疑 SGID 文件
SGID_FILES=$(find /usr/local /opt /home /tmp /var/tmp -perm -2000 -type f 2>/dev/null | head -10 || echo "")
# 全局可写文件(非 /tmp /proc /sys /dev)
WORLD_WRITABLE=$(find / -xdev -path /tmp -prune -o -path /proc -prune -o -path /sys -prune -o -path /dev -prune -o -type f -perm -0002 -print 2>/dev/null | head -10 || echo "")

# /tmp 目录大小
TMP_SIZE=$(du -sh /tmp 2>/dev/null | awk '{print $1}' || echo "N/A")
VAR_LOG_SIZE=$(du -sh /var/log 2>/dev/null | awk '{print $1}' || echo "N/A")

# ======================== 定时任务 ========================
log_info "检查定时任务..."
CRON_ROWS=""
# 系统 crontab
if [[ -f /etc/crontab ]]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^#|^$ ]] && continue
        CRON_ROWS+="<tr><td>system</td><td>/etc/crontab</td><td>$(html_escape "$line")</td></tr>"
    done < <(grep -vE "^#|^$|^[A-Z]" /etc/crontab 2>/dev/null || true)
fi
# /etc/cron.d/
for f in /etc/cron.d/*; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line; do
        [[ "$line" =~ ^#|^$ ]] && continue
        CRON_ROWS+="<tr><td>system</td><td>$(basename "$f")</td><td>$(html_escape "$line")</td></tr>"
    done < <(grep -vE "^#|^$|^[A-Z]" "$f" 2>/dev/null || true)
done
# 用户 crontab
for user_cron in /var/spool/cron/crontabs/* /var/spool/cron/*; do
    [[ -f "$user_cron" ]] || continue
    cron_user=$(basename "$user_cron")
    while IFS= read -r line; do
        [[ "$line" =~ ^#|^$ ]] && continue
        CRON_ROWS+="<tr><td>${cron_user}</td><td>用户crontab</td><td>$(html_escape "$line")</td></tr>"
    done < <(grep -vE "^#|^$" "$user_cron" 2>/dev/null || true)
done

# ======================== 服务检查 ========================
log_info "检查关键服务状态..."
SERVICES=("sshd" "crond" "cron" "rsyslog" "syslog-ng" "firewalld" "ufw" "chronyd" "ntpd" "systemd-timesyncd" "docker" "containerd" "kubelet" "nginx" "httpd" "apache2" "mysqld" "mariadb" "postgresql" "redis-server" "redis" "mongod" "elasticsearch" "php-fpm" "tomcat" "supervisord" "zabbix-agent" "zabbix-agent2" "node_exporter" "prometheus" "grafana-server" "haproxy" "keepalived" "named" "dnsmasq" "postfix" "dovecot" "vsftpd" "smbd")
SVC_ROWS=""
for svc in "${SERVICES[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -qw "${svc}"; then
        status=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
        enabled=$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")
        if [[ "$status" == "active" ]]; then
            badge='<span class="badge ok">运行中</span>'
        elif [[ "$status" == "inactive" ]]; then
            badge='<span class="badge warning">已停止</span>'
        else
            badge='<span class="badge critical">异常</span>'
        fi
        SVC_ROWS+="<tr><td>${svc}</td><td>${badge}</td><td>${enabled}</td></tr>"
    fi
done

# 最近失败的服务
FAILED_SVCS=$(systemctl --failed --no-pager 2>/dev/null | grep "loaded" | awk '{printf "<tr><td>%s</td><td><span class=\"badge critical\">FAILED</span></td><td>%s</td></tr>\n", $2, $4}' || echo "")

# ======================== Docker 检查 ========================
DOCKER_ROWS=""
DOCKER_IMAGES=""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
    log_info "检查 Docker 容器..."
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "N/A")
    DOCKER_CONTAINERS=$(docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true)
    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        image=$(echo "$line" | awk '{print $2}')
        status=$(echo "$line" | awk '{print $3, $4, $5}')
        badge='<span class="badge ok">运行中</span>'
        if echo "$status" | grep -qi "exited\|dead\|created"; then
            badge='<span class="badge warning">已停止</span>'
        fi
        DOCKER_ROWS+="<tr><td>${name}</td><td>${image}</td><td>${status}</td><td>${badge}</td></tr>"
    done < <(docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}" 2>/dev/null || true)
    # 镜像列表
    DOCKER_IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" 2>/dev/null | head -15 | while read -r img size; do echo "<tr><td>${img}</td><td>${size}</td></tr>"; done || true)
    # Docker 磁盘使用
    DOCKER_DISK=$(docker system df 2>/dev/null || true)
fi

# ======================== 内核参数 ========================
log_info "检查内核参数..."
KERN_ROWS=""
KERN_PARAMS=(
    "net.ipv4.tcp_syncookies|TCP SYN Cookies|1"
    "net.ipv4.ip_forward|IP 转发|视需求"
    "net.ipv4.tcp_max_syn_backlog|SYN 队列长度|>=1024"
    "net.core.somaxconn|Socket 最大连接队列|>=1024"
    "net.ipv4.tcp_tw_reuse|TIME_WAIT 重用|1"
    "net.ipv4.tcp_fin_timeout|FIN 超时|<=30"
    "net.ipv4.tcp_keepalive_time|Keepalive 时间|<=600"
    "net.core.netdev_max_backlog|网卡积压队列|>=1000"
    "vm.swappiness|Swap 倾向|<=30"
    "vm.overcommit_memory|内存过量分配|视需求"
    "fs.file-max|系统最大文件描述符|>=65535"
    "net.ipv4.conf.all.rp_filter|反向路径过滤|1"
    "kernel.panic|内核 panic 重启|>0"
)
for item in "${KERN_PARAMS[@]}"; do
    IFS='|' read -r param desc recommend <<< "$item"
    val=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    KERN_ROWS+="<tr><td>${param}</td><td>${desc}</td><td>${val}</td><td>${recommend}</td></tr>"
done

# ======================== 系统更新 ========================
log_info "检查系统更新状态..."
UPDATE_INFO="N/A"
UPDATE_COUNT=0
if command -v yum &>/dev/null; then
    UPDATE_COUNT=$(yum check-update --quiet 2>/dev/null | grep -cE "^[a-zA-Z]" || echo "0")
    UPDATE_INFO="yum: ${UPDATE_COUNT} 个可用更新"
    LAST_UPDATE=$(rpm -qa --last 2>/dev/null | head -1 | awk '{print $2, $3, $4, $5}' || echo "N/A")
elif command -v dnf &>/dev/null; then
    UPDATE_COUNT=$(dnf check-update --quiet 2>/dev/null | grep -cE "^[a-zA-Z]" || echo "0")
    UPDATE_INFO="dnf: ${UPDATE_COUNT} 个可用更新"
    LAST_UPDATE=$(rpm -qa --last 2>/dev/null | head -1 | awk '{print $2, $3, $4, $5}' || echo "N/A")
elif command -v apt &>/dev/null; then
    apt update -qq 2>/dev/null || true
    UPDATE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    UPDATE_INFO="apt: ${UPDATE_COUNT} 个可用更新"
    LAST_UPDATE=$(stat -c %y /var/cache/apt/pkgcache.bin 2>/dev/null | cut -d' ' -f1 || echo "N/A")
fi

# 安全更新
SEC_UPDATES=""
if command -v yum &>/dev/null; then
    SEC_UPDATES=$(yum updateinfo list security 2>/dev/null | grep -c "security" || echo "0")
    SEC_UPDATES="${SEC_UPDATES} 个安全更新"
elif command -v apt &>/dev/null; then
    SEC_UPDATES=$(apt list --upgradable 2>/dev/null | grep -ci "security" || echo "0")
    SEC_UPDATES="${SEC_UPDATES} 个安全更新"
fi

# ======================== 日志检查 ========================
log_info "检查系统日志..."
SYSLOG_ERRORS=""
if [[ -f /var/log/messages ]]; then
    SYSLOG_ERRORS=$(grep -iE "error|fail|critical|panic|oom" /var/log/messages 2>/dev/null | tail -"$LOG_LINES" || true)
elif [[ -f /var/log/syslog ]]; then
    SYSLOG_ERRORS=$(grep -iE "error|fail|critical|panic|oom" /var/log/syslog 2>/dev/null | tail -"$LOG_LINES" || true)
else
    SYSLOG_ERRORS=$(journalctl -p err --no-pager -n "$LOG_LINES" 2>/dev/null || echo "无法读取日志")
fi

# OOM 检查
OOM_COUNT=$(dmesg 2>/dev/null | grep -ci "oom\|out of memory" || echo "0")
if (( OOM_COUNT > 0 )); then
    log_warn "检测到 ${OOM_COUNT} 次 OOM 事件"
fi

# dmesg 硬件错误
HW_ERRORS=$(dmesg 2>/dev/null | grep -iE "hardware error|machine check|ecc|i/o error|medium error" | tail -5 || true)

# 认证日志
AUTH_ERRORS=""
if [[ -f /var/log/auth.log ]]; then
    AUTH_ERRORS=$(grep -iE "failed|invalid|error" /var/log/auth.log 2>/dev/null | tail -10 || true)
elif [[ -f /var/log/secure ]]; then
    AUTH_ERRORS=$(grep -iE "failed|invalid|error" /var/log/secure 2>/dev/null | tail -10 || true)
fi

# ======================== NTP 时间同步 ========================
log_info "检查时间同步..."
NTP_STATUS="未配置"
NTP_BADGE='<span class="badge warning">警告</span>'
NTP_DETAIL=""
if command -v chronyc &>/dev/null; then
    NTP_STATUS=$(chronyc tracking 2>/dev/null | grep "Leap status" | cut -d: -f2 | xargs || echo "未同步")
    NTP_DETAIL=$(chronyc sources 2>/dev/null | head -10 || true)
    if [[ "$NTP_STATUS" == "Normal" ]]; then
        NTP_BADGE='<span class="badge ok">正常</span>'
    fi
elif command -v ntpstat &>/dev/null; then
    if ntpstat &>/dev/null; then
        NTP_STATUS="已同步"
        NTP_BADGE='<span class="badge ok">正常</span>'
    else
        NTP_STATUS="未同步"
    fi
elif timedatectl 2>/dev/null | grep -q "synchronized: yes"; then
    NTP_STATUS="已同步(systemd-timesyncd)"
    NTP_BADGE='<span class="badge ok">正常</span>'
fi

# ======================== 生成 HTML 报告 ========================
log_info "生成 HTML 报告..."

CPU_COLOR=$(get_color_class "$CPU_USAGE" "$CPU_WARN")
MEM_COLOR=$(get_color_class "$MEM_USAGE" "$MEM_WARN")
DISK_COLOR="green"
(( DISK_ALERT > 0 )) && DISK_COLOR="orange"

cat >> "$REPORT_FILE" <<EOF
<div class="summary">
  <div class="summary-card">
    <div class="num ${CPU_COLOR}">${CPU_USAGE}%</div>
    <div class="label">CPU</div>
  </div>
  <div class="summary-card">
    <div class="num ${MEM_COLOR}">${MEM_USAGE}%</div>
    <div class="label">内存</div>
  </div>
  <div class="summary-card">
    <div class="num ${DISK_COLOR}">${DISK_ALERT}</div>
    <div class="label">磁盘告警</div>
  </div>
  <div class="summary-card">
    <div class="num green">${LOAD_1}</div>
    <div class="label">负载(1m)</div>
  </div>
  <div class="summary-card">
    <div class="num green">${CONN_TOTAL}</div>
    <div class="label">TCP连接</div>
  </div>
  <div class="summary-card">
    <div class="num $(get_color_class "$WARN_COUNT" 3)">${WARN_COUNT}</div>
    <div class="label">警告</div>
  </div>
</div>

<!-- 基本信息 -->
<div class="section">
  <h2>基本信息</h2>
  <div class="info-grid">
    <div class="info-item"><span class="key">主机名</span><span class="val">${HOSTNAME_VAL}</span></div>
    <div class="info-item"><span class="key">FQDN</span><span class="val">${HOSTNAME_FQDN}</span></div>
    <div class="info-item"><span class="key">IP 地址</span><span class="val">${IP_ALL}</span></div>
    <div class="info-item"><span class="key">操作系统</span><span class="val">${OS_VERSION}</span></div>
    <div class="info-item"><span class="key">内核版本</span><span class="val">${KERNEL}</span></div>
    <div class="info-item"><span class="key">架构</span><span class="val">${ARCH}</span></div>
    <div class="info-item"><span class="key">运行时间</span><span class="val">${UPTIME} (${UPTIME_DAYS}天)</span></div>
    <div class="info-item"><span class="key">启动时间</span><span class="val">${BOOT_TIME}</span></div>
    <div class="info-item"><span class="key">时区</span><span class="val">${TIMEZONE}</span></div>
    <div class="info-item"><span class="key">CPU 型号</span><span class="val">${CPU_MODEL}</span></div>
    <div class="info-item"><span class="key">CPU 核数/插槽</span><span class="val">${CPU_CORES}核 / ${CPU_SOCKETS}路</span></div>
    <div class="info-item"><span class="key">总内存</span><span class="val">${MEM_TOTAL}</span></div>
    <div class="info-item"><span class="key">当前用户</span><span class="val">${CURRENT_USERS}人 (${CURRENT_USERS_LIST})</span></div>
    <div class="info-item"><span class="key">进程/线程</span><span class="val">${PROCESS_COUNT} / ${THREAD_COUNT}</span></div>
    <div class="info-item"><span class="key">SELinux</span><span class="val">${SELINUX_STATUS}</span></div>
    <div class="info-item"><span class="key">防火墙</span><span class="val">${FIREWALL_STATUS}</span></div>
    <div class="info-item"><span class="key">时间同步</span><span class="val">${NTP_STATUS} ${NTP_BADGE}</span></div>
    <div class="info-item"><span class="key">默认网关</span><span class="val">${DEFAULT_GW}</span></div>
    <div class="info-item"><span class="key">DNS 服务器</span><span class="val">${DNS_SERVERS}</span></div>
    <div class="info-item"><span class="key">虚拟化</span><span class="val">${VIRT_TYPE}</span></div>
    <div class="info-item"><span class="key">厂商/型号</span><span class="val">${VENDOR} ${PRODUCT}</span></div>
    <div class="info-item"><span class="key">序列号</span><span class="val">${SERIAL}</span></div>
    <div class="info-item"><span class="key">BIOS 版本</span><span class="val">${BIOS_VER}</span></div>
  </div>
</div>

<!-- CPU & 负载 -->
<div class="section">
  <h2>CPU & 负载</h2>
  <table>
    <tr><th>指标</th><th>当前值</th><th>阈值</th><th>状态</th></tr>
    <tr><td>CPU 使用率</td><td>${CPU_USAGE}%</td><td>${CPU_WARN}%</td><td>${CPU_BADGE}</td></tr>
    <tr><td>负载(1/5/15分钟)</td><td>${LOAD_1} / ${LOAD_5} / ${LOAD_15}</td><td>核数x${LOAD_WARN_FACTOR}=${LOAD_WARN_VAL}</td><td>${LOAD_BADGE}</td></tr>
    <tr><td>运行中进程/总进程</td><td>${RUNNING_PROCS}</td><td>-</td><td><span class="badge info">信息</span></td></tr>
  </table>
  <h3>CPU 占用 TOP 10 进程</h3>
  <table>
    <tr><th>用户</th><th>PID</th><th>CPU%</th><th>MEM%</th><th>命令</th></tr>
    ${CPU_TOP}
  </table>
</div>

<!-- 内存 & Swap -->
<div class="section">
  <h2>内存 & Swap</h2>
  <table>
    <tr><th>指标</th><th>当前值</th><th>阈值</th><th>状态</th></tr>
    <tr><td>内存使用率</td><td>${MEM_USAGE}%</td><td>${MEM_WARN}%</td><td>${MEM_BADGE}</td></tr>
    <tr><td>Swap 使用率</td><td>${SWAP_USAGE}% (${SWAP_USED}/${SWAP_TOTAL})</td><td>${SWAP_WARN}%</td><td>${SWAP_BADGE}</td></tr>
  </table>
  <h3>内存详细</h3>
  <pre>${MEM_DETAIL}</pre>
  <h3>内存占用 TOP 10 进程</h3>
  <table>
    <tr><th>用户</th><th>PID</th><th>CPU%</th><th>MEM%</th><th>命令</th></tr>
    ${MEM_TOP}
  </table>
</div>

<!-- 磁盘使用 -->
<div class="section">
  <h2>磁盘使用</h2>
  <table>
    <tr><th>文件系统</th><th>大小</th><th>已用</th><th>可用</th><th>使用率</th><th>挂载点</th><th>状态</th></tr>
    ${DISK_ROWS}
  </table>
  <h3>Inode 使用情况</h3>
  <table>
    <tr><th>文件系统</th><th>Inode 使用率</th><th>挂载点</th><th>状态</th></tr>
    ${INODE_ROWS}
  </table>
EOF

# 磁盘 I/O
if [[ -n "$DISK_IO_ROWS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>磁盘 I/O 统计</h3>
  <table>
    <tr><th>设备</th><th>TPS</th><th>读(KB/s)</th><th>写(KB/s)</th></tr>
    ${DISK_IO_ROWS}
  </table>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
  <div class="two-col" style="margin-top:14px;">
    <div class="mini-card"><h4>/tmp 大小</h4><span style="font-size:18px;font-weight:bold;">${TMP_SIZE}</span></div>
    <div class="mini-card"><h4>/var/log 大小</h4><span style="font-size:18px;font-weight:bold;">${VAR_LOG_SIZE}</span></div>
  </div>
</div>

<!-- 大文件 -->
<div class="section">
  <h2>大文件分析</h2>
EOF

if [[ -n "$LARGE_FILES" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>大文件 TOP 10 (>100M)</h3>
  <table>
    <tr><th>大小</th><th>路径</th></tr>
    ${LARGE_FILES}
  </table>
EOF
else
    echo "  <p style='color:#999;font-size:13px;'>未发现超过 100M 的大文件</p>" >> "$REPORT_FILE"
fi

if [[ -n "$RECENT_LARGE" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>最近7天修改的大文件 (>50M)</h3>
  <table>
    <tr><th>大小</th><th>路径</th></tr>
    ${RECENT_LARGE}
  </table>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</div>

<!-- 文件描述符 -->
<div class="section">
  <h2>文件描述符</h2>
  <table>
    <tr><th>指标</th><th>当前值</th><th>最大值</th><th>使用率</th><th>状态</th></tr>
    <tr><td>系统 FD</td><td>${FD_CURRENT}</td><td>${FD_MAX}</td><td>${FD_PCT}%</td><td>${FD_BADGE}</td></tr>
  </table>
EOF

if [[ -n "$FD_TOP" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>FD 使用 TOP 5 进程</h3>
  <table>
    <tr><th>进程名</th><th>PID</th><th>FD 数</th></tr>
    ${FD_TOP}
  </table>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</div>

<!-- 网络状态 -->
<div class="section">
  <h2>网络状态</h2>
  <h3>网卡信息</h3>
  <table>
    <tr><th>网卡</th><th>IP</th><th>MAC</th><th>速率</th><th>流量(累计)</th><th>错误/丢包</th><th>状态</th></tr>
    ${NIC_ROWS}
  </table>
  <h3>TCP 连接统计</h3>
  <table>
    <tr><th>ESTABLISHED</th><th>TIME_WAIT</th><th>CLOSE_WAIT</th><th>SYN_RECV</th><th>LISTEN</th><th>总计</th></tr>
    <tr><td>${CONN_ESTABLISHED}</td><td>${CONN_TIME_WAIT}</td><td>${CONN_CLOSE_WAIT}</td><td>${CONN_SYN_RECV}</td><td>${CONN_LISTEN}</td><td>${CONN_TOTAL}</td></tr>
  </table>
  <h3>监听端口 (前30)</h3>
  <table>
    <tr><th>地址:端口</th><th>协议</th><th>进程</th></tr>
    ${LISTEN_PORTS}
  </table>
  <h3>路由表</h3>
  <table>
    <tr><th>路由条目</th></tr>
    ${ROUTE_TABLE}
  </table>
</div>

<!-- 进程检查 -->
<div class="section">
  <h2>进程检查</h2>
  <table>
    <tr><th>检查项</th><th>结果</th><th>状态</th></tr>
    <tr><td>僵尸进程(Z)</td><td>${ZOMBIE_COUNT}</td><td>${ZOMBIE_BADGE}</td></tr>
    <tr><td>D 状态进程</td><td>${D_STATE_COUNT}</td><td>$(if (( D_STATE_COUNT > 0 )); then echo '<span class="badge warning">警告</span>'; else echo '<span class="badge ok">正常</span>'; fi)</td></tr>
  </table>
EOF

if [[ -n "$ZOMBIE_LIST" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>僵尸进程详情</h3>
  <pre>$(html_escape "$ZOMBIE_LIST")</pre>
EOF
fi

if [[ -n "$D_STATE_LIST" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>D 状态进程详情</h3>
  <pre>$(html_escape "$D_STATE_LIST")</pre>
EOF
fi

if [[ -n "$LONG_RUNNING" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>运行时间最长的进程 TOP 5</h3>
  <table>
    <tr><th>PID</th><th>用户</th><th>运行时间</th><th>进程名</th></tr>
    ${LONG_RUNNING}
  </table>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</div>

<!-- 服务状态 -->
<div class="section">
  <h2>服务状态</h2>
  <table>
    <tr><th>服务名</th><th>运行状态</th><th>开机自启</th></tr>
    ${SVC_ROWS}
  </table>
EOF

if [[ -n "$FAILED_SVCS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>失败的服务 (systemctl --failed)</h3>
  <table>
    <tr><th>服务</th><th>状态</th><th>说明</th></tr>
    ${FAILED_SVCS}
  </table>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</div>
EOF

# Docker 部分
if [[ -n "$DOCKER_ROWS" ]] || [[ -n "$DOCKER_IMAGES" ]]; then
    cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>Docker 容器</h2>
  <p style="font-size:12px;color:#888;margin-bottom:10px;">Docker 版本: ${DOCKER_VERSION:-N/A}</p>
  <h3>容器列表</h3>
  <table>
    <tr><th>容器名</th><th>镜像</th><th>状态</th><th>运行状态</th></tr>
    ${DOCKER_ROWS}
  </table>
EOF
    if [[ -n "$DOCKER_IMAGES" ]]; then
        cat >> "$REPORT_FILE" <<EOF
  <h3>镜像列表 (前15)</h3>
  <table>
    <tr><th>镜像</th><th>大小</th></tr>
    ${DOCKER_IMAGES}
  </table>
EOF
    fi
    if [[ -n "${DOCKER_DISK:-}" ]]; then
        cat >> "$REPORT_FILE" <<EOF
  <h3>Docker 磁盘占用</h3>
  <pre>$(html_escape "$DOCKER_DISK")</pre>
EOF
    fi
    echo "</div>" >> "$REPORT_FILE"
fi

# 定时任务
cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>定时任务</h2>
EOF
if [[ -n "$CRON_ROWS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <table>
    <tr><th>用户</th><th>来源</th><th>任务内容</th></tr>
    ${CRON_ROWS}
  </table>
EOF
else
    echo "  <p style='color:#999;font-size:13px;'>未发现定时任务</p>" >> "$REPORT_FILE"
fi
echo "</div>" >> "$REPORT_FILE"

# 安全检查
cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>安全检查</h2>
  <h3>SSH 配置</h3>
  <table>
    <tr><th>配置项</th><th>当前值</th><th>建议</th></tr>
    <tr><td>Root 登录</td><td>${SSH_ROOT}</td><td>建议设为 no 或 prohibit-password</td></tr>
    <tr><td>SSH 端口</td><td>${SSH_PORT}</td><td>建议修改默认端口</td></tr>
    <tr><td>最大认证次数</td><td>${SSH_MAXAUTH}</td><td>建议 <=3</td></tr>
    <tr><td>密钥认证</td><td>${SSH_PUBKEY}</td><td>建议 yes</td></tr>
    <tr><td>SELinux</td><td>${SELINUX_STATUS}</td><td>建议 Enforcing</td></tr>
    <tr><td>防火墙</td><td>${FIREWALL_STATUS}</td><td>建议开启</td></tr>
  </table>
  <h3>账户审计</h3>
  <table>
    <tr><th>检查项</th><th>结果</th></tr>
    <tr><td>UID=0 的账户</td><td>${ROOT_USERS}</td></tr>
    <tr><td>可登录 Shell 账户数</td><td>${LOGIN_USER_COUNT} (${LOGIN_USERS})</td></tr>
    <tr><td>登录失败总次数</td><td>${FAIL_COUNT}</td></tr>
  </table>
EOF

if [[ -n "$EXPIRE_USERS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>密码过期/即将过期账户</h3>
  <table>
    <tr><th>用户</th><th>过期时间</th><th>状态</th></tr>
    ${EXPIRE_USERS}
  </table>
EOF
fi

if [[ -n "$FAIL_LOGINS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>最近登录失败记录 (前10)</h3>
  <table>
    <tr><th>用户</th><th>来源IP</th><th>时间</th></tr>
    ${FAIL_LOGINS}
  </table>
EOF
fi

if [[ -n "$SUCCESS_LOGINS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>最近成功登录记录</h3>
  <table>
    <tr><th>用户</th><th>来源</th><th>时间</th></tr>
    ${SUCCESS_LOGINS}
  </table>
EOF
fi

if [[ -n "$SUID_FILES" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>可疑 SUID 文件</h3>
  <pre>$(html_escape "$SUID_FILES")</pre>
EOF
fi

if [[ -n "$WORLD_WRITABLE" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>全局可写文件</h3>
  <pre>$(html_escape "$WORLD_WRITABLE")</pre>
EOF
fi

echo "</div>" >> "$REPORT_FILE"

# 内核参数
cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>内核参数</h2>
  <table>
    <tr><th>参数</th><th>说明</th><th>当前值</th><th>建议值</th></tr>
    ${KERN_ROWS}
  </table>
</div>
EOF

# 系统更新
cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>系统更新</h2>
  <table>
    <tr><th>检查项</th><th>结果</th></tr>
    <tr><td>可用更新</td><td>${UPDATE_INFO}</td></tr>
    <tr><td>安全更新</td><td>${SEC_UPDATES:-N/A}</td></tr>
    <tr><td>最近安装/更新</td><td>${LAST_UPDATE:-N/A}</td></tr>
  </table>
</div>
EOF

# 系统日志
cat >> "$REPORT_FILE" <<EOF
<div class="section">
  <h2>系统日志 (最近异常)</h2>
  <pre>${SYSLOG_ERRORS:-无异常日志}</pre>
  <p style="margin-top:8px;font-size:12px;color:#888;">OOM 事件次数: ${OOM_COUNT}</p>
EOF

if [[ -n "$HW_ERRORS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>硬件错误 (dmesg)</h3>
  <pre>$(html_escape "$HW_ERRORS")</pre>
EOF
fi

if [[ -n "$AUTH_ERRORS" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>认证日志异常 (前10)</h3>
  <pre>$(html_escape "$AUTH_ERRORS")</pre>
EOF
fi

if [[ -n "$NTP_DETAIL" ]]; then
    cat >> "$REPORT_FILE" <<EOF
  <h3>NTP 时间源详情</h3>
  <pre>$(html_escape "$NTP_DETAIL")</pre>
EOF
fi

echo "</div>" >> "$REPORT_FILE"

# 报告尾部
cat >> "$REPORT_FILE" <<EOF
<div class="footer">
  巡检完成 | 警告: ${WARN_COUNT} | 严重: ${CRITICAL_COUNT} | 生成时间: $(date '+%Y-%m-%d %H:%M:%S') | linux_inspect.sh v2.0
</div>
</div>
</body>
</html>
EOF

# ======================== 终端输出汇总 ========================
echo ""
echo "========================================"
echo "  巡检完成: $(hostname)"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  警告数: ${YELLOW}${WARN_COUNT}${NC}"
echo -e "  严重数: ${RED}${CRITICAL_COUNT}${NC}"
echo "  报告: ${REPORT_FILE}"
echo "========================================"
echo ""

if (( CRITICAL_COUNT > 0 )); then
    exit 1
fi
exit 0
