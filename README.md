<div align="center">

# Tailscale on OpenWrt

**面向 OpenWrt 的 Tailscale 安装、配置与管理工具**

[![Version](https://img.shields.io/badge/version-v1.1.0-2ea44f)](https://github.com/CH3NGYZ/small-tailscale-openwrt)
[![Shell](https://img.shields.io/badge/shell-sh-4eaa25)](https://github.com/CH3NGYZ/small-tailscale-openwrt)
[![License](https://img.shields.io/badge/license-MIT-1677ff)](LICENSE)

一键安装 · 自动更新 · 镜像测速 · 直连切换 · 推送通知

</div>

---

## 项目简介

本项目为 OpenWrt 提供完整的 Tailscale 管理方案，覆盖自动化安装、版本管理、下载线路切换、镜像测速和通知推送等常用场景。

| 功能 | 说明 |
| :--- | :--- |
| 一键安装 | 支持本地安装和内存安装，可选择指定版本 |
| 自动更新 | 定时检查新版本，更新后自动重启服务 |
| 下载加速 | 自动测速代理镜像，并优先使用最快线路 |
| 直连切换 | 可随时切换 GitHub 直连与代理模式 |
| 推送通知 | 支持 Server 酱、Bark、NTFY 和 PushPlus |
| 多架构支持 | 支持 x86、ARM、MIPS 等常见架构 |
| 脚本更新 | 可通过管理菜单在线更新脚本包 |

## 快速开始

### 1. 运行安装脚本

使用代理镜像安装：

```sh
rm -rf /etc/tailscale /tmp/tailscale-use-direct /tmp/install.sh
URL="https://gh.ch3ng.top/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }
```

<details>
<summary><strong>使用 GitHub 直连安装</strong></summary>

```sh
rm -rf /etc/tailscale /tmp/install.sh
touch /tmp/tailscale-use-direct
URL="https://github.com/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }
```

</details>

安装过程中根据提示选择：

1. 安装模式：本地安装或内存安装
2. 是否启用自动更新
3. Tailscale 版本

> [!NOTE]
> 运行前请确认设备使用 OpenWrt、网络连接正常，并具备基础 Shell 环境。

### 2. 打开管理菜单

```sh
tailscale-helper
```

### 3. 创建 Tailscale 接口

登录 OpenWrt 后，进入 **网络 → 接口**，按照下表完成配置：

| 操作与配置 | 参考截图 |
| :--- | :---: |
| **① 新建接口**<br><br>点击 **添加新接口**。<br><br>接口名称：`tailscale`<br>协议：**静态地址** | <img width="400" alt="创建 Tailscale 接口" src="https://github.com/user-attachments/assets/c600fe8b-099b-407f-8dd8-539ac27f9cae"> |
| **② 配置 IPv4 地址**<br><br>IPv4 地址：当前设备在 Tailscale 管理后台中分配的 IP，例如 `100.64.0.1`<br>子网掩码：`255.0.0.0`<br>网关：你的网关地址，例如 `192.168.1.1`<br>广播地址：保持默认<br><br>**注意：** **IPv4地址不是 OpenWrt 的 LAN 地址。** | <img width="400" alt="配置 IPv4 地址" src="https://github.com/user-attachments/assets/bddbbf80-8ad0-434c-a87d-7351604844b7"> |
| **③ 配置防火墙**<br><br>防火墙区域：`lan`<br><br>完成后点击 **保存**。 | <img width="400" alt="配置防火墙区域" src="https://github.com/user-attachments/assets/24351983-2dbc-4b15-b713-4927a0f6e60b"> |

> [!NOTE]
> 保存后，`tailscale` 接口会绑定到 `tailscale0`，并加入 `lan` 防火墙区域。

## 安装模式

| 对比项 | 本地安装（Local） | 内存安装（Tmp） |
| :--- | :--- | :--- |
| 安装位置 | `/usr/local/bin/` | `/tmp/` |
| 重启后保留 | 是 | 否，需要重新下载 |
| 系统存储占用 | 较高 | 较低 |
| 内存占用 | 较低 | 较高 |
| 适用设备 | 存储空间充足、需要长期运行 | 存储空间有限 |
| 主要特点 | 持久化、性能稳定 | 易清理、不占用持久存储 |

## 管理菜单

运行 `tailscale-helper` 后，可使用以下功能：

| 选项 | 功能 | 选项 | 功能 |
| :---: | :--- | :---: | :--- |
| 1 | 安装 / 重装 Tailscale | 8 | 切换代理 / 直连状态 |
| 2 | 登录 Tailscale | 9 | 查看本地 Tailscale 版本 |
| 3 | 生成 Tailscale 启动命令 | 10 | 查看远程最新版本 |
| 4 | 登出 Tailscale | 11 | 管理推送通知 |
| 5 | 卸载 Tailscale | 12 | 排序代理池 |
| 6 | 管理自动更新 | 13 | 更新脚本包 |
| 7 | 手动运行更新脚本 | 14 | 显示更新日志 |
| 0 | 退出 | | |

常用操作均从管理菜单进入：

```sh
tailscale-helper
```

- 管理自动更新：选择 `6`
- 手动更新：选择 `7`
- 切换代理 / 直连：选择 `8`
- 配置推送通知：选择 `11`
- 镜像测速排序：选择 `12`
- 更新脚本包：选择 `13`

## 自动更新与代理

### 自动更新流程

1. 每天 4:00-6:00 随机时间检查新版本
2. 对比本地版本与远程最新版本
3. 发现新版本后自动下载并安装
4. 更新完成后自动重启 Tailscale 服务
5. 根据配置发送成功或失败通知

系统会自动创建以下定时任务：

```cron
# 镜像维护任务（2:00-3:00 随机时间）
$RANDOM_MIN $RANDOM_HOUR * * * /etc/tailscale/test_mirrors.sh

# 自动更新任务（4:00-6:00 随机时间）
$UPDATE_MIN $UPDATE_HOUR * * * /etc/tailscale/autoupdate.sh
```

查看当前定时任务：

```sh
crontab -l
```

### 下载模式

| 模式 | 说明 | 适用情况 |
| :--- | :--- | :--- |
| GitHub 直连 | 直接连接 GitHub，延迟较低 | 网络可稳定访问 GitHub |
| 代理镜像 | 通过测速后的镜像源下载 | GitHub 访问不稳定或受限 |

通过管理菜单的选项 `8` 切换下载模式，使用选项 `12` 手动测速并重新排序代理池。

## 配置说明

所有配置均保存在 `/etc/tailscale/`：

```text
/etc/tailscale/
├── install.conf          # 安装模式、版本、架构等
├── notify.conf           # 通知服务配置
├── proxies.txt           # 代理列表
├── valid_proxies.txt     # 测速后的有效代理列表
├── current_version       # 当前 Tailscale 版本
└── scripts/              # 管理脚本
```

<details>
<summary><strong>install.conf 配置示例</strong></summary>

```sh
# 安装模式：local（本地）或 tmp（内存）
MODE=local

# 自动更新：true 或 false
AUTO_UPDATE=true

# Tailscale 版本：latest 或具体版本号
VERSION=latest

# 系统架构：amd64、arm、arm64、mips、mipsle 等
ARCH=amd64

# 设备主机名
HOST_NAME=OpenWrt

# GitHub 直连模式：true 或 false
GITHUB_DIRECT=false

# 安装时间戳
TIMESTAMP=1234567890
```

</details>

<details>
<summary><strong>notify.conf 配置示例</strong></summary>

```sh
# 通知开关
NOTIFY_UPDATE=1              # 更新成功通知
NOTIFY_MIRROR_FAIL=1         # 镜像失效通知
NOTIFY_EMERGENCY=1           # 紧急错误通知

# Server 酱
NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""

# Bark
NOTIFY_BARK=0
BARK_KEY=""

# NTFY
NOTIFY_NTFY=0
NTFY_KEY=""

# PushPlus
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
```

</details>

## 通知系统

| 服务 | 获取凭据 | 配置内容 |
| :--- | :--- | :--- |
| Server 酱 | [sct.ftqq.com](https://sct.ftqq.com/sendkey) | SendKey |
| Bark | 从 Bark 应用获取 | 设备码或自建服务器地址 |
| NTFY | [ntfy.sh](https://ntfy.sh) | 订阅码 |
| PushPlus | [pushplus.plus](https://www.pushplus.plus) | Token |

支持的通知事件：

| 通知事件 | 触发条件 | 配置项 |
| :--- | :--- | :--- |
| 更新成功 | Tailscale 更新完成 | `NOTIFY_UPDATE` |
| 镜像失效 | 所有代理镜像均不可用 | `NOTIFY_MIRROR_FAIL` |
| 紧急错误 | 更新或安装失败 | `NOTIFY_EMERGENCY` |

运行 `tailscale-helper` 并选择选项 `11`，即可配置通知服务和发送测试通知。

## 脚本索引

<details>
<summary><strong>查看全部脚本</strong></summary>

### 核心脚本

| 脚本 | 用途 | 调用方式 |
| :--- | :--- | :--- |
| [`install.sh`](install.sh) | 检查依赖、下载软件包、校验并初始化 | `sh install.sh` |
| [`pretest_mirrors.sh`](pretest_mirrors.sh) | 下载校验文件、预检代理并测速 | 由 `install.sh` 调用 |
| [`setup.sh`](scripts/setup.sh) | 选择安装模式、版本和更新策略 | 菜单选项 `1` |
| [`helper.sh`](scripts/helper.sh) | 提供交互式管理菜单 | `tailscale-helper` |

### 管理脚本

| 脚本 | 用途 | 调用方式 |
| :--- | :--- | :--- |
| [`update_ctl.sh`](scripts/update_ctl.sh) | 控制自动更新开关 | 菜单选项 `6` |
| [`autoupdate.sh`](scripts/autoupdate.sh) | 检查版本并执行自动更新 | 定时任务或手动调用 |
| [`github_direct_ctl.sh`](scripts/github_direct_ctl.sh) | 切换 GitHub 直连 / 代理模式 | 菜单选项 `8` |
| [`test_mirrors.sh`](scripts/test_mirrors.sh) | 测试镜像速度并排序 | 菜单选项 `12` |

### 服务与工具脚本

| 脚本 | 用途 | 调用方式 |
| :--- | :--- | :--- |
| [`setup_service.sh`](scripts/setup_service.sh) | 生成并启动 Tailscale 服务 | 由 `setup.sh` 调用 |
| [`setup_cron.sh`](scripts/setup_cron.sh) | 配置镜像维护和自动更新任务 | 由 `setup.sh` 调用 |
| [`uninstall.sh`](scripts/uninstall.sh) | 卸载 Tailscale 及相关配置 | 菜单选项 `5` |
| [`fetch_and_install.sh`](scripts/fetch_and_install.sh) | 下载并安装 Tailscale 二进制文件 | 由其他脚本调用 |
| [`notify_ctl.sh`](scripts/notify_ctl.sh) | 管理通知配置 | 菜单选项 `11` |
| [`tools.sh`](scripts/tools.sh) | 提供日志、下载、通知等公共函数 | 由其他脚本引入 |
| [`tailscale_up_generator.sh`](scripts/tailscale_up_generator.sh) | 生成 Tailscale 启动命令 | 菜单选项 `3` |

</details>

## 常见问题

<details>
<summary><strong>安装失败并提示缺少依赖包</strong></summary>

安装脚本会自动检查并安装依赖。如果仍然失败，可手动执行：

```sh
opkg update
opkg install libustream-openssl ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl jq
```

</details>

<details>
<summary><strong>如何切换安装模式？</strong></summary>

运行 `tailscale-helper`，选择选项 `1` 重新安装，并选择新的安装模式。

</details>

<details>
<summary><strong>自动更新不工作</strong></summary>

依次检查：

1. 运行 `tailscale-helper`，通过选项 `6` 确认自动更新已启用
2. 执行 `crontab -l` 检查定时任务
3. 执行 `cat /tmp/tailscale_update.log` 查看更新日志
4. 确认设备网络连接正常

</details>

<details>
<summary><strong>代理镜像全部失效</strong></summary>

运行 `tailscale-helper`，选择选项 `8` 切换到 GitHub 直连模式。

</details>

<details>
<summary><strong>如何卸载 Tailscale？</strong></summary>

运行 `tailscale-helper`，选择选项 `5`。

</details>

<details>
<summary><strong>如何查看当前版本？</strong></summary>

运行 `tailscale-helper` 并选择选项 `9`，或直接执行：

```sh
cat /etc/tailscale/current_version
```

</details>

<details>
<summary><strong>支持哪些架构？</strong></summary>

- x86：`386`、`amd64`
- ARM：`arm`、`arm64`
- MIPS：`mips`、`mipsle`、`mips64`、`mips64le`

安装脚本会自动检测设备架构。

</details>

## 日志位置

| 日志 | 路径 |
| :--- | :--- |
| 安装日志 | `/var/log/tailscale_install.log` |
| Tailscale 服务日志 | `/var/log/tailscale.log` |
| 更新日志 | `/tmp/tailscale_update.log` |

```sh
# 实时查看安装日志
tail -f /var/log/tailscale_install.log

# 实时查看服务日志
tail -f /var/log/tailscale.log

# 查看更新日志
cat /tmp/tailscale_update.log
```

也可以运行 `tailscale-helper`，选择选项 `14` 查看更新日志。

## 贡献与支持

- [提交问题](https://github.com/CH3NGYZ/small-tailscale-openwrt/issues)
- [功能建议与讨论](https://github.com/CH3NGYZ/small-tailscale-openwrt/discussions)
- [MIT License](LICENSE)

---

<div align="center">

**v1.1.0** · 最后更新于 2026-07-31 · 维护者 CH3NGYZ

</div>
