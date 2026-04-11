# Linux Auto Inspection

**Linux 服务器一键巡检脚本** — 纯 Bash 编写，零依赖，自动生成高颜值 HTML 巡检报告。

[![Shell](https://img.shields.io/badge/Shell-Bash-green)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux-orange)]()

---

## 功能概览

一条命令完成服务器巡检，覆盖 **20+ 项检查维度**，输出标准化 HTML 报告。

```
========================================
  巡检完成: web-server-01
  时间: 2026-04-08 10:30:00
  警告数: 2
  严重数: 0
  报告: /tmp/inspect_report/inspect_web-server-01_20260408_103000.html
========================================
```

### 报告效果

报告采用现代卡片式设计，顶部 6 个概览指标，内容分区展示：

```
 ┌──────┬──────┬──────┬──────┬──────┬──────┐
 │ CPU  │ 内存 │ 磁盘 │ 负载 │ TCP  │ 警告 │
 │ 23%  │ 67%  │  0   │ 0.8  │ 156  │  2   │
 │  ●   │  ●   │  ●   │  ●   │  ●   │  ●   │
 └──────┴──────┴──────┴──────┴──────┴──────┘
  绿色=正常    橙色=警告    红色=严重
```

---

## 检查维度

### 基础信息
| 检查项 | 说明 |
|--------|------|
| 主机信息 | 主机名、FQDN、IP 地址、操作系统、内核、架构 |
| 硬件信息 | 厂商、型号、序列号、BIOS 版本 |
| 虚拟化检测 | 自动识别 VMware / KVM / Hyper-V / Xen / 物理机 |
| 运行状态 | 运行时间、启动时间、时区、当前登录用户 |
| 进程概况 | 进程总数、线程总数 |

### CPU & 负载
| 检查项 | 说明 |
|--------|------|
| CPU 使用率 | **4 种采集方式自动降级**（top → mpstat → vmstat → /proc/stat） |
| 系统负载 | 1 / 5 / 15 分钟负载，对比核数告警 |
| 运行队列 | 当前运行中 / 总进程数 |
| TOP 10 进程 | CPU 占用最高的 10 个进程 |

### 内存 & Swap
| 检查项 | 说明 |
|--------|------|
| 内存使用率 | 使用率 + `free` 详细输出 |
| Swap 使用率 | Swap 总量 / 已用 / 使用率 |
| TOP 10 进程 | 内存占用最高的 10 个进程 |

### 磁盘
| 检查项 | 说明 |
|--------|------|
| 空间使用率 | 所有挂载点，带进度条和状态徽章 |
| Inode 使用率 | Inode 占用检查 |
| 磁盘 I/O | iostat 统计 TPS / 读写速率 |
| 大文件 TOP 10 | 扫描 >100M 的大文件 |
| 近期大文件 | 7 天内修改的 >50M 文件 |
| 目录大小 | `/tmp` 和 `/var/log` 大小 |

### 文件描述符
| 检查项 | 说明 |
|--------|------|
| 系统 FD | 当前值 / 最大值 / 使用率 |
| TOP 5 进程 | FD 占用最多的 5 个进程 |

### 网络
| 检查项 | 说明 |
|--------|------|
| 网卡信息 | IP、MAC、速率、流量统计（RX/TX）、错误 / 丢包数 |
| TCP 连接 | ESTABLISHED / TIME_WAIT / CLOSE_WAIT / SYN_RECV / LISTEN |
| 监听端口 | 前 30 个监听端口 + 对应进程 |
| 路由表 | `ip route` 路由条目 |
| DNS / 网关 | DNS 服务器配置、默认网关 |

### 进程
| 检查项 | 说明 |
|--------|------|
| 僵尸进程 (Z) | 数量 + 详情列表 |
| D 状态进程 | 不可中断睡眠进程检测 |
| 长期运行进程 | 运行时间最长的 TOP 5 |

### 服务状态
| 检查项 | 说明 |
|--------|------|
| 关键服务 | **38 个常见服务**状态检测 |
| 失败的服务 | `systemctl --failed` 输出 |

<details>
<summary>支持检测的服务列表（点击展开）</summary>

`sshd` `crond` `cron` `rsyslog` `syslog-ng` `firewalld` `ufw` `chronyd` `ntpd` `systemd-timesyncd` `docker` `containerd` `kubelet` `nginx` `httpd` `apache2` `mysqld` `mariadb` `postgresql` `redis-server` `redis` `mongod` `elasticsearch` `php-fpm` `tomcat` `supervisord` `zabbix-agent` `zabbix-agent2` `node_exporter` `prometheus` `grafana-server` `haproxy` `keepalived` `named` `dnsmasq` `postfix` `dovecot` `vsftpd` `smbd`

</details>

### Docker 容器
| 检查项 | 说明 |
|--------|------|
| 容器列表 | 名称、镜像、运行状态 |
| 镜像列表 | 镜像名 + 大小（前 15） |
| 磁盘占用 | `docker system df` |

### 定时任务
| 检查项 | 说明 |
|--------|------|
| 系统 crontab | `/etc/crontab` 和 `/etc/cron.d/` |
| 用户 crontab | 所有用户的 crontab |

### 安全检查
| 检查项 | 说明 |
|--------|------|
| SSH 配置 | Root 登录、端口、最大认证次数、密钥认证 |
| 账户审计 | UID=0 账户、可登录 Shell 账户数 |
| 密码过期 | 即将过期 / 已过期账户 |
| 登录记录 | 最近失败记录（前 10）+ 失败总次数 + 成功记录 |
| 文件权限 | SUID 文件、全局可写文件扫描 |
| 安全组件 | SELinux 状态、防火墙状态 |

### 内核参数
检查 **13 项关键 sysctl 参数**，含当前值和建议值：

| 参数 | 说明 |
|------|------|
| `net.ipv4.tcp_syncookies` | TCP SYN Cookies |
| `net.ipv4.ip_forward` | IP 转发 |
| `net.ipv4.tcp_max_syn_backlog` | SYN 队列长度 |
| `net.core.somaxconn` | Socket 最大连接队列 |
| `net.ipv4.tcp_tw_reuse` | TIME_WAIT 重用 |
| `net.ipv4.tcp_fin_timeout` | FIN 超时 |
| `net.ipv4.tcp_keepalive_time` | Keepalive 时间 |
| `net.core.netdev_max_backlog` | 网卡积压队列 |
| `vm.swappiness` | Swap 倾向 |
| `vm.overcommit_memory` | 内存过量分配 |
| `fs.file-max` | 系统最大文件描述符 |
| `net.ipv4.conf.all.rp_filter` | 反向路径过滤 |
| `kernel.panic` | 内核 panic 重启 |

### 系统更新
| 检查项 | 说明 |
|--------|------|
| 可用更新 | yum / dnf / apt 可用更新数 |
| 安全更新 | 安全相关更新数 |
| 最近更新 | 上次安装/更新包时间 |

### 日志检查
| 检查项 | 说明 |
|--------|------|
| 系统日志 | error / fail / critical / panic / oom 关键字 |
| OOM 事件 | dmesg 中 OOM 次数 |
| 硬件错误 | dmesg 中 ECC / IO error / hardware error |
| 认证日志 | auth.log / secure 异常记录 |
| NTP 详情 | chrony sources 时间源信息 |

---

## 快速开始

### 环境要求

- Linux 系统（CentOS 7/8, RHEL 7/8/9, Ubuntu 18/20/22, Debian 10/11/12）
- Bash 4.0+
- root 权限（建议，部分检查项需要）

### 使用方式

```bash
# 1. 克隆仓库
git clone https://github.com/Aidan-996/Linux_Auto_Inspection.git

# 2. 赋权
cd Linux_Auto_Inspection
chmod +x linux_inspect.sh

# 3. 执行巡检
./linux_inspect.sh

# 4. 查看报告（输出路径在终端最后几行）
# 下载 /tmp/inspect_report/inspect_xxx.html 到本地浏览器打开
```

### 单行命令（无需克隆）

```bash
curl -sO https://raw.githubusercontent.com/Aidan-996/Linux_Auto_Inspection/main/linux_inspect.sh && chmod +x linux_inspect.sh && ./linux_inspect.sh
```

---

## 配置说明

脚本顶部有集中配置区，按实际环境调整：

```bash
# 阈值设置
CPU_WARN=80          # CPU 使用率告警阈值(%)
MEM_WARN=85          # 内存使用率告警阈值(%)
DISK_WARN=85         # 磁盘使用率告警阈值(%)
INODE_WARN=85        # Inode 使用率告警阈值(%)
SWAP_WARN=50         # Swap 使用率告警阈值(%)
FD_WARN=80           # 文件描述符使用率告警阈值(%)
LOAD_WARN_FACTOR=2   # 负载告警倍数(相对于CPU核数)
ZOMBIE_WARN=0        # 僵尸进程告警阈值
LOG_LINES=20         # 日志检查行数
LARGE_FILE_SIZE="+100M"  # 大文件扫描阈值

# 报告输出目录
REPORT_DIR="/tmp/inspect_report"
```

### 三级告警机制

| 级别 | 条件 | 颜色 |
|------|------|------|
| 正常 | < 阈值 | 绿色 |
| 警告 | >= 阈值 | 橙色 |
| 严重 | >= 阈值 + 10% | 红色 |

---

## 进阶用法

### 定时巡检 + 邮件通知

```bash
# crontab -e
# 每天早上 8 点巡检并发送报告
0 8 * * * /opt/scripts/linux_inspect.sh && \
  REPORT=$(ls -t /tmp/inspect_report/*.html | head -1) && \
  echo "巡检报告见附件" | mail -s "$(hostname) 每日巡检报告" \
  -a "$REPORT" admin@company.com
```

### 批量巡检

```bash
#!/bin/bash
SERVERS="192.168.1.10 192.168.1.11 192.168.1.12"
mkdir -p ./reports

for ip in $SERVERS; do
    echo "=== 巡检: $ip ==="
    ssh root@$ip 'bash -s' < linux_inspect.sh
    scp root@$ip:/tmp/inspect_report/*.html ./reports/
done

echo "所有巡检完成，报告保存在 ./reports/"
```

### Ansible 批量巡检

```yaml
# inspect.yml
- hosts: all
  become: yes
  tasks:
    - name: Upload inspect script
      copy:
        src: linux_inspect.sh
        dest: /tmp/linux_inspect.sh
        mode: '0755'

    - name: Run inspection
      shell: /tmp/linux_inspect.sh
      register: result
      ignore_errors: yes

    - name: Fetch report
      fetch:
        src: "{{ result.stdout_lines[-2] | regex_replace('.*报告: ', '') | trim }}"
        dest: "./reports/{{ inventory_hostname }}/"
        flat: yes
```

### 企业微信告警

在脚本末尾追加：

```bash
if (( CRITICAL_COUNT > 0 )); then
    curl -s -X POST "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"msgtype\": \"markdown\",
        \"markdown\": {
            \"content\": \"## 服务器巡检告警\n> 主机: $(hostname)\n> IP: $(hostname -I | awk '{print \$1}')\n> 严重: ${CRITICAL_COUNT} | 警告: ${WARN_COUNT}\n> 请及时处理！\"
        }
    }"
fi
```

### 钉钉告警

```bash
if (( CRITICAL_COUNT > 0 )); then
    curl -s -X POST "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"msgtype\": \"markdown\",
        \"markdown\": {
            \"title\": \"巡检告警\",
            \"text\": \"## 服务器巡检告警\n- 主机: $(hostname)\n- 严重: ${CRITICAL_COUNT}\n- 警告: ${WARN_COUNT}\n- 请及时处理\"
        }
    }"
fi
```

---

## 技术细节

### CPU 采集兼容性

CPU 使用率采集实现了 4 种方式自动降级，确保在任何发行版上都能正确获取：

```
top → mpstat → vmstat → /proc/stat
```

同时做了 0-100 范围限制，防止异常值。

### 脚本特点

| 特性 | 说明 |
|------|------|
| 零依赖 | 纯 Bash 编写，无需 Python / Perl / 额外工具 |
| 1100+ 行 | 覆盖 20+ 项检查维度 |
| HTML 报告 | 现代卡片式设计，浏览器直接打开 |
| 三级告警 | 正常 / 警告 / 严重，颜色区分 |
| 容错处理 | 每个采集项都有兜底，不会因单项失败中断 |
| HTML 转义 | 防止特殊字符破坏报告格式 |
| set -euo pipefail | 严格模式，及早发现错误 |

---

## 兼容性

| 发行版 | 版本 | 状态 |
|--------|------|------|
| CentOS | 7 / 8 / Stream | 已测试 |
| RHEL | 7 / 8 / 9 | 已测试 |
| Ubuntu | 18.04 / 20.04 / 22.04 | 已测试 |
| Debian | 10 / 11 / 12 | 已测试 |
| Rocky Linux | 8 / 9 | 兼容 |
| AlmaLinux | 8 / 9 | 兼容 |

---

## 目录结构

```
Linux_Auto_Inspection/
├── linux_inspect.sh      # 巡检脚本（主文件）
├── README.md             # 项目说明
└── LICENSE               # 开源协议
```

---

## 更新日志

### v2.0 (2026-04-08)
- 新增：硬件信息采集（厂商/型号/序列号/BIOS）
- 新增：虚拟化自动检测
- 新增：磁盘 I/O 统计
- 新增：大文件扫描（TOP 10 + 近期修改）
- 新增：文件描述符使用率 + TOP 5 进程
- 新增：网卡流量统计（RX/TX）、错误/丢包
- 新增：D 状态进程检测
- 新增：运行最长进程 TOP 5
- 新增：Docker 容器/镜像/磁盘占用
- 新增：定时任务采集（系统 + 用户）
- 新增：13 项内核参数检查
- 新增：账户安全审计（UID=0/Shell/密码过期）
- 新增：SSH 扩展检查（MaxAuthTries/PubkeyAuth）
- 新增：成功登录记录 + 全局可写文件扫描
- 新增：系统更新状态 + 安全更新检测
- 新增：硬件错误日志 + 认证日志检查
- 新增：失败的服务检测
- 新增：NTP 源详情
- 优化：CPU 采集 4 重兼容（top/mpstat/vmstat/proc）
- 优化：TOP 进程从 5 扩展到 10
- 优化：服务列表从 15 扩展到 38
- 优化：概览卡片从 4 个扩展到 6 个
- 修复：CPU 使用率异常值（1000%）
- 修复：set -u 下 heredoc 变量未定义报错

### v1.0 (2026-04-07)
- 初始版本
- 基础信息 / CPU / 内存 / 磁盘 / 网络 / 服务 / 安全 / 日志

---

## Contributing | 参与贡献

欢迎提交 Issue 和 Pull Request！详见 [CONTRIBUTING.md](CONTRIBUTING.md)

```
Fork → Clone → Branch → Commit → Push → Pull Request
```

---

## License

[MIT License](LICENSE)
