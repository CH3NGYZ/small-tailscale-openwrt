#!/bin/sh

[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
CONFIG_DIR="/etc/tailscale"
CONF_FILE="$CONFIG_DIR/tailscale_up.conf"

PARAMS_LIST="--accept-dns:flag:接受来自管理面板的 DNS 配置（默认 true）
--accept-risk:value:接受风险类型并跳过确认（lose-ssh、mac-app-connector、linux-strict-rp-filter、all）
--accept-routes:flag:接受其他 Tailscale 节点通告的路由（默认 false）
--advertise-connector:flag:将此节点宣告为应用连接器（默认 false）
--advertise-exit-node:flag:提供此节点作为出口节点以转发互联网流量（默认 false）
--advertise-routes:value:向其他节点通告的路由（逗号分隔，例如 10.0.0.0/8,192.168.0.0/24），空字符串表示不通告
--advertise-tags:value:请求的 ACL 标签（逗号分隔），每个必须以 tag: 开头
--auth-key:value:节点授权密钥；如果以 file: 开头则为包含密钥的文件路径
--client-id:value:用于通过工作负载身份联合生成授权密钥的 Client ID
--client-secret:value:用于通过 OAuth 生成授权密钥的 Client Secret；以 file: 开头则为包含密钥的文件路径
--exit-node:value:Tailscale 出口节点（IP、基本名称或 auto:any），空字符串表示不使用出口节点
--exit-node-allow-lan-access:flag:通过出口节点路由时允许直接访问本地局域网（默认 false）
--force-reauth:flag:强制重新认证（警告：会断开 Tailscale 连接，不应在 SSH 或 RDP 远程执行）（默认 false）
--hostname:value:使用此主机名而不是操作系统提供的名称
--id-token:value:从身份提供商获取的 ID token，用于与控制服务器交换以进行工作负载身份联合；以 file: 开头则为文件路径
--json:flag:以 JSON 格式输出（警告：格式可能变更）（默认 false）
--login-server:value:控制服务器的基础 URL（默认 https://controlplane.tailscale.com）
--netfilter-mode:value:netfilter 模式（on、nodivert、off 之一）（默认 on）
--operator:value:允许无需 sudo 操作 tailscaled 的 Unix 用户名
--qr:flag:显示登录 URL 的二维码（默认 false）
--qr-format:value:二维码格式（small 或 large，默认 small）
--reset:flag:将未指定的设置重置为默认值（默认 false）
--shields-up:flag:不允许传入连接（默认 false）
--snat-subnet-routes:flag:对通过 --advertise-routes 通告的本地路由进行源 NAT（默认 true）
--ssh:flag:运行 SSH 服务器，允许根据 tailnet 管理员声明的策略访问（默认 false）
--stateful-filtering:flag:对转发的数据包应用有状态过滤（子网路由器、出口节点等）（默认 false）
--timeout:value:等待 tailscaled 进入 Running 状态的最长时间；默认 0s 表示永远等待"

# 获取参数类型
get_param_type() {
  echo "$PARAMS_LIST" | grep "^$1:" | cut -d':' -f2
}

# 获取参数描述
get_param_desc() {
  echo "$PARAMS_LIST" | grep "^$1:" | cut -d':' -f3-
}

# 加载配置文件
load_conf() {
  [ -f "$CONF_FILE" ] || return
  while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    case "$key" in \#*) continue ;; esac
    key=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    value=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')
    eval "$key=\"$value\""
    log_info "加载配置: $key=$value"
  done < "$CONF_FILE"
}

# 保存配置到文件
save_conf() {
  echo -n > "$CONF_FILE"
  echo "$PARAMS_LIST" | while IFS= read -r line; do
    key=$(echo "$line" | cut -d':' -f1)
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    eval val=\$$var_name
    [ -n "$val" ] && echo "$key=\"$val\"" >> "$CONF_FILE"
  done
}

# 显示当前参数状态
show_status() {
  clear
  log_info "当前 tailscale up 参数状态："
  max_key_len=0
  max_val_len=0
  i=1
  OPTIONS=""
  echo "$PARAMS_LIST" > /tmp/params_list.txt
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key=$(echo "$line" | cut -d':' -f1)
    type=$(echo "$line" | cut -d':' -f2)
    desc=$(echo "$line" | cut -d':' -f3-)
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    eval val=\$$var_name
    [ "${#key}" -gt "$max_key_len" ] && max_key_len=${#key}
    [ "${#val}" -gt "$max_val_len" ] && max_val_len=${#val}
    OPTIONS="${OPTIONS}
$i|$key"
    emoji="❌"
    [ -n "$val" ] && emoji="✅"
    if [ -n "$val" ]; then
      printf "%2d) [%s] %-${max_key_len}s = %-${max_val_len}s # %s\n" \
        "$i" "$emoji" "$key" "$val" "$desc"
    else
      printf "%2d) [%s] %-${max_key_len}s   %*s# %s\n" \
        "$i" "$emoji" "$key" $((max_val_len + 3)) "" "$desc"
    fi
    i=$((i + 1))
  done < /tmp/params_list.txt
  log_info "⏳  0) 退出   g) 生成带参数的 tailscale up 命令"
  log_info "⏳  输入编号后回车即可修改: " 1
}

# 编辑指定参数
edit_param() {
  idx=$1
  key=$(echo "$OPTIONS" | grep "^$idx|" | cut -d'|' -f2)
  [ -z "$key" ] && return
  type=$(get_param_type "$key")
  desc=$(get_param_desc "$key")
  var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
  eval val=\$$var_name

  if [ "$type" = "flag" ]; then
    if [ -z "$val" ]; then
      eval "$var_name=1"
      log_info "✅  启用了 $key"
    else
      unset $var_name
      log_info "❌  禁用了 $key"
    fi
  else
    if [ -z "$val" ]; then
      log_info "🔑  请输入 $key 的值（$desc）：" 1
      read val
      [ -n "$val" ] && eval "$var_name=\"$val\"" && log_info "✅  保存了 $key 的值：$val"
    else
      log_info "🔄  当前 $key 的值为 $val，直接回车则清除，输入其他值则更新：" 1
      read newval
      if [ -n "$newval" ]; then
        eval "$var_name=\"$newval\""
        log_info "✅  更新了 $key 的值：$newval"
      else
        unset $var_name
        log_info "❌  删除了 $key 的值"
      fi
    fi
  fi
  save_conf
  sleep 1
}

# 生成带参数的 tailscale up 命令
generate_cmd() {
  cmd="tailscale up"
  temp_file=$(mktemp)
  echo "$PARAMS_LIST" > "$temp_file"

  while IFS= read -r line; do
    key=$(echo "$line" | cut -d':' -f1)
    type=$(echo "$line" | cut -d':' -f2)
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
    eval val=\$$var_name
    [ -z "$val" ] && continue

    if [ "$type" = "flag" ]; then
      cmd="$cmd $key"
      log_info "正在拼接命令: $key"
    else
      cmd="$cmd $key=$val"
      log_info "正在拼接命令: $key=$val"
    fi
  done < "$temp_file"

  rm -f "$temp_file"

  log_info "⏳ 生成命令："
  log_info "$cmd"
  log_info "🟢  是否立即执行该命令？[y/N]: " 1
  read runnow
  if [ -z "$runnow" ] || [ "$runnow" = "y" ] || [ "$runnow" = "Y" ]; then
    log_info "🚀  正在执行 tailscale up ..."
    eval "$cmd"
    log_info "⏳  请按回车继续..." 1
    read _
    exit 0
  fi
}

# 主函数
main() {
  while true; do
    load_conf
    show_status
    read input
    if [ "$input" = "0" ]; then
      exit 0
    elif [ "$input" = "g" ]; then
      generate_cmd
    elif echo "$OPTIONS" | grep -q "^$input|"; then
      edit_param "$input"
    fi
  done
}

main
