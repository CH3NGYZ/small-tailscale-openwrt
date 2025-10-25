#!/bin/sh

set -e
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

safe_source "$INST_CONF"
if [ "$GITHUB_DIRECT" = "true" ]; then
    log_info "🌐  不测速代理池..."
    return 0
fi

TIME_OUT=10
BIN_NAME="tailscaled-linux-amd64"
SUM_NAME="SHA256SUMS.txt"
BIN_PATH="/tmp/$BIN_NAME"
SUM_PATH="/tmp/$SUM_NAME"
MIRROR_FILE_URL="CH3NGYZ/test-github-proxies/raw/refs/heads/main/proxies.txt"
SUM_URL="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$SUM_NAME"
BIN_URL="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$BIN_NAME"

rm -f "$TMP_VALID_MIRRORS"

log_info() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    [ $# -eq 2 ] || echo
}

log_warn() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    [ $# -eq 2 ] || echo
}

log_error() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    [ $# -eq 2 ] || echo
}

# 下载函数
webget() {
    local result=""
    if command -v curl >/dev/null 2>&1; then
        [ "$3" = "echooff" ] && local progress='-s' || local progress='-#'
        [ -z "$4" ] && local redirect='-L' || local redirect=''
        result=$(timeout $TIME_OUT curl -w %{http_code} -H "User-Agent: Mozilla/5.0 (curl-compatible)" $progress $redirect -ko "$1" "$2")
        [ -n "$(echo "$result" | grep -e ^2)" ] && result="200"
    elif command -v wget >/dev/null 2>&1; then
        [ "$3" = "echooff" ] && local progress='-q' || local progress='--show-progress'
        [ "$4" = "rediroff" ] && local redirect='--max-redirect=0' || local redirect=''
        local certificate='--no-check-certificate'
        timeout $TIME_OUT wget --header="User-Agent: Mozilla/5.0" $progress $redirect $certificate -O "$1" "$2"
        [ $? -eq 0 ] && result="200"
    else
        log_error "❌  错误：curl 和 wget 都不可用"
        return 1
    fi
    [ "$result" = "200" ] && return 0 || return 1
}

# 提前下载校验文件
SUM_URL_PROXY="https://ghproxy.ch3ng.top/https://github.com/${SUM_URL}"
SUM_URL_DIRECT="https://github.com/${SUM_URL}"

if [ "$GITHUB_DIRECT" = "true" ] ; then
    log_info "📄  使用 GitHub 直连下载: $SUM_URL_DIRECT"
    if ! webget "$SUM_PATH" "$SUM_URL_DIRECT" "echooff"; then
        log_error "❌  无法下载校验文件（直连失败）"
        exit 1
    fi
else
    log_info "🔗  使用固定代理下载: $SUM_URL_PROXY"
    if ! webget "$SUM_PATH" "$SUM_URL_PROXY" "echooff"; then
        log_info "🔗  代理失效，尝试直连: $SUM_URL_DIRECT"
        if ! webget "$SUM_PATH" "$SUM_URL_DIRECT" "echooff"; then
            log_error "❌  无法下载校验文件（代理+直连均失败）"
            exit 1
        fi
    fi
fi

sha_expected=$(grep "$BIN_NAME" "$SUM_PATH" | grep -v "$BIN_NAME.build" | awk '{print $1}')

# 镜像测试函数（下载并验证 tailscaled）
test_mirror() {
    local mirror=$(echo "$1" | sed 's|/*$|/|')
    local progress="$2"  # 当前/总数
    log_info "⏳   测试[$progress] $mirror"

    local start=$(date +%s.%N)

    if webget "$BIN_PATH" "${mirror}$BIN_URL" "echooff" ; then
        sha_actual=$(sha256sum "$BIN_PATH" | awk '{print $1}')
        if [ "$sha_expected" = "$sha_actual" ]; then
            local end=$(date +%s.%N)
            local dl_time=$(awk "BEGIN {printf \"%.2f\", $end - $start}")
            log_info "✅  用时 ${dl_time}s"
            echo "$dl_time $mirror" >> "$TMP_VALID_MIRRORS"
        else
            log_warn "❌  校验失败"
        fi
    else
        log_warn "❌  下载失败"
    fi
    rm -f "$BIN_PATH" "$SUM_PATH"
}

# 下载镜像列表
MIRROR_FILE_URL_PROXY="https://ghproxy.ch3ng.top/https://github.com/${MIRROR_FILE_URL}"
MIRROR_FILE_URL_DIRECT="https://github.com/${MIRROR_FILE_URL}"

log_info "🛠️  正在下载镜像列表，请耐心等待..."

if [ "$GITHUB_DIRECT" = "true" ] ; then
    if webget "$MIRROR_LIST" "$MIRROR_FILE_URL_DIRECT" "echooff"; then
        log_info "✅  已通过直连下载镜像列表"
    else
        log_warn "⚠️  无法下载镜像列表，尝试使用旧版本（如果存在）"
        [ -s "$MIRROR_LIST" ] || {
            log_error "❌  没有可用镜像列表，且下载失败"
            if should_notify_mirror_fail; then
                send_notify "❌  下载远程镜像列表失败，且本地也没有可用镜像列表"
            fi
            exit 1
        }
        send_notify "⚠️  下载远程镜像列表失败，已使用本地存在的镜像列表"
    fi
else
    if webget "$MIRROR_LIST" "$MIRROR_FILE_URL_PROXY" "echooff"; then
        log_info "✅  已更新镜像列表"
    else
        log_warn "⚠️  无法通过代理下载镜像列表，尝试直连: $MIRROR_FILE_URL_DIRECT"
        if webget "$MIRROR_LIST" "$MIRROR_FILE_URL_DIRECT" "echooff"; then
            log_info "✅  已通过直连下载镜像列表"
        else
            log_warn "⚠️  无法下载镜像列表，尝试使用旧版本（如果存在）"
            [ -s "$MIRROR_LIST" ] || {
                log_error "❌  没有可用镜像列表，且下载失败"
                if should_notify_mirror_fail; then
                    send_notify "❌  下载远程镜像列表失败，且本地也没有可用镜像列表"
                fi
                exit 1
            }
            send_notify "⚠️  下载远程镜像列表失败，已使用本地存在的镜像列表"
        fi
    fi
fi

log_warn "⚠️  测试代理下载tailscale可执行文件花费的时间中, 每个代理最长需要 $TIME_OUT 秒, 请耐心等待......"
# 主流程：测试所有镜像
total=$(grep -cve '^\s*$' "$MIRROR_LIST")  # 排除空行
index=0
while read -r mirror; do
    [ -n "$mirror" ] || continue
    index=$((index + 1))
    test_mirror "$mirror" "$index/$total"
done < "$MIRROR_LIST"

# 排序并保存最佳镜像
if [ -s "$TMP_VALID_MIRRORS" ]; then
    sort -n "$TMP_VALID_MIRRORS" | awk '{print $2}' > "$VALID_MIRRORS"
    log_info "🏆 最佳镜像: $(head -n1 "$VALID_MIRRORS")"
else
    if should_notify_mirror_fail; then
        send_notify "❌  所有镜像均失效" "请手动配置代理"
    fi
fi

rm -f "$TMP_VALID_MIRRORS"