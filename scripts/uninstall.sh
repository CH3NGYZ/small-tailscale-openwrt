#!/bin/sh

set -e
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

log_info "🛑  开始卸载Tailscale..."

# 停止并禁用 Tailscale 服务
[ -f /etc/init.d/tailscale ] && {
    /etc/init.d/tailscale stop
    /etc/init.d/tailscale disable
    rm -f /etc/init.d/tailscale
}

log_info "🗑️  删除所有相关文件..."
# 删除所有可能的文件和目录
rm -rf \
    /etc/config/tailscale* \
    /etc/init.d/tailscale* \
    /usr/bin/tailscale \
    /usr/bin/tailscaled \
    /usr/local/bin/tailscale* \
    /tmp/tailscaled \
    /var/lib/tailscale* \
    "$VERSION_FILE"

# 删除 Tailscale 网络接口
ip link delete tailscale0 2>/dev/null || true

# 清理定时任务
log_info "🧹  清理定时任务..."
sed -i "\|$CONFIG_DIR/|d" /etc/crontabs/root
/etc/init.d/cron restart

log_info "🎉  Tailscale卸载完成！"
log_info "🎉  重装Tailscale , 请运行  tailscale-helper"
log_info "🎉  如需删除安装脚本,请运行  rm -rf $CONFIG_DIR"