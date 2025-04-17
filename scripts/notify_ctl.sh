#!/bin/sh
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

show_menu() {
    clear
    echo "🛠️ 通知配置管理"
    echo "--------------------------------"
    echo "1. 设置Server酱SendKey"
    echo "2. 设置Bark的设备码"
    echo "3. 设置ntfy的订阅码"
    echo "4. 切换Server酱通知开关"
    echo "5. 切换Bark通知开关"
    echo "6. 切换ntfy通知开关"
    echo "7. 发送测试通知"
    echo "8. 查看当前配置"
    echo "9. 退出"
    echo "--------------------------------"
}

# 设置Server酱的SendKey
edit_key() {
    echo "可以从 https://sct.ftqq.com/sendkey 获取 Server酱 SendKey"
    read -p "请输入 Server酱 SendKey (留空禁用) : " key
    sed -i "s|^SERVERCHAN_KEY=.*|SERVERCHAN_KEY=\"$key\"|" "$NTF_CONF"
}

# 设置Bark的设备码
edit_bark() {
    echo "请输入 Bark 设备码 (留空禁用):"
    read -p "Bark设备码: " bark_key
    sed -i "s|^BARK_KEY=.*|BARK_KEY=\"$bark_key\"|" "$NTF_CONF"
}

# 设置ntfy的订阅码
edit_ntfy() {
    echo "请输入 NTFY 订阅码 (留空禁用):"
    read -p "NTFY订阅码: " ntfy_key
    sed -i "s|^NTFY_KEY=.*|NTFY_KEY=\"$ntfy_key\"|" "$NTF_CONF"
}

# 切换通知开关
toggle_setting() {
    local setting=$1
    current=$(grep "^$setting=" "$NTF_CONF" | cut -d= -f2)
    new_value=$([ "$current" = "1" ] && echo "0" || echo "1")
    sed -i "s|^$setting=.*|$setting=$new_value|" "$NTF_CONF"
}


# 测试通知
test_notify() {
    send_notify "Tailscale测试通知" "这是测试消息" "时间: $(date '+%F %T')"
}

# 查看当前配置
show_config() {
    echo "当前通知配置:"
    echo "--------------------------------"
    grep -v '^#' "$NTF_CONF" | while read -r line; do
        name=${line%%=*}
        value=${line#*=}
        case "$name" in
            NOTIFY_SERVERCHAN)
                echo "Server酱通知: $([ "$value" = "1" ] && echo "✅" || echo "❌")" ;;
            NOTIFY_BARK)
                echo "Bark通知: $([ "$value" = "1" ] && echo "✅" || echo "❌")" ;;
            NOTIFY_NTFY)
                echo "ntfy通知: $([ "$value" = "1" ] && echo "✅" || echo "❌")" ;;
            SERVERCHAN_KEY)
                echo "Server酱 SendKey: ${value:+"(已设置)"}" ;;
            BARK_KEY)
                echo "Bark 设备码: ${value:+"(已设置)"}" ;;
            NTFY_KEY)
                echo "NTFY 订阅码: ${value:+"(已设置)"}" ;;
        esac
    done
    echo "--------------------------------"
}

# 主菜单
while :; do
    show_menu
    read -p "请选择 [1-9]: " choice
    case $choice in
        1) edit_key ;;
        2) edit_bark ;;
        3) edit_ntfy ;;
        4) toggle_setting "NOTIFY_SERVERCHAN" ;;
        5) toggle_setting "NOTIFY_BARK" ;;
        6) toggle_setting "NOTIFY_NTFY" ;;
        7) test_notify ;;
        8) show_config ;;
        9) exit 0 ;;
        *) echo "无效选择" ;;
    esac
    read -p "按回车键继续..."
done
