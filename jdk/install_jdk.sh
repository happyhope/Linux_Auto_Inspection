#!/bin/bash
# ============================================================================
# JDK 安装脚本
# 自动检测系统架构并安装相应版本的 JDK
# 支持 x86_64 和 aarch64 架构
# ============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统架构
detect_architecture() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 检查是否已安装 Java
check_java() {
    if command -v java &> /dev/null; then
        local version=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | sed 's/^1\.//' | cut -d'.' -f1)
        log_info "已安装 Java 版本: $version"
        return 0
    else
        return 1
    fi
}

# 安装 JDK
install_jdk() {
    local arch=$1
    local jdk_dir="/usr/local/java"
    local jdk_package
    
    # 选择合适的 JDK 包
    case "$arch" in
        x64)
            jdk_package="jdk_x64_linux_17.0.19_10.tar.gz"
            ;;
        aarch64)
            jdk_package="jdk_aarch64_linux_17.0.18_8.tar.gz"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    # 检查 JDK 包是否存在
    if [ ! -f "$jdk_package" ]; then
        log_error "JDK 安装包不存在: $jdk_package"
        exit 1
    fi
    
    # 创建安装目录
    if [ ! -d "$jdk_dir" ]; then
        log_info "创建 JDK 安装目录: $jdk_dir"
        sudo mkdir -p "$jdk_dir"
    fi
    
    # 解压 JDK 包
    log_info "解压 JDK 安装包..."
    local jdk_version=$(basename "$jdk_package" .tar.gz)
    local install_path="$jdk_dir/$jdk_version"
    
    if [ -d "$install_path" ]; then
        log_warn "JDK 已存在于: $install_path，将覆盖安装"
        sudo rm -rf "$install_path"
    fi
    
    sudo tar -xzf "$jdk_package" -C "$jdk_dir"
    
    # 配置 alternatives
    log_info "配置 alternatives..."
    local java_bin="$install_path/bin/java"
    local javac_bin="$install_path/bin/javac"
    
    # 检查 alternatives 是否存在
    if ! command -v alternatives &> /dev/null; then
        log_warn "alternatives 命令不可用，将使用 ln 命令创建链接"
        sudo ln -sf "$java_bin" /usr/bin/java
        sudo ln -sf "$javac_bin" /usr/bin/javac
        log_info "已创建 Java 链接"
    else
        # 使用 alternatives 配置
        sudo alternatives --install /usr/bin/java java "$java_bin" 1
        sudo alternatives --install /usr/bin/javac javac "$javac_bin" 1
        
        # 提示用户选择默认 Java 版本
        log_info "配置默认 Java 版本..."
        sudo alternatives --config java
    fi
    
    # 设置 JAVA_HOME 环境变量
    log_info "设置 JAVA_HOME 环境变量..."
    local java_home_config="/etc/profile.d/java.sh"
    cat << EOF | sudo tee "$java_home_config"
#!/bin/bash
export JAVA_HOME="$install_path"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
    
    sudo chmod +x "$java_home_config"
    
    # 使环境变量生效
    source "$java_home_config"
    
    log_info "JDK 安装完成！"
    log_info "Java 版本: $(java -version 2>&1 | head -1)"
    log_info "JAVA_HOME: $JAVA_HOME"
}

# 主函数
main() {
    log_info "开始安装 JDK..."
    
    # 检查是否已安装 Java
    if check_java; then
        log_warn "Java 已安装，是否继续安装？(y/n)"
        read -r answer
        if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
            log_info "安装取消"
            exit 0
        fi
    fi
    
    # 检测系统架构
    local arch=$(detect_architecture)
    log_info "检测到系统架构: $arch"
    
    # 安装 JDK
    install_jdk "$arch"
    
    log_info "JDK 安装脚本执行完成！"
}

# 执行主函数
main