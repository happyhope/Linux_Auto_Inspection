# OpenResty 平滑升级脚本

## 简介

本脚本用于实现 OpenResty/Nginx 的平滑热升级，支持在线下载源码升级、本地离线包升级、一键回滚等功能。

## 功能特性

- **在线升级**：自动下载指定版本源码进行编译升级
- **本地升级**：支持使用本地离线源码包进行升级
- **平滑升级**：通过 Nginx 信号机制实现热升级，业务不中断
- **一键回滚**：升级失败或出现问题时支持快速回滚至原版本
- **配置校验**：升级前自动校验配置文件是否正常
- **多版本备份**：自动管理历史备份版本，默认保留3个
- **编译参数保留**：自动保留原有编译参数，确保模块兼容性
- **跨平台支持**：支持 CentOS/RHEL/Rocky/AlmaLinux/Kylin-V10 和 Ubuntu/Debian

## 环境要求

### 系统要求
- Linux 操作系统（CentOS/RHEL/Rocky/AlmaLinux/Kylin-V10 或 Ubuntu/Debian）
- root 用户权限
- 至少 100MB 可用磁盘空间
- 已安装必要的编译依赖

### 编译依赖
- gcc / gcc-c++
- pcre-devel / libpcre3-dev
- zlib-devel / zlib1g-dev
- openssl-devel / libssl-dev
- perl
- make
- wget
- tar

## 快速开始

### 在线升级

```bash
bash openrestry-upgrade.sh upgrade
```

### 本地升级

```bash
bash openrestry-upgrade.sh local /path/to/openresty-1.29.2.4.tar.gz
```

### 一键回滚

```bash
bash openrestry-upgrade.sh rollback
```

### 查看原有编译参数

```bash
bash openrestry-upgrade.sh showargs
```

### 显示帮助

```bash
bash openrestry-upgrade.sh help
```

## 配置说明

脚本顶部的配置区可修改以下参数：

```bash
OPENRESTY_VERSION="1.29.2.4"    # 目标升级版本
DEFAULT_SRC_DIR="/usr/local/src" # 源码解压目录
MAX_BACKUP_NUM=3                # 最大备份保留数量
UPGRADE_LOG="/var/log/openresty_upgrade.log"  # 日志文件路径
```

## 工作流程

### 升级流程

1. **权限校验**：必须使用 root 用户执行
2. **信息收集**：检测已安装 Nginx 信息（二进制路径、prefix、编译参数）
3. **依赖安装**：自动安装编译所需依赖
4. **源码处理**：下载/解压源码包
5. **编译配置**：执行 configure（保留原有参数）
6. **源码编译**：多线程编译（自动检测 CPU 核心数）
7. **版本备份**：备份旧版本二进制文件
8. **版本替换**：复制新版本二进制文件
9. **配置校验**：使用 `nginx -t` 校验配置
10. **平滑升级**：发送 USR2/WINCH 信号实现热升级
11. **结果输出**：显示升级后的版本信息

### 回滚流程

1. **权限校验**：必须使用 root 用户执行
2. **信息收集**：检测当前 Nginx 信息
3. **备份查找**：查找最新备份文件
4. **确认操作**：交互式确认是否回滚
5. **版本恢复**：恢复备份版本到当前位置
6. **配置校验**：校验回滚后的配置
7. **配置重载**：执行 `nginx -s reload`

## 日志说明

升级过程日志同时输出到控制台和日志文件：

```
/var/log/openresty_upgrade.log
```

日志格式：`[时间] [级别] 消息`

## 信号说明

脚本使用以下 Nginx 信号实现平滑升级：

| 信号 | 说明 |
|------|------|
| USR2 | 启动新版本主进程，实现热升级 |
| WINCH | 优雅关闭旧版本工作进程 |
| -9 | 超时后强制关闭残留旧进程 |

## 备份管理

- 备份文件命名格式：`nginx.old_YYYYMMDD_HHMMSS`
- 默认保留最近 3 个备份
- 超出数量自动清理最旧备份

## 支持的系统

| 系统类型 | 发行版 | 包管理器 |
|---------|--------|---------|
| RPM 系 | CentOS / RHEL / Rocky / AlmaLinux / Kylin-V10 | yum |
| DEB 系 | Ubuntu / Debian | apt |

## 注意事项

1. **权限要求**：必须使用 root 用户执行
2. **业务影响**：平滑升级期间对业务无感知，但建议在低峰期操作
3. **编译参数**：脚本自动保留原有编译参数，确保模块兼容性
4. **磁盘空间**：确保 `/usr/local/src` 目录有至少 100MB 可用空间
5. **配置文件**：升级前会自动校验 nginx.conf 配置，失败自动回滚
6. **回滚确认**：执行回滚前需要手动确认
7. **网络要求**：在线升级需要能够访问 `https://openresty.org`

## 常见问题

### Q: 升级失败如何处理？

A: 脚本会自动回滚二进制文件到原版本。如需手动回滚，可执行：
```bash
bash openrestry-upgrade.sh rollback
```

### Q: 如何查看升级历史？

A: 查看备份文件列表：
```bash
ls -lt /usr/local/openresty/nginx/sbin/nginx.old_*
```

### Q: 编译失败怎么办？

A: 检查日志文件 `/var/log/openresty_upgrade.log`，确认缺少的依赖并手动安装。

### Q: 麒麟 Kylin-V10 系统需要特殊配置吗？

A: 不需要，脚本会自动检测麒麟系统并使用 yum 安装依赖。

## 目录结构

```
openrestry/update/
├── openrestry-upgrade.sh    # 主升级脚本
└── README.md                # 本文档
```

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0.0 | 2026-05-20 | 初始版本，支持在线/本地升级、回滚、备份管理 |
| 1.1.0 | 2026-05-20 | 新增麒麟 Kylin-V10 系统支持 |
