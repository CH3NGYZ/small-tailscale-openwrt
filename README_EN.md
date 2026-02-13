# Tailscale on OpenWRT Management Tools

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Version](https://img.shields.io/badge/version-v1.1.0-brightgreen)
![Shell](https://img.shields.io/badge/shell-sh-blue)

A comprehensive solution for installing, configuring, and managing Tailscale on OpenWRT. Provides automated installation, version management, proxy switching, push notifications, and more.

## 📋 Table of Contents

- [Core Features](#-core-features)
- [Quick Start](#-quick-start)
- [Installation Modes](#-installation-modes)
- [Script Index](#-script-index)
- [Management Tools](#-management-tools)
- [Configuration Guide](#-configuration-guide)
- [FAQ](#-faq)
- [Log Locations](#-log-locations)
- [Notification System](#-notification-system)
- [Contributing & License](#-contributing--license)

## ✨ Core Features

- **🚀 One-Click Installation** - Automated installation process with local and memory modes
- **🔄 Auto Update** - Scheduled version detection and automatic Tailscale updates
- **🌐 Proxy Management** - Intelligent mirror speed testing with automatic fastest source selection
- **🔌 Direct Connection Toggle** - Quick switch between GitHub direct connection and proxy modes
- **📦 Version Management** - Flexible version selection with support for specific version installation
- **🔔 Push Notifications** - Multiple notification methods (Server Chan, Bark, NTFY, PushPlus)
- **⚙️ Multi-Architecture Support** - Compatible with x86, ARM, MIPS and other architectures
- **📊 Mirror Ranking** - Periodic speed testing and automatic proxy pool sorting
- **🛠️ Script Updates** - Online update support for management script packages

## 🚀 Quick Start

### Prerequisites

- OpenWRT system
- Network connectivity
- Basic shell environment

### Installation Steps

1. **Download and execute the installation script**

```bash
# PROXY (Recommended for Chinese Users)
rm -rf /etc/tailscale /tmp/tailscale-use-direct /tmp/install.sh
URL="https://gh.ch3ng.top/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }

```

Or use GitHub direct connection:

```bash
# DIRECT
rm -rf /etc/tailscale /tmp/install.sh
touch /tmp/tailscale-use-direct
URL="https://github.com/CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"
(command -v curl >/dev/null && curl -fSL "$URL" -o /tmp/install.sh || wget "$URL" -O /tmp/install.sh) || { echo 下载失败; exit 1; }
sh /tmp/install.sh || { echo 执行失败; exit 1; }

```

2. **Follow the prompts to complete installation**

   - Select installation mode (Local/Memory)
   - Choose whether to enable auto-update
   - Select Tailscale version

3. **Open the management menu**

```bash
tailscale-helper
```

## 📦 Installation Modes

### Local Installation Mode

- **Characteristics**: Tailscale binary installed to `/usr/local/bin/`
- **Advantages**:
  - Persistent storage, retained after reboot
  - Optimal performance
  - Suitable for long-term operation
- **Disadvantages**:
  - Consumes system storage space
  - May conflict with system packages

**Use Case**: Devices with sufficient storage space

### Memory Installation Mode (Tmp)

- **Characteristics**: Tailscale binary stored in `/tmp/` memory
- **Advantages**:
  - No system storage consumption
  - Suitable for storage-limited devices
  - Easy cleanup
- **Disadvantages**:
  - Requires re-download after reboot
  - Higher memory usage

**Use Case**: Storage-limited devices

## 📚 Script Index

### Core Scripts

| Script Name                                | Function                                                                                                 | Invocation                    |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ----------------------------- |
| [`install.sh`](install.sh)                 | Main installation script, handles dependency checking, package download, verification and initialization | `sh install.sh`               |
| [`pretest_mirrors.sh`](pretest_mirrors.sh) | Mirror pre-testing, downloads verification files, proxy lists and performs speed testing                 | Called by install.sh          |
| [`setup.sh`](scripts/setup.sh)             | Tailscale installation configuration, selects mode, version and update strategy                          | `tailscale-helper` → Option 1 |
| [`helper.sh`](scripts/helper.sh)           | Main menu script providing 14 functional options in interactive interface                                | `tailscale-helper`            |

### Management Scripts

| Script Name                                            | Function                                                  | Invocation                          |
| ------------------------------------------------------ | --------------------------------------------------------- | ----------------------------------- |
| [`update_ctl.sh`](scripts/update_ctl.sh)               | Auto-update toggle control                                | `tailscale-helper` → Option 6       |
| [`autoupdate.sh`](scripts/autoupdate.sh)               | Auto-update execution logic, detects and updates versions | Scheduled task or manual invocation |
| [`github_direct_ctl.sh`](scripts/github_direct_ctl.sh) | GitHub direct connection/proxy mode toggle                | `tailscale-helper` → Option 8       |
| [`test_mirrors.sh`](scripts/test_mirrors.sh)           | Mirror speed testing and ranking                          | `tailscale-helper` → Option 12      |

### Service Scripts

| Script Name                                    | Function                                                        | Invocation                    |
| ---------------------------------------------- | --------------------------------------------------------------- | ----------------------------- |
| [`setup_service.sh`](scripts/setup_service.sh) | Generate and start Tailscale service                            | Called by setup.sh            |
| [`setup_cron.sh`](scripts/setup_cron.sh)       | Configure scheduled tasks (mirror maintenance, auto-update)     | Called by setup.sh            |
| [`uninstall.sh`](scripts/uninstall.sh)         | Complete uninstallation of Tailscale and related configurations | `tailscale-helper` → Option 5 |

### Utility Scripts

| Script Name                                                      | Function                                                            | Invocation                     |
| ---------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------ |
| [`fetch_and_install.sh`](scripts/fetch_and_install.sh)           | Download and install Tailscale binary                               | Called by other scripts        |
| [`notify_ctl.sh`](scripts/notify_ctl.sh)                         | Notification system configuration management                        | `tailscale-helper` → Option 11 |
| [`tools.sh`](scripts/tools.sh)                                   | Common function library (logging, downloading, notifications, etc.) | Sourced by all scripts         |
| [`tailscale_up_generater.sh`](scripts/tailscale_up_generater.sh) | Generate Tailscale startup command                                  | `tailscale-helper` → Option 3  |

## 🎛️ Management Tools

### Main Menu (tailscale-helper)

Execute `tailscale-helper` to open the main menu with the following options:

```
1).  💾 Install / Reinstall Tailscale
2).  📥 Login to Tailscale
3).  📝 Generate Tailscale startup command
4).  📤 Logout from Tailscale
5).  ❌ Uninstall Tailscale
6).  🔄 Manage Tailscale auto-update
7).  🔄 Manually run update script
8).  🔄 Toggle proxy/direct connection mode
9).  📦 View local Tailscale version
10). 📦 View remote Tailscale latest version
11). 🔔 Manage push notifications
12). 📊 Sort proxy pool
13). 🛠️ Update script package
14). 📜 Display Tailscale update log
0).  ⛔ Exit
```

### Auto-Update Management

Enable or disable auto-update:

```bash
# Via menu
tailscale-helper
# Select option 6 to manage Tailscale auto-update
```

### Proxy Switching Guide

Toggle between GitHub direct connection and proxy modes:

**Switch via menu**:

```bash
tailscale-helper
# Select option 8 to toggle proxy/direct connection mode
```

### Mirror Speed Testing

Manually test speed and rank proxy pool:

```bash
tailscale-helper
# Select option 12 to sort proxy pool
```

## ⚙️ Configuration Guide

### Configuration File Locations

All configuration files are stored in `/etc/tailscale/` directory:

```
/etc/tailscale/
├── install.conf          # Installation configuration (mode, version, architecture, etc.)
├── notify.conf           # Notification configuration (push service keys)
├── proxies.txt           # Proxy list
├── valid_proxies.txt     # Valid proxy list (speed test results)
├── current_version       # Current Tailscale version
└── scripts/              # All management scripts
```

### install.conf Configuration Items

```bash
# Installation mode: local or tmp
MODE=local

# Auto-update: true or false
AUTO_UPDATE=true

# Tailscale version: latest or specific version number
VERSION=latest

# System architecture: amd64, arm, arm64, mips, mipsle, etc.
ARCH=amd64

# Device hostname
HOST_NAME=OpenWrt

# GitHub direct connection mode: true or false
GITHUB_DIRECT=false

# Installation timestamp
TIMESTAMP=1234567890
```

### notify.conf Notification Configuration

```bash
# Notification switches
NOTIFY_UPDATE=1              # Update success notification
NOTIFY_MIRROR_FAIL=1         # Mirror failure notification
NOTIFY_EMERGENCY=1           # Emergency error notification

# Server Chan configuration
NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""

# Bark configuration
NOTIFY_BARK=0
BARK_KEY=""

# NTFY configuration
NOTIFY_NTFY=0
NTFY_KEY=""

# PushPlus configuration
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
```

## 🔄 Auto-Update

### How It Works

1. **Scheduled Detection**: Checks for new versions at random time between 4-6 AM daily
2. **Version Comparison**: Compares local version with remote latest version
3. **Automatic Update**: If new version available, automatically downloads and installs
4. **Service Restart**: Automatically restarts Tailscale service after update
5. **Push Notification**: Sends update success or failure notification based on configuration

### Scheduled Tasks

The system automatically configures two scheduled tasks:

```bash
# Mirror maintenance task (random time between 2-3 AM)
$RANDOM_MIN $RANDOM_HOUR * * * /etc/tailscale/test_mirrors.sh

# Auto-update task (random time between 4-6 AM)
$UPDATE_MIN $UPDATE_HOUR * * * /etc/tailscale/autoupdate.sh
```

View scheduled tasks:

```bash
crontab -l
```

## 🌐 Proxy Switching

### Direct Connection Mode

Connect directly to GitHub without proxy:

```bash
tailscale-helper
# Select option 8 to toggle proxy/direct connection mode
```

**Advantages**: Fast speed, no proxy latency
**Disadvantages**: May be restricted by GFW

### Proxy Mode

Download through proxy mirrors:

```bash
tailscale-helper
# Select option 8 to toggle proxy/direct connection mode
```

**Advantages**: Stable and reliable, supports domestic access
**Disadvantages**: May have latency

### Automatic Mirror Speed Testing

The system periodically tests proxy pool and automatically selects the fastest mirror:

```bash
tailscale-helper
# Select option 12 to sort proxy pool
```

## ❓ FAQ

### Q1: Installation fails with missing dependency packages

**A**: The script automatically detects and installs required dependencies. If it still fails, manually install:

```bash
opkg update
opkg install libustream-openssl ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl jq
```

### Q2: How to switch installation modes?

**A**: Re-run the installation script and select a different mode:

```bash
tailscale-helper
# Select option 1 to reinstall
```

### Q3: Auto-update is not working

**A**: Check the following:

1. Confirm auto-update is enabled: `tailscale-helper` → Option 6
2. Check scheduled tasks: `crontab -l`
3. View update log: `cat /tmp/tailscale_update.log`
4. Ensure network connectivity is normal

### Q4: How to manually update Tailscale?

**A**: Use menu option 7:

```bash
tailscale-helper
# Select option 7 to manually run update script
```

### Q5: What if all proxies fail?

**A**: Switch to GitHub direct connection mode:

```bash
# Via menu
tailscale-helper
# Select option 8 to toggle proxy/direct connection mode
```

### Q6: How to uninstall Tailscale?

**A**: Use menu option 5:

```bash
tailscale-helper
# Select option 5 to uninstall Tailscale
```

### Q7: How to check current version?

**A**: Use menu option 9:

```bash
tailscale-helper
# Select option 9 to view local version
```

Or check directly:

```bash
cat /etc/tailscale/current_version
```

### Q8: Which architectures are supported?

**A**: The following architectures are supported:

- x86: `386`, `amd64`
- ARM: `arm`, `arm64`
- MIPS: `mips`, `mipsle`, `mips64`, `mips64le`

The system automatically detects the architecture.

### Q9: How to configure push notifications?

**A**: Use menu option 11:

```bash
tailscale-helper
# Select option 11 to manage push notifications
```

### Q10: How to update the script package?

**A**: Use menu option 13:

```bash
tailscale-helper
# Select option 13 to update script package
```

## 📍 Log Locations

### System Logs

| Log File                         | Description           |
| -------------------------------- | --------------------- |
| `/var/log/tailscale_install.log` | Installation log      |
| `/var/log/tailscale.log`         | Tailscale service log |
| `/tmp/tailscale_update.log`      | Update log            |

### View Logs

```bash
# View installation log
tail -f /var/log/tailscale_install.log

# View service log
tail -f /var/log/tailscale.log

# View update log
cat /tmp/tailscale_update.log

# View update log in menu
tailscale-helper
# Select option 14 to display Tailscale update log
```

## 🔔 Notification System

### Supported Notification Methods

#### 1. Server Chan (WeChat)

- **Get Key**: https://sct.ftqq.com/sendkey
- **Configuration**: Set SendKey in menu option 11

#### 2. Bark (iOS)

- **Get Key**: Install Bark app and get device code
- **Configuration**: Set device code in menu option 11
- **Format**: `https://api.day.app/KEYxxxxxxx` or self-hosted server address

#### 3. NTFY (Web/Mobile)

- **Get Key**: Visit https://ntfy.sh to create subscription
- **Configuration**: Set subscription code in menu option 11

#### 4. PushPlus (Web)

- **Get Key**: https://www.pushplus.plus
- **Configuration**: Set Token in menu option 11

### Notification Types

| Notification Type | Trigger Condition              | Configuration Item   |
| ----------------- | ------------------------------ | -------------------- |
| Update Success    | Tailscale successfully updated | `NOTIFY_UPDATE`      |
| Mirror Failure    | All proxy mirrors failed       | `NOTIFY_MIRROR_FAIL` |
| Emergency Error   | Update or installation failed  | `NOTIFY_EMERGENCY`   |

### Configure Notifications

```bash
# Open menu
tailscale-helper

# Select option 11 to manage push notifications
# Follow prompts to configure each notification service

# Send test notification
# Select option 12 in menu
```

## 🤝 Contributing & License

### License

This project is licensed under the MIT License. See [LICENSE](LICENSE) file for details.

### Contributing

Issues and Pull Requests are welcome!

- **Report Bugs**: https://github.com/CH3NGYZ/small-tailscale-openwrt/issues
- **Feature Requests**: https://github.com/CH3NGYZ/small-tailscale-openwrt/discussions

### Acknowledgments

Thanks to all contributors and users for their support!

## 📞 Technical Support

- **GitHub Issues**: https://github.com/CH3NGYZ/small-tailscale-openwrt/issues
- **Discussions**: https://github.com/CH3NGYZ/small-tailscale-openwrt/discussions

---

**Version**: v1.1.0  
**Last Updated**: 2026-02-13  
**Maintainer**: CH3NGYZ
