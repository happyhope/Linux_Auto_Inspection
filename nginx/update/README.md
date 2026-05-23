# Nginx 平滑升级脚本

## 简介

本脚本用于实现 Nginx 的平滑热升级，支持在线下载源码升级、本地离线包升级、回滚等功能。

## 功能特性

- **在线升级**：自动下载指定版本源码进行编译升级
- **本地升级**：支持使用本地离线源码包进行升级
- **平滑升级**：通过 Nginx 信号机制实现热升级，业务不中断
- **自动回滚**：升级失败时支持快速回滚至原版本
- **配置校验**：升级前自动校验配置文件是否正常
- **多版本备份**：自动管理历史备份版本，默认保留3个
- **跨平台支持**：支持 macOS (Homebrew)、CentOS/RHEL/Rocky 和 Ubuntu/Debian 系统

## 环境要求

### Linux 系统
- CentOS/RHEL/Rocky 或 Ubuntu/Debian
- root 用户权限
- 足够的磁盘空间（建议至少 100MB 可用空间）
- 已安装 gcc、gcc-c++、pcre-devel、zlib-devel、openssl-devel、make、wget、tar

### macOS 系统
- macOS 10.14+
- Homebrew 已安装
- 足够的磁盘空间（建议至少 100MB 可用空间）
- Xcode Command Line Tools
- Homebrew 安装的依赖：gcc、pcre、openssl、zlib、make、wget、tar

**Homebrew 安装命令**：
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Homebrew 安装 Nginx**：
```bash
brew install nginx
```

## 快速开始

### 在线升级

```bash
bash nginx-upgrade.sh upgrade
```

### 本地升级

```bash
bash nginx-upgrade.sh local /path/to/nginx-1.31.0.tar.gz
```

### 回滚

```bash
bash nginx-upgrade.sh rollback
```

### 查看原有编译参数

```bash
bash nginx-upgrade.sh showargs
```

### 清理备份

```bash
bash nginx-upgrade.sh cleanbak
```

## 配置说明

脚本顶部的自定义配置区可修改以下参数：

```bash
NGINX_TARGET_VER="1.31.0"    # 目标升级版本
DEFAULT_SRC_DIR="/usr/local/src"  # 源码解压目录
MAX_BACKUP_NUM=3            # 最大备份保留数量
COMPILE_THREAD=$(nproc)     # 编译线程数
UPGRADE_LOG="/var/log/nginx_upgrade.log"  # 日志文件路径
```

## 工作流程

### 升级流程

1. 权限校验（必须使用 root 用户）
2. 检测已安装 Nginx 信息（二进制路径、prefix、编译参数）
3. 安装编译依赖
4. 下载/解压源码包
5. 执行 configure 和 make 编译
6. 备份旧版本二进制
7. 替换新版本二进制
8. 校验配置文件
9. 发送 USR2 信号触发平滑升级
10. 发送 WINCH 信号优雅关闭旧进程
11. 输出升级结果

### 回滚流程

1. 权限校验
2. 检测 Nginx 信息
3. 查找最新备份文件
4. 确认回滚操作
5. 替换二进制文件
6. 重载 Nginx 配置

## 日志说明

升级过程日志同时输出到控制台和日志文件：

```
/var/log/nginx_upgrade.log
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

## 注意事项

1. **权限要求**：Linux 必须使用 root 用户执行；macOS 无需 root 权限
2. **业务影响**：平滑升级期间对业务无感知，但建议在低峰期操作
3. **编译参数**：脚本自动保留原有编译参数，确保模块兼容性
4. **磁盘空间**：确保源码目录有足够空间（Linux: `/usr/local/src`，macOS: `/usr/local/src`）
5. **配置文件**：升级前会自动校验 nginx.conf 配置
6. **回滚确认**：执行回滚前需要手动确认
7. **macOS 限制**：Homebrew 安装的 nginx 可能无法保留原有模块，需要重新编译
8. **macOS 路径**：
   - Apple Silicon: `/opt/homebrew/sbin/nginx`
   - Intel: `/usr/local/sbin/nginx`

## 常见问题

### Q: 升级失败如何处理？

A: 脚本会自动回滚二进制文件到原版本。如需手动回滚，可执行：
```bash
mv /usr/local/nginx/sbin/nginx /usr/local/nginx/sbin/nginx.new
ls -t /usr/local/nginx/sbin/nginx.old_* | head -1 | xargs -I {} mv {} /usr/local/nginx/sbin/nginx
nginx -s reload
```

### Q: 如何查看升级历史？

A: 查看备份文件列表：
```bash
ls -lt /usr/local/nginx/sbin/nginx.old_*
```

### Q: 编译失败怎么办？

A: 检查日志文件 `/var/log/nginx_upgrade.log`，确认缺少的依赖并手动安装。

### Q: macOS 上找不到 nginx？

A: macOS 使用 Homebrew 安装的 nginx 通常位于：
- Apple Silicon (M1/M2/M3): `/opt/homebrew/sbin/nginx`
- Intel: `/usr/local/sbin/nginx`

使用 `which nginx` 或 `brew --prefix` 查看实际路径。

### Q: macOS 升级后如何启动 nginx？

A: Homebrew 安装的 nginx 可以通过以下方式管理：
```bash
brew services start nginx   # 启动
brew services stop nginx    # 停止
brew services restart nginx # 重启
```

## 目录结构

```
nginx/update/
├── nginx-upgrade.sh    # 主升级脚本
└── README.md           # 本文档
```

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0.0 | 2026-05-07 | 初始版本，支持在线/本地升级、回滚、备份管理 |
| 1.1.0 | 2026-05-07 | 新增 macOS (Homebrew) 系统支持 |
