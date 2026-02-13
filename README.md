# Tailscale on OpenWRT 管理工具

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-v1.1.0-brightgreen)
![Shell](https://img.shields.io/badge/shell-sh-blue)

一套完整的 Tailscale 在 OpenWRT 上的安装、配置和管理解决方案。提供自动化安装、版本管理、代理切换、通知推送等功能。

## 📋 目录

- [核心特性](#核心特性)
- [快速开始](#快速开始)
- [安装模式](#安装模式)
- [脚本索引](#脚本索引)
- [管理工具](#管理工具)
- [配置说明](#配置说明)
- [常见问题](#常见问题)
- [日志位置](#日志位置)
- [通知系统](#通知系统)
- [贡献与许可](#贡献与许可)

## ✨ 核心特性

- **🚀 一键安装** - 自动化安装流程，支持本地和内存两种模式
- **🔄 自动更新** - 支持定时自动检测和更新 Tailscale 版本
- **🌐 代理管理** - 智能镜像测速，自动选择最快的下载源
- **🔌 直连切换** - 支持 GitHub 直连和代理模式快速切换
- **📦 版本管理** - 灵活的版本选择，支持指定版本安装
- **🔔 推送通知** - 集成多种通知方式（Server 酱、Bark、NTFY、PushPlus）
- **⚙️ 架构支持** - 支持 x86、ARM、MIPS 等多种架构
- **📊 镜像排序** - 定期测速并自动排序代理池
- **🛠️ 脚本更新** - 支持在线更新管理脚本包

## 🚀 快速开始

### 前置要求

- OpenWRT 系统
- 网络连接
- 基础 shell 环境

### 安装步骤

1. **下载并执行安装脚本**

```bash
# 代理版
rm -rf /etc/tailscale /tmp/tailscale-use-direct /tmp/install.sh
URL="https://gh.ch3ng.top/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }

```

或使用 GitHub 直连：

```bash
# 直连版
rm -rf /etc/tailscale /tmp/install.sh
touch /tmp/tailscale-use-direct
URL="https://github.com/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }

```

2. **按照提示完成安装**

   - 选择安装模式（本地/内存）
   - 选择是否启用自动更新
   - 选择 Tailscale 版本

3. **打开管理菜单**

```bash
tailscale-helper
```

## 📦 安装模式

### 本地安装模式 (Local)

- **特点**：Tailscale 二进制文件安装到 `/usr/local/bin/`
- **优势**：
  - 持久化存储，重启后保留
  - 性能最优
  - 适合长期运行
- **劣势**：
  - 占用系统存储空间
  - 可能与系统包冲突

**适用场景**：存储空间充足的设备

### 内存安装模式 (Tmp)

- **特点**：Tailscale 二进制文件存储在 `/tmp/` 内存中
- **优势**：
  - 不占用系统存储
  - 适合存储空间有限的设备
  - 易于清理
- **劣势**：
  - 重启后需要重新下载
  - 内存占用较大

**适用场景**：存储空间有限的设备

## 📚 脚本索引

### 核心脚本

| 脚本名称                                   | 功能描述                                       | 调用方式                    |
| ------------------------------------------ | ---------------------------------------------- | --------------------------- |
| [`install.sh`](install.sh)                 | 主安装脚本，负责依赖检查、包下载、校验和初始化 | `sh install.sh`             |
| [`pretest_mirrors.sh`](pretest_mirrors.sh) | 镜像预测试，下载校验文件、代理列表并测速       | 由 install.sh 调用          |
| [`setup.sh`](scripts/setup.sh)             | Tailscale 安装配置，选择模式、版本和更新策略   | `tailscale-helper` → 选项 1 |
| [`helper.sh`](scripts/helper.sh)           | 主菜单脚本，提供 14 个功能选项的交互界面       | `tailscale-helper`          |

### 管理脚本

| 脚本名称                                               | 功能描述                         | 调用方式                     |
| ------------------------------------------------------ | -------------------------------- | ---------------------------- |
| [`update_ctl.sh`](scripts/update_ctl.sh)               | 自动更新开关控制                 | `tailscale-helper` → 选项 6  |
| [`autoupdate.sh`](scripts/autoupdate.sh)               | 自动更新执行逻辑，检测版本并更新 | 定时任务或手动调用           |
| [`github_direct_ctl.sh`](scripts/github_direct_ctl.sh) | GitHub 直连/代理模式切换         | `tailscale-helper` → 选项 8  |
| [`test_mirrors.sh`](scripts/test_mirrors.sh)           | 镜像测速并排序                   | `tailscale-helper` → 选项 12 |

### 服务脚本

| 脚本名称                                       | 功能描述                           | 调用方式                    |
| ---------------------------------------------- | ---------------------------------- | --------------------------- |
| [`setup_service.sh`](scripts/setup_service.sh) | 生成并启动 Tailscale 服务          | 由 setup.sh 调用            |
| [`setup_cron.sh`](scripts/setup_cron.sh)       | 配置定时任务（镜像维护、自动更新） | 由 setup.sh 调用            |
| [`uninstall.sh`](scripts/uninstall.sh)         | 完整卸载 Tailscale 和相关配置      | `tailscale-helper` → 选项 5 |

### 工具脚本

| 脚本名称                                                         | 功能描述                         | 调用方式                     |
| ---------------------------------------------------------------- | -------------------------------- | ---------------------------- |
| [`fetch_and_install.sh`](scripts/fetch_and_install.sh)           | 下载和安装 Tailscale 二进制文件  | 由其他脚本调用               |
| [`notify_ctl.sh`](scripts/notify_ctl.sh)                         | 通知系统配置管理                 | `tailscale-helper` → 选项 11 |
| [`tools.sh`](scripts/tools.sh)                                   | 公共函数库（日志、下载、通知等） | 被所有脚本引入               |
| [`tailscale_up_generater.sh`](scripts/tailscale_up_generater.sh) | 生成 Tailscale 启动命令          | `tailscale-helper` → 选项 3  |

## 🎛️ 管理工具

### 主菜单 (tailscale-helper)

执行 `tailscale-helper` 打开主菜单，提供以下功能：

```
1).  💾 安装 / 重装 Tailscale
2).  📥 登录 Tailscale
3).  📝 生成 Tailscale 启动命令
4).  📤 登出 Tailscale
5).  ❌ 卸载 Tailscale
6).  🔄 管理 Tailscale 自动更新
7).  🔄 手动运行更新脚本
8).  🔄 切换代理/直连状态
9).  📦 查看本地 Tailscale 存在版本
10). 📦 查看远程 Tailscale 最新版本
11). 🔔 管理推送通知
12). 📊 排序代理池
13). 🛠️ 更新脚本包
14). 📜 显示 Tailscale 更新日志
0).  ⛔ 退出
```

### 自动更新管理

启用或禁用自动更新：

```bash
# 通过菜单
tailscale-helper
# 选择选项 6 管理 Tailscale 自动更新
```

### 代理切换指南

在 GitHub 直连和代理模式之间切换：

```bash
tailscale-helper
# 选择选项 8 切换代理/直连状态
```

### 镜像测速

手动测速并排序代理池：

```bash
tailscale-helper
# 选择选项 12 排序代理池
```

## ⚙️ 配置说明

### 配置文件位置

所有配置文件存储在 `/etc/tailscale/` 目录：

```
/etc/tailscale/
├── install.conf          # 安装配置（模式、版本、架构等）
├── notify.conf           # 通知配置（推送服务密钥）
├── proxies.txt           # 代理列表
├── valid_proxies.txt     # 有效代理列表（测速结果）
├── current_version       # 当前 Tailscale 版本
└── scripts/              # 所有管理脚本
```

### install.conf 配置项

```bash
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

### notify.conf 通知配置

```bash
# 通知开关
NOTIFY_UPDATE=1              # 更新成功通知
NOTIFY_MIRROR_FAIL=1         # 镜像失效通知
NOTIFY_EMERGENCY=1           # 紧急错误通知

# Server酱配置
NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""

# Bark 配置
NOTIFY_BARK=0
BARK_KEY=""

# NTFY 配置
NOTIFY_NTFY=0
NTFY_KEY=""

# PushPlus 配置
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
```

## 🔄 自动更新

### 工作原理

1. **定时检测**：每天 4-6 点随机时间检测新版本
2. **版本对比**：比较本地版本和远程最新版本
3. **自动更新**：如果有新版本，自动下载并安装
4. **服务重启**：更新完成后自动重启 Tailscale 服务
5. **通知推送**：根据配置发送更新成功或失败通知

### 定时任务

系统会自动配置两个定时任务：

```bash
# 镜像维护任务（2-3 点随机时间）
$RANDOM_MIN $RANDOM_HOUR * * * /etc/tailscale/test_mirrors.sh

# 自动更新任务（4-6 点随机时间）
$UPDATE_MIN $UPDATE_HOUR * * * /etc/tailscale/autoupdate.sh
```

查看定时任务：

```bash
crontab -l
```

## 🌐 代理切换

### 直连模式

直接连接 GitHub，不经过代理：

```bash
tailscale-helper
# 选择选项 8 切换代理/直连状态
```

**优势**：速度快，无代理延迟
**劣势**：可能被 GFW 限制

### 代理模式

通过代理镜像下载：

```bash
tailscale-helper
# 选择选项 8 切换代理/直连状态
```

**优势**：稳定可靠，支持国内访问
**劣势**：可能有延迟

### 自动镜像测速

系统会定期测速代理池，自动选择最快的镜像：

```bash
tailscale-helper
# 选择选项 12 排序代理池
```

## 📋 常见问题

### Q1: 安装失败，提示缺少依赖包

**A**: 脚本会自动检测并安装必要的依赖包。如果仍然失败，请手动安装：

```bash
opkg update
opkg install libustream-openssl ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl jq
```

### Q2: 如何切换安装模式？

**A**: 重新运行安装脚本，选择不同的模式：

```bash
tailscale-helper
# 选择选项 1 重新安装
```

### Q3: 自动更新不工作

**A**: 检查以下几点：

1. 确认自动更新已启用：`tailscale-helper` → 选项 6
2. 检查定时任务：`crontab -l`
3. 查看更新日志：`cat /tmp/tailscale_update.log`
4. 确认网络连接正常

### Q4: 如何手动更新 Tailscale？

**A**: 使用主菜单选项 7：

```bash
tailscale-helper
# 选择选项 7 手动运行更新脚本
```

### Q5: 代理全部失效怎么办？

**A**: 切换到 GitHub 直连模式：

```bash
# 通过菜单
tailscale-helper
# 选择选项 8 切换代理/直连状态
```

### Q6: 如何卸载 Tailscale？

**A**: 使用主菜单选项 5：

```bash
tailscale-helper
# 选择选项 5 卸载 Tailscale
```

### Q7: 如何查看当前版本？

**A**: 使用主菜单选项 9：

```bash
tailscale-helper
# 选择选项 9 查看本地版本
```

或直接查看：

```bash
cat /etc/tailscale/current_version
```

### Q8: 支持哪些架构？

**A**: 支持以下架构：

- x86: `386`、`amd64`
- ARM: `arm`、`arm64`
- MIPS: `mips`、`mipsle`、`mips64`、`mips64le`

系统会自动检测架构。

### Q9: 如何配置推送通知？

**A**: 使用主菜单选项 11：

```bash
tailscale-helper
# 选择选项 11 管理推送通知
```

### Q10: 脚本包如何更新？

**A**: 使用主菜单选项 13：

```bash
tailscale-helper
# 选择选项 13 更新脚本包
```

## 📍 日志位置

### 系统日志

| 日志文件                         | 说明               |
| -------------------------------- | ------------------ |
| `/var/log/tailscale_install.log` | 安装日志           |
| `/var/log/tailscale.log`         | Tailscale 服务日志 |
| `/tmp/tailscale_update.log`      | 更新日志           |

### 查看日志

```bash
# 查看安装日志
tail -f /var/log/tailscale_install.log

# 查看服务日志
tail -f /var/log/tailscale.log

# 查看更新日志
cat /tmp/tailscale_update.log

# 在菜单中查看更新日志
tailscale-helper
# 选择选项 14 显示 Tailscale 更新日志
```

## 🔔 通知系统

### 支持的通知方式

#### 1. Server 酱 (WeChat)

- **获取密钥**：https://sct.ftqq.com/sendkey
- **配置**：在菜单选项 11 中设置 SendKey

#### 2. Bark (iOS)

- **获取密钥**：安装 Bark 应用后获取设备码
- **配置**：在菜单选项 11 中设置设备码
- **格式**：`https://api.day.app/KEYxxxxxxx` 或自建服务器地址

#### 3. NTFY (Web/Mobile)

- **获取密钥**：访问 https://ntfy.sh 创建订阅
- **配置**：在菜单选项 11 中设置订阅码

#### 4. PushPlus (Web)

- **获取密钥**：https://www.pushplus.plus
- **配置**：在菜单选项 11 中设置 Token

### 通知类型

| 通知类型 | 触发条件           | 配置项               |
| -------- | ------------------ | -------------------- |
| 更新成功 | Tailscale 成功更新 | `NOTIFY_UPDATE`      |
| 镜像失效 | 所有代理镜像失效   | `NOTIFY_MIRROR_FAIL` |
| 紧急错误 | 更新或安装失败     | `NOTIFY_EMERGENCY`   |

### 配置通知

```bash
# 打开菜单
tailscale-helper

# 选择选项 11 管理推送通知
# 按照提示配置各个通知服务

# 发送测试通知
# 在菜单中选择选项 12
```

## 🤝 贡献与许可

### 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

### 贡献

欢迎提交 Issue 和 Pull Request！

- **报告 Bug**：https://github.com/CH3NGYZ/small-tailscale-openwrt/issues
- **功能建议**：https://github.com/CH3NGYZ/small-tailscale-openwrt/discussions

### 致谢

感谢所有贡献者和用户的支持！

## 📞 技术支持

- **GitHub Issues**：https://github.com/CH3NGYZ/small-tailscale-openwrt/issues
- **讨论区**：https://github.com/CH3NGYZ/small-tailscale-openwrt/discussions

---

**版本**：v1.1.0  
**最后更新**：2026-02-13  
**维护者**：CH3NGYZ
