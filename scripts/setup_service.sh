#!/bin/sh

set -e
[ -f /etc/tailscale/common.sh ] && . /etc/tailscale/common.sh

# 加载配置文件
log_info "🔧 加载配置文件..."
safe_source "$INST_CONF" || { log_error "❌ 无法加载配置文件 $INST_CONF"; exit 1; }

# 确保配置文件中有 MODE 设置
if [ -z "$MODE" ]; then
    log_error "❌ 错误：未在配置文件中找到 MODE 设置"
    exit 1
fi

log_info "🔧 当前的 MODE 设置为: $MODE"

# 生成服务文件
log_info "📝 生成服务文件..."
cat > /etc/init.d/tailscale <<"EOF"
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=90
STOP=1

start_service() {
  # 确保已经加载了 INST_CONF 和其中的 MODE
  log_info "🔧 加载服务启动配置..."
  [ -f /etc/tailscale/common.sh ] && . /etc/tailscale/common.sh
  safe_source "$INST_CONF"

  log_info "🔧 当前的 MODE 设置为: $MODE"

  if [ "$MODE" = "local" ]; then
    # 本地模式的启动逻辑
    TAILSCALED_BIN="/usr/local/bin/tailscaled"
    log_info "🔹 启动 Tailscale（本地模式）..."
    procd_open_instance
    procd_set_param env TS_DEBUG_FIREWALL_MODE=auto
    procd_set_param command "$TAILSCALED_BIN"
    procd_append_param command --port 41641
    procd_append_param command --state /etc/config/tailscaled.state
    procd_append_param command --statedir /etc/tailscale/
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param logfile /var/log/tailscale.log
    procd_close_instance

  elif [ "$MODE" = "tmp" ]; then
    # 临时模式的启动逻辑
    log_info "🧩 使用临时模式启动 Tailscale..."
    /etc/tailscale/setup.sh --tmp --auto-update > /tmp/tailscale_boot.log 2>&1 &
    log_info "🔧 临时模式已启动，日志文件：/tmp/tailscale_boot.log"
  else
    log_error "❌ 错误：未知模式 $MODE"
    exit 1
  fi
}

stop_service() {
  log_info "🛑 停止服务..."
  # 确保正确停止 tailscaled
  if [ -x "/usr/local/bin/tailscaled" ]; then
    /usr/local/bin/tailscaled --cleanup 2>/dev/null || log_error "⚠️ 清理失败: /usr/local/bin/tailscaled"
  fi
  if [ -x "/tmp/tailscaled" ]; then
    /tmp/tailscaled --cleanup 2>/dev/null || log_error "⚠️ 清理失败: /tmp/tailscaled"
  fi
  killall tailscaled 2>/dev/null || log_error "⚠️ 未能停止 tailscaled 服务"
}
EOF

# 设置权限
log_info "🔧 设置服务文件权限..."
chmod +x /etc/init.d/tailscale

# 启用服务
log_info "🔧 启用 Tailscale 服务..."
/etc/init.d/tailscale enable || { log_error "❌ 启用服务失败"; exit 1; }

# 启动服务并不显示任何状态输出
log_info "🔧 启动服务..."
/etc/init.d/tailscale restart > /dev/null 2>&1 || { log_error "❌ 重启服务失败，尝试启动服务"; /etc/init.d/tailscale start > /dev/null 2>&1; }

# 完成
log_info "🎉 Tailscale 服务已启动!"
