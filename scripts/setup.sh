#!/bin/sh

set -e
clear
. /etc/tailscale/tools.sh || { log_error "❌  加载 tools.sh 失败"; exit 1; }
log_info "加载公共函数..."

log_info "加载配置文件..."
safe_source "$INST_CONF" || log_warn "⚠️  INST_CONF 未找到或无效，使用默认配置"
apply_github_mode

GITHUB_API_RELEASE_LIST_URL_SUFFIX="repos/ch3ngyz/small-tailscale-openwrt/releases"

# 默认值
MODE=""
AUTO_UPDATE=""
VERSION="latest"
ARCH=$(detect_arch)
HOST_NAME=$(uci show system.@system[0].hostname | awk -F"'" '{print $2}')

has_args=false  # 🔧  新增：标记是否传入了参数
if [ "$GITHUB_DIRECT" = "true" ] ; then
    GITHUB_DIRECT=true
else
    GITHUB_DIRECT=false
fi

# 若有参数, 接受 --tmp为使用内存模式, --auto-update为自动更新
while [ $# -gt 0 ]; do
    has_args=true  # 🔧  有参数，关闭交互模式
    case "$1" in
        --tmp) MODE="tmp"; shift ;;
        --auto-update) AUTO_UPDATE=true; shift ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

# 若无参数，进入交互模式
if [ "$has_args" = false ]; then
    log_info
    log_info "📮  请选择安装 Tailscale 模式："
    log_info "     1/y/Y/直接回车). 本地安装  🏠"
    log_info "     2/n/N        ). 内存安装  💻"
    log_info "     0/e/E/其他字符). 退出安装  ⛔"
    log_info "⏳  请输入选项: " 1
    read mode_input

    case "$mode_input" in
        1|"y"|"Y"|"") MODE="local" ;;
        2|"n"|"N") MODE="tmp" ;;
        *) log_error "❌  已取消安装"; exit 1 ;;
    esac

    log_info
    log_info "🔄  是否启用 Tailscale 自动更新？"
    log_info "     1/y/Y/直接回车). 启用更新  ✅"
    log_info "     2/n/N        ). 禁用更新  ❌"
    log_info "     0/e/E/其他字符). 退出安装  ⛔"
    log_info "⏳  请输入选项: " 1
    read update_input

    case "$update_input" in
        1|"y"|"Y"|"") AUTO_UPDATE=true ;;
        2|"n"|"N") AUTO_UPDATE=false ;;
        *) log_error "⛔  已取消安装"; exit 1 ;;
    esac
    log_info

    PAGE=1
    PER_PAGE=10

    while true; do
        clear
        log_info "🧩 正在拉取版本列表（第 $PAGE 页，每页 $PER_PAGE 条）..."

        API_URL="${CUSTOM_API_PROXY}/${GITHUB_API_RELEASE_LIST_URL_SUFFIX}?per_page=${PER_PAGE}&page=${PAGE}"
        retry=0
        while [ $retry -lt 3 ]; do
            if webget "/tmp/response.json" "$API_URL"; then
                break
            fi
            retry=$((retry + 1))
            log_error "❌ 拉取失败（$retry/3），重试中..."
            sleep 1
        done

        if [ $retry -ge 3 ]; then
            log_error "❌ 连续 3 次失败，取消操作"
            exit 1
        fi

        # 从返回解析 tags
        TAGS_TMP="/tmp/.tags.$$"
        if command -v jq >/dev/null 2>&1; then
            jq -r '.[].tag_name // empty' /tmp/response.json > "$TAGS_TMP"
        else
            grep -o '"tag_name"[ ]*:[ ]*"[^"]*"' /tmp/response.json \
                | sed 's/.*"tag_name"[ ]*:[ ]*"\([^"]*\)".*/\1/' \
                > "$TAGS_TMP"
        fi
        rm -f /tmp/response.json

        # 判断是否有 tags
        if [ ! -s "$TAGS_TMP" ]; then
            log_info "⚠️ 本页没有更多版本了"
            log_info "➡️ 输入 p 返回上一页，或 q 退出"
            read op
            case "$op" in
                p|P) [ "$PAGE" -gt 1 ] && PAGE=$((PAGE - 1)) ;;
                q|Q) exit 1 ;;
            esac
            continue
        fi

        # 展示本页 tags
        i=1
        log_info
        log_info "🔧 可用版本列表（第 $PAGE 页）："
        while read -r tag; do
            log_info "  [$i] $tag"
            eval "TAG_$i=\"$tag\""
            i=$((i + 1))
        done < "$TAGS_TMP"
        total=$((i - 1))

        log_info ""
        log_info "⏳ 输入序号选择版本（回车=最新，n=下一页，p=上一页，q=退出）：" 1
        read input
        input=$(echo "$input" | xargs)

        case "$input" in
            "")  # 直接回车 = 使用 latest
                VERSION="latest"
                break
                ;;
            q|Q)
                log_error "⛔ 已取消安装"
                exit 1
                ;;
            n|N)
                PAGE=$((PAGE + 1))
                continue
                ;;
            p|P)
                [ "$PAGE" -gt 1 ] && PAGE=$((PAGE - 1))
                continue
                ;;
            *)
                # 选择一个 tag
                if echo "$input" | grep -qE '^[0-9]+$' \
                    && [ "$input" -ge 1 ] \
                    && [ "$input" -le "$total" ]; then

                    eval "VERSION=\$TAG_$input"
                    log_info "✅ 使用指定版本: $VERSION"
                    break
                else
                    log_error "❌ 无效的选择"
                    sleep 1
                fi
                ;;
        esac
    done
    rm -f "$TAGS_TMP"
    clear
fi


# 兜底
MODE=${MODE:-local}
AUTO_UPDATE=${AUTO_UPDATE:-false}
VERSION=${VERSION:-latest}

cat > "$INST_CONF" <<EOF
# 安装配置记录
MODE=$MODE
AUTO_UPDATE=$AUTO_UPDATE
VERSION=$VERSION
ARCH=$ARCH
HOST_NAME=$HOST_NAME
GITHUB_DIRECT=$GITHUB_DIRECT
TIMESTAMP=$(date +%s)
EOF

# 显示当前配置
echo
log_info "🎯  当前安装配置："
log_info "🎯  模式: $MODE"
log_info "🎯  更新: $AUTO_UPDATE"
log_info "🎯  版本: $VERSION"
log_info "🎯  架构: $ARCH"
log_info "🎯  昵称: $HOST_NAME"
log_info "🎯  直连: $GITHUB_DIRECT"

echo

# 停止服务之前，检查服务文件是否存在
if [ -f /etc/init.d/tailscale ]; then
    log_info "🔴  停止 tailscaled 服务..."
    /etc/init.d/tailscale stop 2>/dev/null || log_warn "⚠️  停止 tailscaled 服务失败，继续清理残留文件"
else
    log_warn "⚠️  未找到 tailscale 服务文件，跳过停止服务步骤"
fi

# 清理残留文件
log_info "🧹  清理残留文件..."
if [ "$MODE" = "local" ]; then
    log_info "🗑️  删除本地安装的残留文件..."
    rm -f /usr/local/bin/tailscale
    rm -f /usr/local/bin/tailscaled
fi

if [ "$MODE" = "tmp" ]; then
    log_info "🗑️  删除/tmp中的残留文件..."
    rm -f /tmp/tailscale
    rm -f /tmp/tailscaled
fi

# 安装开始
log_info "🚀  开始安装 Tailscale..."
"$CONFIG_DIR/fetch_and_install.sh" \
    --mode="$MODE" \
    --version="$VERSION" \
    --mirror-list="$VALID_MIRRORS"

# 初始化服务
log_info "🛠️  初始化服务..."
"$CONFIG_DIR/setup_service.sh" --mode="$MODE"

# 设置定时任务
log_info "⏰  设置定时任务..."
"$CONFIG_DIR/setup_cron.sh" --auto-update="$AUTO_UPDATE"
