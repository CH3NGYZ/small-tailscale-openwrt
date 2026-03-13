#!/bin/sh

set -o pipefail

SCRIPT_VERSION="v1.2.2"

# 检查并引入 /etc/tailscale/tools.sh 文件
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
safe_source "$INST_CONF"
apply_github_mode
ensure_arch || exit 1

HELPER_SCRIPT_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/scripts/helper.sh"
INSTALL_SCRIPT_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/install.sh"

get_remote_version() {
    local remote_ver_url="${CUSTOM_RAW_PROXY}/${HELPER_SCRIPT_URL_SUFFIX}"
    local tmp_helper="/tmp/helper_remote.$$"
    log_info "获取远程文件: ${remote_ver_url}"
    if webget "$tmp_helper" "$remote_ver_url" "echooff"; then
        grep -E '^SCRIPT_VERSION=' "$tmp_helper" | cut -d'"' -f2 > "$REMOTE_SCRIPTS_VERSION_FILE"
    fi
    rm -f "$tmp_helper"
}

# 显示菜单
show_menu() {
    log_info "🎉  欢迎使用 Tailscale on OpenWRT 管理脚本 $SCRIPT_VERSION"
    if [ ! -s "$REMOTE_SCRIPTS_VERSION_FILE" ]; then
        log_info "⚠️  无法获取远程脚本版本"
    else
        remote_version=$(cat "$REMOTE_SCRIPTS_VERSION_FILE")
        log_info "📦  远程脚本版本: $remote_version $( 
            [ "$remote_version" != "$SCRIPT_VERSION" ] && echo '🚨脚本有更新, 请使用 13) 更新脚本包' || echo '✅已是最新' 
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
    log_info "      7).  🔄 手动运行更新脚本"
    log_info "      8).  🔄 切换代理/直连状态"
    log_info "      9).  📦 查看本地 Tailscale 存在版本"
    log_info "     10).  📦 查看远程 Tailscale 最新版本"
    log_info "     11).  🔔 管理推送通知"
    log_info "     12).  📊 排序代理池"
    log_info "     13).  🛠️ 更新脚本包"
    log_info "     14).  📜 显示 Tailscale 更新日志"
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
            read _
            ;;
        2)
            if ! command -v tailscale >/dev/null 2>&1; then
                log_error "❌  tailscale 未安装或命令未找到"
                log_error "📦  请先安装 tailscale 后再运行本脚本"
            else
                local tmp_log="/tmp/tailscale_up.log"
                local pipe="/tmp/tailscale_up.pipe"

                : > "$tmp_log"
                [ -p "$pipe" ] && rm -f "$pipe"
                mkfifo "$pipe"

                log_info "🚀  执行 tailscale up, 正在生成登录链接..."

                # 后台运行 tailscale up
                (
                    tailscale up >"$tmp_log" 2>&1
                    echo "__TS_UP_DONE__" >>"$tmp_log"
                ) &
                ts_up_pid=$!

                # 用 tail -F 写入命名管道
                tail -F "$tmp_log" >"$pipe" &
                tail_pid=$!

                auth_detected=false
                fail_detected=false

                while read -r line <"$pipe"; do
                    echo "$line" | grep -qE "https://[^ ]*tailscale.com" && {
                        auth_url=$(echo "$line" | grep -oE "https://[^ ]*tailscale.com[^ ]*")
                        log_info "🔗  tailscale 等待认证, 请访问以下网址登录：$auth_url"
                        auth_detected=true
                    }

                    echo "$line" | grep -qi "failed" && {
                        log_error "❌  tailscale up 执行失败：$line"
                        fail_detected=true
                        break
                    }

                    echo "$line" | grep -q "__TS_UP_DONE__" && {
                        if [ "$auth_detected" != "true" ] && [ "$fail_detected" != "true" ]; then
                            if [ -s "$tmp_log" ]; then
                                log_info "✅  tailscale up 执行完成：$(cat "$tmp_log")"
                            else
                                log_info "✅  tailscale up 执行完成, 无输出"
                            fi
                        fi
                        break
                    }
                done

                # 清理后台进程
                kill "$ts_up_pid" 2>/dev/null
                kill "$tail_pid" 2>/dev/null

                # 删除临时文件
                rm -f "$tmp_log" "$pipe"

                # 检查登录状态
                if ! tailscale status >/dev/null 2>&1; then
                    log_error "⚠️  tailscale 未登录或状态异常"
                else
                    log_info "🎉  tailscale 登录成功，状态正常"
                fi

            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        3)  
            $CONFIG_DIR/tailscale_up_generator.sh
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
            read _
            ;;
        5)
            $CONFIG_DIR/uninstall.sh
            log_info "✅  请按回车退出..." 1
            read _
            exit 0
            ;;
        6)
            $CONFIG_DIR/update_ctl.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        7)
            $CONFIG_DIR/autoupdate.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        8)
            $CONFIG_DIR/github_direct_ctl.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        9)
            if [ -f "$VERSION_FILE" ]; then
                log_info "📦  当前本地版本: $(cat "$VERSION_FILE")"
            else
                log_info "⚠️  本地未记录版本信息, 可能未安装 Tailscale"
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        10)
            log_info "$($CONFIG_DIR/fetch_and_install.sh --dry-run)"
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        11)
            $CONFIG_DIR/notify_ctl.sh
            ;;
        12)
            $CONFIG_DIR/test_mirrors.sh
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        13)
            URL="${CUSTOM_RAW_PROXY}/${INSTALL_SCRIPT_URL_SUFFIX}"
            tmpfile=$(mktemp)
            if webget "$tmpfile" "$URL" "echooff"; then
                # exec 会替换当前进程，不会返回
                exec sh "$tmpfile" < /dev/tty
            else
                log_error "❌ 脚本下载失败, 脚本内置作者的代理失效"
                rm -f "$tmpfile"
                log_info "✅  请按回车继续..." 1
                read _
            fi
            ;;
        14)
            # 检查日志文件是否存在
            if [ -f /tmp/tailscale_update.log ]; then
                # 如果文件存在，则显示日志内容
                log_info "    日志内容如下："
                log_info "    ---------------------------"
                cat /tmp/tailscale_update.log
                log_info "    ---------------------------"
            else
                # 如果文件不存在，则提示用户日志文件未找到
                log_error "❌  没有找到日志文件，更新脚本可能未执行！"
            fi
            log_info "✅  请按回车继续..." 1
            read _
            ;;
        0)
            log_info "👋  退出脚本"
            sleep 1
            clear
            exit 0
            ;;
        *)
            log_info "❌  无效选择, 请重新输入, 按回车继续..." 1
            read _
            ;;
    esac
}

# 主循环前执行一次远程版本检测
clear
log_info "🔄  正在检测脚本更新, 最多需要 5 秒..."
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
