#!/bin/sh
SCRIPT_VERSION="v1.0.78"

# 检查并引入 /etc/tailscale/tools.sh 文件
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
safe_source "$INST_CONF"

if [ "$GITHUB_DIRECT" = "true" ] ; then
    custom_proxy="https://github.com/"
else
    custom_proxy="https://ghproxy.ch3ng.top/https://github.com/"
fi


# 自动判断 curl 和 wget 可用性
get_download_tool() {
    if command -v curl > /dev/null 2>&1; then
        echo "curl"
    elif command -v wget > /dev/null 2>&1; then
        echo "wget"
    else
        log_info "❌  没有找到 curl 或 wget, 无法下载或执行操作。"
        exit 1
    fi
}

# 获取可用的下载工具
download_tool=$(get_download_tool)

get_remote_version() {
    remote_ver_url="${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/scripts/helper.sh"
    log_info "获取远程文件: ${remote_ver_url}"
    if [ "$download_tool" = "curl" ]; then
        # 设置 5 秒超时
        timeout 10 curl -sSL "$remote_ver_url" | grep -E '^SCRIPT_VERSION=' | cut -d'"' -f2 > "$REMOTE_SCRIPTS_VERSION_FILE"
    else
        # 设置 5 秒超时
        timeout 10 wget -qO- "$remote_ver_url" | grep -E '^SCRIPT_VERSION=' | cut -d'"' -f2 > "$REMOTE_SCRIPTS_VERSION_FILE"
    fi
}

# 显示菜单
show_menu() {
    log_info "🎉  欢迎使用 Tailscale on OpenWRT 管理脚本 $SCRIPT_VERSION"
    if [ ! -s "$REMOTE_SCRIPTS_VERSION_FILE" ]; then
        log_info "⚠️  无法获取远程脚本版本"
    else
        remote_version=$(cat "$REMOTE_SCRIPTS_VERSION_FILE")
        log_info "📦  远程脚本版本: $remote_version $( 
            [ "$remote_version" != "$SCRIPT_VERSION" ] && echo '🚨脚本有更新, 请使用 12) 更新脚本' || echo '✅已是最新' 
        )"
    fi
    log_info "------------------------------------------"
    log_info "      1).  💾 安装 / 重装 Tailscale"
    log_info "------------------------------------------"
    log_info "      2).  📥 登录 Tailscale"
    log_info "      3).  📝 生成 Tailscale 启动命令"  # 新增选项
    log_info "      4).  📤 登出 Tailscale"
    log_info "      5).  ❌ 卸载 Tailscale"
    log_info "------------------------------------------"
    log_info "      6).  🔄 管理 Tailscale 自动更新"
    log_info "      7).  📦 查看本地 Tailscale 存在版本"
    log_info "      8).  📦 查看远程 Tailscale 最新版本"
    log_info "      9).  🔔 管理推送通知"
    log_info "     10).  📊 排序代理池"
    log_info "     11).  ♻️ 更新代理池"
    log_info "     12).  🛠️ 更新脚本包"
    log_info "     13).  📜 显示 Tailscale 更新日志"
    log_info "     14).  🔄 手动运行更新脚本"
    log_info "     15).  🔄 切换代理/直连状态"
    log_info "------------------------------------------"
    log_info "      0).  ⛔ 退出"
    log_info "------------------------------------------"
}

# 处理用户选择
handle_choice() {
    case $1 in
        1)
            $CONFIG_DIR/setup.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        2)
            if ! command -v tailscale >/dev/null 2>&1; then
                log_error "❌  tailscale 未安装或命令未找到"
                log_error "📦  请先安装 tailscale 后再运行本脚本"
            else
                local tmp_log="/tmp/tailscale_up.log"
                : > "$tmp_log"

                log_info "🚀  执行 tailscale up, 正在监控输出..."

                (
                    tailscale up >"$tmp_log" 2>&1
                    echo "__TS_UP_DONE__" >>"$tmp_log"
                ) &

                local auth_detected=false
                local fail_detected=false

                exec 3< <(tail -F "$tmp_log")
                tail_pid=$!                   # 记录 tail 进程的 PID
                while read -r line <&3; do
                    # 检测认证网址
                    echo "$line" | grep -qE "https://[^ ]*tailscale.com" && {
                        auth_url=$(echo "$line" | grep -oE "https://[^ ]*tailscale.com[^ ]*")
                        log_info "🔗  tailscale 等待认证, 请访问以下网址登录：$auth_url"
                        auth_detected=true
                        # 不退出
                    }

                    # 执行失败
                    echo "$line" | grep -qi "failed" && {
                        log_error "❌  tailscale up 执行失败：$line"
                        fail_detected=true
                        break
                    }

                    # 检测结束标志
                    echo "$line" | grep -q "__TS_UP_DONE__" && {
                        if [[ $auth_detected != true && $fail_detected != true ]]; then
                            if [[ -s "$tmp_log" ]]; then
                                log_info "✅  tailscale up 执行完成：$(cat "$tmp_log")"
                            else
                                log_info "✅  tailscale up 执行完成, 无输出"
                            fi
                        fi
                        break
                    }
                done
                exec 3<&-            # 关闭 FD3
                kill %1 2>/dev/null  # 杀掉 tailscale up 的后台进程
                kill "$tail_pid" 2>/dev/null  # 杀掉 tail 进程
                rm -f "$tmp_log"     # 删除临时日志

                tailscale status >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then
                    log_error "⚠️  tailscale 未登录或状态异常"
                else
                    log_info "🎉  tailscale 登录成功，状态正常"
                fi
            fi
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        3)  
            $CONFIG_DIR/tailscale_up_generater.sh
            ;;
        4)
            if ! command -v tailscale >/dev/null 2>&1; then
                log_error "❌  tailscale 未安装或命令未找到"
                log_error "📦  请先安装 tailscale 后再运行本脚本"
            else
                log_info "🔓  正在执行 tailscale logout..."
                
                if tailscale logout; then
                    sleep 3
                    if tailscale status 2>&1 | grep -q "Logged out."; then
                        log_info "✅  成功登出 tailscale"
                    else
                        log_error "⚠️  登出后状态未知，请检查 tailscale status 状态"
                    fi
                else
                    log_error "❌  tailscale logout 命令执行失败"
                fi
            fi
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        5)
            $CONFIG_DIR/uninstall.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        6)
            $CONFIG_DIR/update_ctl.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        7)
            if [ -f "$VERSION_FILE" ]; then
                log_info "📦  当前本地版本: $(cat "$VERSION_FILE")"
            else
                log_info "⚠️  本地未记录版本信息, 可能未安装 Tailscale"
            fi
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        8)
            $CONFIG_DIR/fetch_and_install.sh --dry-run
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        9)
            $CONFIG_DIR/notify_ctl.sh
            ;;
        10)
            $CONFIG_DIR/test_mirrors.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        11)
            if [ "$download_tool" = "curl" ]; then
                curl -sSL -o "$MIRROR_LIST" "${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/mirrors.txt"
            else
                wget -O "$MIRROR_LIST" "${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/mirrors.txt"
            fi
            if [ $? -ne 0 ]; then
                log_error "❌  mirrors.txt下载失败, 请手动将 ${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/mirrors.txt 文件内容复制到本地 $MIRROR_LIST 中"
                exit 0
            fi
            log_info "✅  mirrors.txt更新完毕, 请运行 [📊 排序代理池], 按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        12)
            if [ "$download_tool" = "curl" ]; then
                curl -sSL "${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh" | sh
            else
                wget -O- "${custom_proxy}CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh" | sh
            fi

            if [ $? -ne 0 ]; then
                log_error "❌  脚本更新失败, 脚本内置作者的代理失效"
                exit 0
            fi

            log_info "✅  请按回车重新加载脚本..."
            read khjfsdjkhfsd
            exec tailscale-helper
            ;;
        
        13)
            # 检查日志文件是否存在
            log_info "✅  本文件内容: "
            log_info "    local模式为: 开机检测 Tailscale 更新的日志, 和定时任务里检测更新的日志"
            log_info "    tmp  模式为: 开机下载 Tailscale 文件的日志, 和定时任务里检测更新的日志"
            if [ -f /tmp/tailscale_update.log ]; then
                # 如果文件存在，则显示日志内容
                log_info "    内容如下："
                log_info "    ---------------------------"
                cat /tmp/tailscale_update.log
                log_info "    ---------------------------"
            else
                # 如果文件不存在，则提示用户日志文件未找到
                log_error "❌  没有找到日志文件，更新脚本可能未执行！"
              
            fi
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        14)
            $CONFIG_DIR/autoupdate.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        15)
            $CONFIG_DIR/github_direct_ctl.sh
            log_info "✅  请按回车继续..." 1
            read khjfsdjkhfsd
            ;;
        0)
            exit 0
            ;;
        *)
            log_info "❌  无效选择, 请重新输入, 按回车继续..." 1
            read khjfsdjkhfsd
            ;;
    esac
}

# 主循环前执行一次远程版本检测
clear
log_info "🔄  正在检测脚本更新, 最多需要 10 秒..."
get_remote_version
clear

# 主循环
while true; do
    show_menu
    log_info "✅  请输入你的选择: " 1
    read choice
    log_info ""
    handle_choice "$choice"
    clear
done
