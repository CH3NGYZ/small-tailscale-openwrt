#!/bin/sh

[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
CONFIG_DIR="/etc/tailscale"
CONF_FILE="$CONFIG_DIR/tailscale_up.conf"

PARAMS_LIST="--accept-dns:flag:接受来自管理控制台的 DNS 设置
--accept-risk:value:接受风险类型并跳过确认（lose-ssh, all 或空）
--accept-routes:flag:接受其他节点广告的子网路由
--advertise-exit-node:flag:提供出口节点功能
--advertise-routes:value:共享子网路由，填写 IP 段，如 192.168.1.0/24
--advertise-tags:value:为设备添加标签权限
--auth-key:value:提供认证密钥自动登录
--exit-node:value:使用指定出口节点（IP 或名称）
--exit-node-allow-lan-access:flag:允许连接出口节点时访问本地局域网
--force-reauth:flag:强制重新认证
--hostname:value:使用自定义主机名
--login-server:value:指定控制服务器 URL
--netfilter-mode:value:控制防火墙规则：off/nodivert/on
--operator:value:使用非 root 用户操作 tailscaled
--qr:flag:生成二维码供网页登录
--reset:flag:重置未指定设置
--shields-up:flag:屏蔽来自网络其他设备的连接
--snat-subnet-routes:flag:对子网路由使用源地址转换
--stateful-filtering:flag:启用状态过滤（子网路由器/出口节点）
--ssh:flag:启用 Tailscale SSH 服务
--timeout:value:tailscaled 初始化超时时间（如10s）"

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
    # 输出每个加载的配置项
    log_info "加载配置: $key=$value"
  done < "$CONF_FILE"
}


# 保存配置到文件
save_conf() {
  echo -n > "$CONF_FILE"  # 清空文件内容
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
      log_info "🔄  当前 $key 的值为 $val，按回车继续编辑或输入新值，输入空值将删除该值：" 1
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
  
  # 将 PARAMS_LIST 内容写入临时文件
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
      log_info  "正在拼接命令: $key"
    else
      cmd="$cmd $key=$val"
      log_info  "正在拼接命令: $key=$val"
    fi
  done < "$temp_file"  # 从临时文件中读取内容
  
  # 删除临时文件
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
