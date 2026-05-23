#!/bin/bash
set -eo pipefail
clear

# ====================== 配置区 ======================
OPENRESTY_VERSION="1.29.2.4"
DEFAULT_SRC_DIR="/usr/local/src"
MAX_BACKUP_NUM=3
UPGRADE_LOG="/var/log/openresty_upgrade.log"
# ====================================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
info() { 
    echo -e "${GREEN}[INFO] $* ${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO $*" >> "$UPGRADE_LOG"
}

warn() { 
    echo -e "${YELLOW}[WARN] $* ${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN $*" >> "$UPGRADE_LOG"
}

error() { 
    echo -e "${RED}[ERROR] $* ${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR $*" >> "$UPGRADE_LOG"
    exit 1
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "必须使用 root 用户执行此脚本"
    fi
}

# 检查磁盘空间（单位：KB）
check_disk() {
    local check_dir=$1
    local required_kb=102400  # 100MB
    local free_kb
    
    free_kb=$(df -P "$check_dir" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -z "$free_kb" || ! "$free_kb" =~ ^[0-9]+$ ]]; then
        error "无法获取目录 $check_dir 的磁盘空间信息"
    fi
    
    if [[ "$free_kb" -lt "$required_kb" ]]; then
        error "目录 $check_dir 磁盘空间不足，需要至少 ${required_kb}KB，当前剩余 ${free_kb}KB"
    fi
    
    info "磁盘空间检查通过，剩余 $((free_kb / 1024))MB"
}

# 获取 CPU 核心数
get_cpu_cores() {
    local cores
    cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
    echo "$cores"
}

# 获取 Nginx/OpenResty 原有信息
get_nginx_info() {
    # 优先查找命令行 nginx，然后查找 openresty 目录下的
    NGINX_BIN=$(command -v nginx 2>/dev/null || find /usr/local/openresty -name nginx -path "*/sbin/nginx" 2>/dev/null | head -1)
    
    if [[ -z "$NGINX_BIN" ]]; then
        error "未找到 Nginx 二进制文件，请确保 OpenResty 已安装"
    fi
    
    # 获取 prefix 路径
    NGINX_PREFIX=$("$NGINX_BIN" -V 2>&1 | grep -oE '--prefix=[^ ]+' | cut -d'=' -f2)
    if [[ -z "$NGINX_PREFIX" ]]; then
        warn "未获取到 prefix，使用默认值 /usr/local/openresty/nginx"
        NGINX_PREFIX="/usr/local/openresty/nginx"
    fi
    
    PID_FILE="${NGINX_PREFIX}/logs/nginx.pid"
    
    # 获取原有编译参数（处理包含空格的参数）
    OLD_ARGS_RAW=$("$NGINX_BIN" -V 2>&1 | sed -n 's/.*configure arguments: //p')
    if [[ -z "$OLD_ARGS_RAW" ]]; then
        warn "未获取到原有编译参数，将使用默认配置"
        OLD_ARGS_RAW=""
    fi
    
    # 使用数组存储编译参数，正确处理空格
    OLD_CONF_ARRAY=()
    while IFS= read -r -d '' arg; do
        OLD_CONF_ARRAY+=("$arg")
    done < <(xargs printf '%s\0' <<< "$OLD_ARGS_RAW")
    
    info "Nginx 二进制路径：$NGINX_BIN"
    info "安装前缀：$NGINX_PREFIX"
    info "PID 文件：$PID_FILE"
    info "原有编译参数：${OLD_ARGS_RAW:0:100}${OLD_ARGS_RAW:100:+...}"
    
    # 检查 Nginx 是否正在运行
    if [[ -f "$PID_FILE" ]]; then
        PID_NUM=$(cat "$PID_FILE")
        if ps -p "$PID_NUM" &>/dev/null; then
            info "检测到 Nginx 正在运行，PID: $PID_NUM"
        else
            warn "PID 文件存在但进程未运行，可能是异常退出"
        fi
    else
        warn "未检测到 Nginx 运行进程（PID 文件不存在）"
    fi
}

# 安装编译依赖
install_deps() {
    info "检测并安装编译依赖..."
    
    if grep -qi -E "centos|rhel|rocky|almalinux|kylin" /etc/os-release 2>/dev/null; then
        if grep -qi "kylin" /etc/os-release 2>/dev/null; then
            info "检测到 麒麟 Kylin-V10 系统"
        else
            info "检测到 RHEL/CentOS/Rocky/AlmaLinux 系统"
        fi
        
        yum clean all &>/dev/null || warn "清理 yum 缓存失败"
        yum makecache &>/dev/null || warn "生成 yum 缓存失败"
        
        if yum install -y gcc gcc-c++ pcre-devel zlib-devel openssl-devel perl make wget tar &>/dev/null; then
            info "依赖安装成功"
        else
            warn "部分依赖安装可能失败，建议手动检查"
        fi
        
    elif grep -qi -E "ubuntu|debian" /etc/os-release 2>/dev/null; then
        info "检测到 Ubuntu/Debian 系统"
        
        if ! apt update -y &>/dev/null; then
            warn "apt update 失败，尝试继续"
        fi
        
        if apt install -y gcc g++ libpcre3-dev zlib1g-dev libssl-dev perl make wget tar &>/dev/null; then
            info "依赖安装成功"
        else
            warn "部分依赖安装可能失败，建议手动检查"
        fi
        
    else
        error "不支持当前 Linux 发行版，请手动安装编译依赖"
    fi
}

# 清理旧备份（保留最近 MAX_BACKUP_NUM 个）
clean_old_backups() {
    local backup_pattern="${NGINX_BIN}.old_*"
    local backup_list
    local backup_count
    
    # 获取备份文件列表（按时间排序，最新在前）
    backup_list=$(ls -t "$backup_pattern" 2>/dev/null)
    backup_count=$(echo "$backup_list" | wc -l)
    
    if [[ "$backup_count" -gt "$MAX_BACKUP_NUM" ]]; then
        local delete_count=$((backup_count - MAX_BACKUP_NUM))
        local delete_list
        
        delete_list=$(echo "$backup_list" | tail -n "$delete_count")
        
        if [[ -n "$delete_list" ]]; then
            echo "$delete_list" | xargs rm -f 2>/dev/null
            info "已清理 $delete_count 个过期备份文件"
        fi
    fi
}

# 核心编译 + 平滑升级
core_upgrade() {
    local src_build_dir=$(pwd)
    local bak_file
    local compile_threads
    
    # 检查磁盘空间
    check_disk "$DEFAULT_SRC_DIR"
    
    # 获取编译线程数
    compile_threads=$(get_cpu_cores)
    info "编译线程数：$compile_threads"
    
    # 清理编译缓存
    if [[ -f Makefile ]]; then
        info "清理旧编译缓存..."
        make clean &>/dev/null || warn "清理编译缓存失败"
    fi
    
    # 执行 configure
    info "执行 configure（使用原有参数）"
    if [[ ${#OLD_CONF_ARRAY[@]} -gt 0 ]]; then
        ./configure "${OLD_CONF_ARRAY[@]}" || error "configure 失败，请检查编译参数"
    else
        ./configure || error "configure 失败，请检查编译环境"
    fi
    
    # 编译
    info "开始编译，线程数：$compile_threads"
    if ! make -j"$compile_threads"; then
        error "编译失败，请检查错误信息"
    fi
    
    # 备份旧二进制
    bak_file="${NGINX_BIN}.old_$(date +%Y%m%d_%H%M%S)"
    info "备份旧版本到：$bak_file"
    mv "$NGINX_BIN" "$bak_file" || { error "备份旧版本失败"; }
    
    # 清理旧备份
    clean_old_backups
    
    # 复制新二进制
    info "复制新版本到：$NGINX_BIN"
    if [[ -f "build/nginx-*/objs/nginx" ]]; then
        cp "build/nginx-"*/objs/nginx "$NGINX_BIN"
    else
        error "未找到编译生成的 nginx 二进制文件"
    fi
    
    chmod 755 "$NGINX_BIN"
    
    # 配置文件检查
    info "校验 Nginx 配置文件..."
    if ! "$NGINX_BIN" -t; then
        warn "配置文件校验失败，正在回滚..."
        mv "$bak_file" "$NGINX_BIN"
        error "配置文件错误，已自动回滚到旧版本"
    fi
    
    # 平滑升级
    info "执行平滑热升级..."
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE")
        
        # 启动新版本
        kill -USR2 "$old_pid" || { warn "发送 USR2 信号失败"; }
        sleep 2
        
        # 优雅关闭旧版本工作进程
        if [[ -f "${PID_FILE}.oldbin" ]]; then
            local oldbin_pid=$(cat "${PID_FILE}.oldbin")
            kill -WINCH "$oldbin_pid" 2>/dev/null || true
            sleep 3
            
            # 等待旧进程退出，超时强制关闭
            if ps -p "$oldbin_pid" &>/dev/null; then
                warn "旧进程未正常退出，强制关闭"
                kill -9 "$oldbin_pid" 2>/dev/null || true
            fi
        else
            warn "未生成 oldbin 文件，跳过优雅关闭"
        fi
    else
        warn "PID 文件不存在，跳过平滑升级信号（新版本已复制）"
    fi
    
    info "升级完成！"
    echo -e "\n${BLUE}======== 新版本信息 ========${NC}"
    "$NGINX_BIN" -v
    echo -e "${BLUE}============================${NC}"
}

# 在线升级
online_upgrade() {
    local tar_file="openresty-${OPENRESTY_VERSION}.tar.gz"
    local tar_url="https://openresty.org/download/${tar_file}"
    
    check_root
    get_nginx_info
    install_deps
    
    # 进入源码目录
    info "进入源码目录：$DEFAULT_SRC_DIR"
    cd "$DEFAULT_SRC_DIR" || error "无法进入目录 $DEFAULT_SRC_DIR"
    
    # 下载源码包（如果不存在）
    if [[ ! -f "$tar_file" ]]; then
        info "下载 OpenResty ${OPENRESTY_VERSION}..."
        if ! wget -q "$tar_url"; then
            error "下载失败，请检查网络连接或手动下载"
        fi
    else
        info "本地已存在源码包，跳过下载"
    fi
    
    # 验证下载文件
    if [[ ! -f "$tar_file" ]]; then
        error "源码包不存在：$tar_file"
    fi
    
    # 解压源码
    info "解压源码包..."
    rm -rf "openresty-${OPENRESTY_VERSION}"
    if ! tar zxf "$tar_file"; then
        error "解压失败，文件可能损坏"
    fi
    
    # 进入源码目录
    cd "openresty-${OPENRESTY_VERSION}" || error "无法进入源码目录"
    
    # 执行升级
    core_upgrade
}

# 本地源码包升级
local_upgrade() {
    local local_tar_path="$1"
    
    # 参数校验
    if [[ -z "$local_tar_path" ]]; then
        error "用法：$0 local /路径/openresty-1.29.2.4.tar.gz"
    fi
    
    if [[ ! -f "$local_tar_path" ]]; then
        error "文件不存在：$local_tar_path"
    fi
    
    check_root
    get_nginx_info
    install_deps
    
    # 进入源码目录
    cd "$DEFAULT_SRC_DIR" || error "无法进入目录 $DEFAULT_SRC_DIR"
    
    # 获取解压后的目录名
    local src_dir_name
    src_dir_name=$(tar -tf "$local_tar_path" | head -1 | sed 's#/$##')
    
    if [[ -z "$src_dir_name" ]]; then
        error "无法获取源码目录名"
    fi
    
    # 清理旧目录
    rm -rf "$src_dir_name"
    
    # 解压源码
    info "解压本地源码包..."
    if ! tar zxf "$local_tar_path"; then
        error "解压失败，文件可能损坏"
    fi
    
    # 进入源码目录
    cd "$src_dir_name" || error "无法进入源码目录"
    
    # 执行升级
    core_upgrade
}

# 一键回滚
rollback() {
    local old_bin
    local confirm
    
    check_root
    get_nginx_info
    
    # 查找最新备份
    old_bin=$(ls -t "${NGINX_BIN}.old_"* 2>/dev/null | head -1)
    
    if [[ -z "$old_bin" ]]; then
        error "未找到备份文件，无法回滚"
    fi
    
    warn "即将回滚到备份版本：$old_bin"
    read -p "确定回滚？(y/N) " confirm
    
    if [[ "${confirm,,}" != "y" ]]; then
        info "已取消回滚操作"
        exit 0
    fi
    
    # 备份当前版本
    info "备份当前版本..."
    mv "$NGINX_BIN" "${NGINX_BIN}.new_$(date +%Y%m%d_%H%M%S)"
    
    # 恢复旧版本
    info "恢复备份版本..."
    mv "$old_bin" "$NGINX_BIN"
    chmod 755 "$NGINX_BIN"
    
    # 检查配置
    if ! "$NGINX_BIN" -t; then
        error "回滚后配置校验失败，请手动检查"
    fi
    
    # 重载配置
    "$NGINX_BIN" -s reload
    
    info "回滚成功！当前版本："
    "$NGINX_BIN" -v
}

# 查看原有编译参数
show_args() {
    check_root
    get_nginx_info
    
    echo -e "\n${GREEN}原有编译参数：${NC}"
    echo "$OLD_ARGS_RAW"
    echo -e "\n${GREEN}编译参数数组：${NC}"
    for i in "${!OLD_CONF_ARRAY[@]}"; do
        echo "  [$i] ${OLD_CONF_ARRAY[$i]}"
    done
}

# 帮助信息
show_help() {
cat << EOF
OpenResty 平滑升级脚本（Linux 版）

用法：
    $0 upgrade          在线升级 OpenResty 到 ${OPENRESTY_VERSION}
    $0 local  <路径>    使用本地源码包升级
    $0 rollback         一键回滚到上一个备份版本
    $0 showargs         查看当前 Nginx 的编译参数
    $0 help             显示此帮助信息

示例：
    $0 upgrade
    $0 local /data/openresty-1.29.2.4.tar.gz
    $0 rollback

配置说明：
    - 目标版本：${OPENRESTY_VERSION}
    - 源码目录：${DEFAULT_SRC_DIR}
    - 最大备份数：${MAX_BACKUP_NUM}
    - 日志文件：${UPGRADE_LOG}

注意事项：
    1. 必须使用 root 用户执行
    2. 升级过程会自动保留原有编译参数
    3. 支持 CentOS/RHEL/Rocky/AlmaLinux/Kylin-V10 和 Ubuntu/Debian
    4. 升级失败会自动回滚到原版本
EOF
}

# 主入口
case "$1" in
    upgrade)
        online_upgrade
        ;;
    local)
        local_upgrade "$2"
        ;;
    rollback)
        rollback
        ;;
    showargs)
        show_args
        ;;
    help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac