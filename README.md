# 小型化 Tailscale 在 OpenWRT 上的一键安装方案

### 脚本目前还有点小bug, 如发现问题请及时反馈~

## 📦 文件结构
```
/etc/tailscale/
├── setup.sh               # 安装脚本
├── fetch_and_install.sh   # 下载器
├── test_mirrors.sh        # 代理检测
├── autoupdate.sh          # 自动更新
├── setup_service.sh       # 服务配置
├── setup_cron.sh          # 定时任务
├── notify_ctl.sh          # 通知管理
├── update_ctl.sh          # 更新控制
├── uninstall.sh           # 卸载脚本
├── install.conf           # 安装配置
├── mirrors.txt            # 镜像列表
└── valid_mirrors.txt      # 有效镜像
```

## 🚀 快速安装
### 1.安装依赖
   ```bash
   opkg update && opkg install libustream-openssl ca-bundle kmod-tun coreutils-timeout
   ```

### 2.检测镜像 & 下载脚本包
   ```bash
   curl -o /tmp/pretest_mirrors.sh -L https://ghproxy.ch3ng.top/https://github.com/CH3NGYZ/ts-test/raw/refs/heads/main/pretest_mirrors.sh && sh /tmp/pretest_mirrors.sh
   ```
   或
   ```bash
   wget -O /tmp/pretest_mirrors.sh https://ghproxy.ch3ng.top/https://github.com/CH3NGYZ/ts-test/raw/refs/heads/main/pretest_mirrors.sh && sh /tmp/pretest_mirrors.sh
   ```

### 3.开始安装
   ```bash
   tailscale-helper
   ```

## 🔧 功能管理
   | 命令 | 功能 |
   |------|------|
   | `tailscale-helper` | 管理自动更新,配置通知等 |

## 📡 代理配置
   1. 编辑镜像列表：
      ```bash
      vi /etc/tailscale/mirrors.txt
      ```
      格式示例：
      ```
      https://wget.la/https://github.com/
      https://ghproxy.net/https://github.com/
      ```
   2. 测试可用性:
      ```bash
      /etc/tailscale/test_mirrors.sh
      ```
   3. 强制重新检测代理
      ```
      rm /etc/tailscale/valid_mirrors.txt && /etc/tailscale/test_mirrors.sh
      ```

## 🔔 通知系统
   ```bash
   # 交互式配置
   tailscale-helper

   # 配置项说明：
   # - 更新通知：版本升级成功时提醒
   # - 代理失败：代理不可用时提醒
   # - 紧急通知：关键系统错误提醒
   ```

## 🗑️ 卸载
   ```bash
   tailscale-helper
   ```
> 注意：默认会保留脚本目录

## ⚠️ 注意事项
   1. 内存安装模式每次重启后需重新下载Tailscale, 但由于proxy不稳定, 可能会出现下载失败的情况, 因此建议您还是本地安装
   2. 首次使用建议配置通知

## 😍 鸣谢
   1. [glinet-tailscale-updater](https://github.com/Admonstrator/glinet-tailscale-updater)
   2. [golang](https://github.com/golang/go)
   3. [UPX](https://github.com/upx/upx)
