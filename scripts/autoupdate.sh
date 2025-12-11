#!/bin/sh

[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

# 默认变量
MODE=""
ARCH=""
current=""
remote=""
# 加载安装配置
safe_source "$INST_CONF"

[ -z "$MODE" ] && log_error "❌  缺少 MODE 配置" && exit 1
[ -z "$ARCH" ] && ARCH="$(uname -m)"
[ -z "$current" ] && current="latest"

[ "$AUTO_UPDATE" = "true" ] && auto_update_enabled=1 || auto_update_enabled=0

# 查询远程最新版本
remote=$("$CONFIG_DIR/fetch_and_install.sh" --dry-run)

# 本地记录的版本
recorded=""
[ -f "$VERSION_FILE" ] && recorded=$(cat "$VERSION_FILE")

# 加载通知配置
[ -f $CONFIG_DIR/notify.conf ] && . $CONFIG_DIR/notify.conf


# 检查是否需要发送通知的函数
should_notify() {
    local notify_type=$1
    local notify_var
    case "$notify_type" in
        "update") notify_var="$NOTIFY_UPDATE" ;;
        "mirror_fail") notify_var="$NOTIFY_MIRROR_FAIL" ;;
        "emergency") notify_var="$NOTIFY_EMERGENCY" ;;
        *)
            log_error "❌  未知通知类型: $notify_type"
            return 1
            ;;
    esac
    # 检查是否启用通知
    if [ "$notify_var" = "1" ]; then
        return 0
    else
        return 1
    fi
}

# local 模式逻辑
if [ "$MODE" = "local" ]; then
  if [ "$AUTO_UPDATE" = "true" ]; then
    if [ "$remote" = "$recorded" ]; then
      log_info "✅  本地已是最新版 $remote, 无需更新"
      exit 0
    fi

    if "$CONFIG_DIR/fetch_and_install.sh" --version="$remote" --mode="local" --mirror-list="$VALID_MIRRORS"; then
      echo "$remote" > "$VERSION_FILE"
      log_info "✅  更新成功至版本 $remote"
      log_info "🛠️  重启以应用最新版..."
      /etc/init.d/tailscale restart || { log_error "❌  重启服务失败, 将启动服务"; /etc/init.d/tailscale start >/dev/null 2>&1 & }
      # 如果启用更新通知，发送通知
      if should_notify "update"; then
        send_notify "✅  Tailscale 已更新" "版本更新至 $remote"
      fi
    else
      log_error "❌  更新失败"
      # 如果启用紧急通知，发送通知
      if should_notify "emergency"; then
        send_notify "❌  Tailscale 更新失败" "版本更新失败，请检查日志"
      fi
      exit 1
    fi
  else
    if [ ! -x "/usr/local/bin/tailscaled" ]; then
      log_info "⚙️  未检测到 tailscaled，尝试安装默认版本 $current..."
      if "$CONFIG_DIR/fetch_and_install.sh" --version="$current" --mode="local" --mirror-list="$VALID_MIRRORS"; then
        echo "$current" > "$VERSION_FILE"
      else
        log_error "❌  安装失败"
        # 如果启用紧急通知，发送通知
        if should_notify "emergency"; then
          send_notify "❌  Tailscale 安装失败" "默认版本 $current 安装失败" ""
        fi
        exit 1
      fi
    else
      log_info "✅  自动更新已关闭, 本地已存在 tailscaled, 跳过安装"
    fi
  fi

elif [ "$MODE" = "tmp" ]; then
  version_to_use="$([ "$current" = "latest" ] && echo "$remote" || echo "$current")"


  if [ "$AUTO_UPDATE" = "true" ]; then
    # 如果启用自动更新，且版本与本地记录不一致，才进行更新
    if [ "$version_to_use" != "$recorded" ]; then
      # 开机和第一次安装时
      log_info "🌐  检测到新版本 $version_to_use, 开始更新..."
      if "$CONFIG_DIR/fetch_and_install.sh" --version="$version_to_use" --mode="tmp" --mirror-list="$VALID_MIRRORS"; then
        echo "$version_to_use" > "$VERSION_FILE"
        log_info "✅  更新成功至版本 $version_to_use"
        log_info "🛠️  重启以应用最新版..."
        /etc/init.d/tailscale restart || { log_error "❌  重启服务失败, 将启动服务"; /etc/init.d/tailscale start >/dev/null 2>&1 & }

        # 发送更新通知
        if should_notify "update"; then
          send_notify "✅  Tailscale TMP 模式已更新" "版本更新至 $version_to_use"
        fi
      else
        log_error "❌  TMP 更新失败"
        # 发送紧急通知
        if should_notify "emergency"; then
          send_notify "❌  Tailscale TMP 更新失败" "版本更新失败，请检查日志"
        fi
        exit 1
      fi
    else
      log_info "✅  TMP 当前版本 $version_to_use 已是最新"
    fi
  else
    # 如果不启用自动更新，先检测文件是否存在, 文件存在则直接跳过, (第一次安装) 文件不存在则使用指定版本进行安装 (开机时)
    if [ ! -x "/tmp/tailscaled" ]; then
      log_info "⚙️  不启用自动更新, TMP 模式不存在 tailscaled, 安装指定版本 $recorded..."
      if "$CONFIG_DIR/fetch_and_install.sh" --version="$recorded" --mode="tmp" --mirror-list="$VALID_MIRRORS"; then
        echo "$recorded" > "$VERSION_FILE"
      else
        log_error "❌  TMP 安装失败"
        # 发送紧急通知
        if should_notify "emergency"; then
          send_notify "❌  Tailscale TMP 安装失败" "指定版本 $version_to_use 安装失败"
        fi
        exit 1
      fi
    else
      log_info "⚙️  不启用自动更新, TMP 模式已存在 tailscaled, 跳过安装"
    fi
  fi
fi
