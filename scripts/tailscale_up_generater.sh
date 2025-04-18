#!/bin/bash
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
CONF_FILE="$CONFIG_DIR/tailscale_up.conf"

# 参数定义（类型: flag/value, 描述）
declare -A PARAMS_TYPE=(
  ["--accept-dns"]=flag
  ["--accept-risk"]=value
  ["--accept-routes"]=flag
  ["--advertise-exit-node"]=flag
  ["--advertise-routes"]=value
  ["--advertise-tags"]=value
  ["--auth-key"]=value
  ["--exit-node"]=value
  ["--exit-node-allow-lan-access"]=flag
  ["--force-reauth"]=flag
  ["--hostname"]=value
  ["--login-server"]=value
  ["--netfilter-mode"]=value
  ["--operator"]=value
  ["--qr"]=flag
  ["--reset"]=flag
  ["--shields-up"]=flag
  ["--snat-subnet-routes"]=flag
  ["--stateful-filtering"]=flag
  ["--ssh"]=flag
  ["--timeout"]=value
)

# 参数说明
declare -A PARAMS_DESC=(
  ["--accept-dns"]="接受来自管理控制台的 DNS 设置"
  ["--accept-risk"]="接受风险类型并跳过确认（lose-ssh, all 或空）"
  ["--accept-routes"]="接受其他节点广告的子网路由"
  ["--advertise-exit-node"]="提供出口节点功能"
  ["--advertise-routes"]="共享子网路由，填写 IP 段，如 192.168.1.0/24"
  ["--advertise-tags"]="为设备添加标签权限"
  ["--auth-key"]="提供认证密钥自动登录"
  ["--exit-node"]="使用指定出口节点（IP 或名称）"
  ["--exit-node-allow-lan-access"]="允许连接出口节点时访问本地局域网"
  ["--force-reauth"]="强制重新认证"
  ["--hostname"]="使用自定义主机名"
  ["--login-server"]="指定控制服务器 URL"
  ["--netfilter-mode"]="控制防火墙规则：off/nodivert/on"
  ["--operator"]="使用非 root 用户操作 tailscaled"
  ["--qr"]="生成二维码供网页登录"
  ["--reset"]="重置未指定设置"
  ["--shields-up"]="屏蔽来自网络其他设备的连接"
  ["--snat-subnet-routes"]="对子网路由使用源地址转换"
  ["--stateful-filtering"]="启用状态过滤（子网路由器/出口节点）"
  ["--ssh"]="启用 Tailscale SSH 服务"
  ["--timeout"]="tailscaled 初始化超时时间（如10s）"
)

# 加载配置
load_conf() {
  [ -f "$CONF_FILE" ] && source "$CONF_FILE"
}

# 保存配置
save_conf() {
  > "$CONF_FILE"
  for key in "${!PARAMS_TYPE[@]}"; do
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')  # 转换为合法变量名
    value="${!var_name}"  # 获取转换后的变量值
    [[ -n "$value" ]] && echo "$key=\"$value\"" >> "$CONF_FILE"
  done
}

# 展示状态
show_status() {
  clear
  log_info "当前 tailscale up 参数状态："
  i=1
  for key in "${!PARAMS_TYPE[@]}"; do
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')  # 将变量名转换为合法形式
    val="${!var_name}"  # 获取变量值
    emoji="❌"
    [[ -n "$val" ]] && emoji="✅"
    printf "%2d) [%s] %s %s\n" $i "$emoji" "$key" "${PARAMS_DESC[$key]}"
    OPTIONS[$i]="$key"
    ((i++))
  done
  log_info ""  # 空行，等价于 echo ""
  log_info "0) 退出   r) 执行 tailscale up   g) 生成命令"
}

# 修改参数
edit_param() {
  idx=$1
  key="${OPTIONS[$idx]}"
  var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')  # 将变量名转换为合法形式
  type="${PARAMS_TYPE[$key]}"
  
  if [[ "$type" == "flag" ]]; then
    log_info "⏳ 启用 $key ? (默认是启用，按回车继续，输入非y即不启用): " 1
    read -r yn
    if [[ "$yn" != "y" && "$yn" != "Y" ]]; then
      unset $var_name
    else
      declare -g $var_name=1
    fi
  else
    log_info "🔑 请输入 $key 的值（${PARAMS_DESC[$key]}）：" 1
    read -r val
    if [[ -n "$val" ]]; then
      declare -g $var_name="$val"
    else
      unset $var_name
    fi
  fi
  save_conf
}

# 生成命令
generate_cmd() {
  cmd="tailscale up"
  for key in "${!PARAMS_TYPE[@]}"; do
    var_name=$(echo "$key" | tr '-' '_' | tr '[:lower:]' '[:upper:]')  # 转换为合法变量名
    val="${!var_name}"  # 获取变量值
    if [[ -n "$val" ]]; then
      if [[ "${PARAMS_TYPE[$key]}" == "flag" ]]; then
        cmd+=" $key"  # 对于 flag 类型的参数，只加上参数名
      else
        cmd+=" $key=$val"  # 对于 value 类型的参数，拼接参数名和值
      fi
    fi
  done
  log_info "\n生成命令：" 
  log_info "$cmd"
}

# 主循环
main() {
  while true; do
    load_conf
    show_status
    log_info "⏳ 请输入要修改的参数编号（0退出，g生成命令，r运行）：" 1
    read input
    if [[ "$input" == "0" ]]; then
      exit 0
    elif [[ "$input" == "g" ]]; then
      generate_cmd
      log_info "⏳ 按回车继续..." 1
      read dasdsa51561 
    elif [[ "$input" == "r" ]]; then
      generate_cmd
      log_info "\n即将执行..."
      eval $cmd
      exit 0
    elif [[ "$input" =~ ^[0-9]+$ && -n "${OPTIONS[$input]}" ]]; then
      edit_param $input
    fi
  done
}

main
