#!/bin/bash
set -eo pipefail
# ====================== 自定义配置区 ======================
NGINX_TARGET_VER="1.31.0"
DEFAULT_SRC_DIR="/usr/local/src"
MAX_BACKUP_NUM=3          # 最大保留备份数
UPGRADE_LOG="/var/log/nginx_upgrade.log"
# ==========================================================

# 检测操作系统类型
detect_os() {
    if [[ "$(uname)" == "Darwin" ]]; then
        IS_MACOS=true
        IS_LINUX=false
    else
        IS_MACOS=false
        IS_LINUX=true
    fi
}

# 获取CPU线程数
get_compile_thread() {
    if [[ "${IS_MACOS}" == "true" ]]; then
        echo $(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    else
        echo $(nproc 2>/dev/null || echo 4)
    fi
}

COMPILE_THREAD=$(get_compile_thread)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 通用函数
info() { echo -e "${GREEN}[INFO] $* ${NC}"; echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [INFO] $*" >> ${UPGRADE_LOG}; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}"; echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [WARN] $*" >> ${UPGRADE_LOG}; }
error() { echo -e "${RED}[ERROR] $* ${NC}"; echo "[$(date +%Y-%m-%d\ %H:%M:%S)] [ERROR] $*" >> ${UPGRADE_LOG}; exit 1; }

# 权限校验
check_root() {
    if [[ "${IS_MACOS}" == "true" ]]; then
        return 0
    fi
    [[ $EUID -ne 0 ]] && error "必须使用root用户执行脚本"
}

# 磁盘空间校验
check_disk() {
    local check_dir=$1
    local free_size
    if [[ "${IS_MACOS}" == "true" ]]; then
        free_size=$(df -k ${check_dir} 2>/dev/null | awk 'NR==2{print $4}')
    else
        free_size=$(df -P ${check_dir} | awk 'NR==2{print $4}')
    fi
    if [[ ${free_size} -lt 102400 ]];then
        error "目录${check_dir}磁盘剩余空间不足100M，无法编译升级"
    fi
}

# 获取nginx完整信息
get_nginx_base_info() {
    if [[ "${IS_MACOS}" == "true" ]]; then
        if [[ -f "/opt/homebrew/sbin/nginx" ]]; then
            NGINX_BIN="/opt/homebrew/sbin/nginx"
        elif [[ -f "/usr/local/sbin/nginx" ]]; then
            NGINX_BIN="/usr/local/sbin/nginx"
        else
            NGINX_BIN=$(command -v nginx 2>/dev/null)
        fi
    else
        NGINX_BIN=$(command -v nginx 2>/dev/null || find / -name nginx -path "*/sbin/nginx" 2>/dev/null | head -1)
    fi
    [[ -z "${NGINX_BIN}" ]] && error "未检测到已安装Nginx，请先安装Nginx"

    # 获取prefix路径
    NGINX_PREFIX=$(${NGINX_BIN} -V 2>&1 | grep -oE '--prefix=[^ ]+' | cut -d'=' -f2)
    if [[ -z "${NGINX_PREFIX}" ]]; then
        if [[ "${IS_MACOS}" == "true" ]]; then
            NGINX_PREFIX="/opt/homebrew/etc/nginx"
        else
            NGINX_PREFIX="/usr/local/nginx"
        fi
    fi
    PID_FILE="${NGINX_PREFIX}/logs/nginx.pid"

    # 数组存储编译参数，解决空格异常
    local raw_args
    raw_args=$(${NGINX_BIN} -V 2>&1 | sed -n 's/.*configure arguments: //p')
    OLD_CONF_ARRAY=(${raw_args})
    OLD_CONF_STR="${raw_args}"

    # 检测nginx是否运行（macOS使用pgrep）
    if [[ "${IS_MACOS}" == "true" ]]; then
        if pgrep -f "nginx: master" &>/dev/null; then
            info "检测到Nginx正在运行"
        else
            warn "未检测到Nginx运行进程"
        fi
    else
        if [[ -f ${PID_FILE} ]];then
            PID_NUM=$(cat ${PID_FILE})
            if ! ps -p ${PID_NUM} &>/dev/null;then
                warn "Nginx pid文件存在但进程未运行"
            fi
        else
            warn "未检测到Nginx运行进程"
        fi
    fi

    info "Nginx二进制路径：${NGINX_BIN}"
    info "Nginx安装前缀：${NGINX_PREFIX}"
    info "Nginx PID文件路径：${PID_FILE}"
    info "原有完整编译参数：${OLD_CONF_STR}"
}

# 安装编译依赖
install_compile_deps() {
    info "开始检测并安装编译依赖"
    if [[ "${IS_MACOS}" == "true" ]]; then
        if ! command -v brew &>/dev/null; then
            error "Homebrew未安装，请先安装Homebrew：https://brew.sh"
        fi
        brew install gcc pcre openssl zlib make wget tar 2>/dev/null || {
            warn "部分依赖可能已安装或安装失败"
        }
    elif grep -qi "centos\|rhel\|rocky\|kylin" /etc/os-release;then
        yum clean all && yum makecache &>/dev/null
        yum install -y gcc gcc-c++ pcre-devel zlib-devel openssl-devel make wget tar &>/dev/null
    elif grep -qi "ubuntu\|debian" /etc/os-release;then
        apt update -y &>/dev/null
        apt install -y gcc g++ libpcre3-dev zlib1g-dev libssl-dev make wget tar &>/dev/null
    else
        error "暂不支持当前系统依赖安装，请手动安装编译环境"
    fi
    info "依赖安装完成"
}

# 清理旧备份文件
clear_old_backup() {
    local bin_path=$1
    local bak_list
    bak_list=$(ls -lt ${bin_path}.old_* 2>/dev/null | awk '{print $9}')
    local bak_count
    bak_count=$(echo "${bak_list}" | wc -l)
    if [[ ${bak_count} -gt ${MAX_BACKUP_NUM} ]];then
        local del_num=$((bak_count - MAX_BACKUP_NUM))
        echo "${bak_list}" | tail -${del_num} | xargs rm -f
        info "已清理${del_num}个过期Nginx备份文件"
    fi
}

# 二进制备份+替换+平滑升级核心
core_smooth_upgrade() {
    local src_build_dir=$1
    check_disk "${DEFAULT_SRC_DIR}"

    # 清理编译缓存
    [[ -f ./Makefile ]] && make clean &>/dev/null

    info "开始执行configure编译配置"
    ./configure "${OLD_CONF_ARRAY[@]}" || error "configure编译配置失败"

    info "多线程编译中，线程数：${COMPILE_THREAD}"
    make -j${COMPILE_THREAD} || error "make源码编译失败"

    # 备份旧程序
    local bak_file="${NGINX_BIN}.old_$(date +%Y%m%d_%H%M%S)"
    mv "${NGINX_BIN}" "${bak_file}"
    clear_old_backup "${NGINX_BIN}"

    # 替换新二进制
    cp ${src_build_dir}/objs/nginx "${NGINX_BIN}"
    chmod 755 "${NGINX_BIN}"

    # 配置校验
    info "校验Nginx配置文件"
    ${NGINX_BIN} -t || { mv "${bak_file}" "${NGINX_BIN}"; error "配置文件异常，已回滚二进制"; }

    # 平滑升级
    info "执行Nginx平滑热升级"
    if [[ "${IS_MACOS}" == "true" ]]; then
        local nginx_pid=$(pgrep -f "nginx: master" | head -1)
        if [[ -n "${nginx_pid}" ]]; then
            kill -USR2 ${nginx_pid}
            sleep 2
            local old_pid=$(pgrep -f "nginx: master" | tail -1)
            if [[ -n "${old_pid}" ]]; then
                kill -WINCH ${old_pid}
                sleep 3
                if pgrep -f "nginx: master" | grep -q "${old_pid}" 2>/dev/null; then
                    kill -9 ${old_pid} 2>/dev/null || true
                fi
            fi
        else
            warn "未找到运行中的Nginx主进程，跳过平滑升级信号"
        fi
    else
        if [[ -f ${PID_FILE} ]];then
            kill -USR2 $(cat ${PID_FILE})
            sleep 2
            if [[ -f "${PID_FILE}.oldbin" ]];then
                kill -WINCH $(cat ${PID_FILE}.oldbin)
                sleep 3
                # 超时强制关闭旧进程
                if ps -p $(cat ${PID_FILE}.oldbin) &>/dev/null;then
                    kill -9 $(cat ${PID_FILE}.oldbin) 2>/dev/null || true
                fi
            fi
        fi
    fi

    info "平滑升级执行完毕"
    echo -e "\n${BLUE}========== 升级后版本信息 ==========${NC}"
    ${NGINX_BIN} -v
    echo -e "${BLUE}==================================${NC}"
}

# 在线下载源码升级
func_upgrade_online() {
    detect_os
    if [[ "${IS_MACOS}" == "true" ]]; then
        DEFAULT_SRC_DIR="/usr/local/src"
    fi
    check_root
    get_nginx_base_info
    install_compile_deps

    cd ${DEFAULT_SRC_DIR}
    local tar_name="nginx-${NGINX_TARGET_VER}.tar.gz"
    local tar_url="http://nginx.org/download/${tar_name}"

    [[ ! -f ${tar_name} ]] && wget -q ${tar_url} || info "本地已存在目标源码包"
    rm -rf nginx-${NGINX_TARGET_VER}
    tar -zxf ${tar_name}
    cd nginx-${NGINX_TARGET_VER}

    core_smooth_upgrade "$(pwd)"
}

# 本地指定源码包升级
func_upgrade_local() {
    local local_tar_path="$1"
    [[ -z "${local_tar_path}" ]] && error "请传入本地源码包绝对路径"
    [[ ! -f "${local_tar_path}" ]] && error "本地源码包不存在：${local_tar_path}"

    detect_os
    if [[ "${IS_MACOS}" == "true" ]]; then
        DEFAULT_SRC_DIR="/usr/local/src"
    fi
    check_root
    get_nginx_base_info
    install_compile_deps

    cd ${DEFAULT_SRC_DIR}
    local src_dir_name
    src_dir_name=$(tar -tf "${local_tar_path}" | head -1 | sed 's#/$##')
    rm -rf ${src_dir_name}
    tar -zxf "${local_tar_path}"
    cd ${src_dir_name}

    core_smooth_upgrade "$(pwd)"
}

# 一键回滚
func_rollback() {
    detect_os
    check_root
    get_nginx_base_info
    local bak_file
    bak_file=$(ls -t ${NGINX_BIN}.old_* 2>/dev/null | head -1)
    [[ -z "${bak_file}" ]] && error "未找到任何Nginx历史备份，无法回滚"

    warn "即将回滚至备份版本：${bak_file}"
    read -p "确认回滚？(y/N) :" confirm
    [[ ${confirm,,} != "y" ]] && info "取消回滚操作" && exit 0

    mv "${NGINX_BIN}" "${NGINX_BIN}.new_tmp"
    mv "${bak_file}" "${NGINX_BIN}"
    chmod 755 "${NGINX_BIN}"

    ${NGINX_BIN} -s reload
    info "回滚成功，当前版本："
    ${NGINX_BIN} -v
}

# 仅查看原有编译参数
func_show_args() {
    detect_os
    check_root
    get_nginx_base_info
    echo -e "\n${GREEN}原有Nginx完整编译参数：${NC}"
    echo "${OLD_CONF_STR}"
}

# 清理所有备份
func_clean_backup() {
    detect_os
    check_root
    get_nginx_base_info
    rm -f ${NGINX_BIN}.old_*
    info "已清空所有Nginx二进制备份文件"
}

# 帮助菜单
show_help() {
cat << EOF
用法：$0 [操作] [参数]
操作列表：
    upgrade          在线下载源码升级至配置指定版本
    local 路径       使用本地离线nginx源码包升级
    rollback         一键回滚至上一个稳定版本
    showargs         仅查看原有Nginx编译参数
    cleanbak         清理所有旧版本备份文件
示例：
    $0 upgrade
    $0 local /data/nginx-1.31.0.tar.gz
    $0 rollback
EOF
}

# 入口判断
case "$1" in
    upgrade)
        func_upgrade_online
        ;;
    local)
        func_upgrade_local "$2"
        ;;
    rollback)
        func_rollback
        ;;
    showargs)
        func_show_args
        ;;
    cleanbak)
        func_clean_backup
        ;;
    *)
        show_help
        exit 1
        ;;
esac