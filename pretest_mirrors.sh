#!/bin/sh

set -e
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh
TIME_OUT=10
CONFIG_DIR="/etc/tailscale"
MIRROR_FILE_URL="CH3NGYZ/test-github-proxies/raw/refs/heads/main/proxies.txt"
SUM_URL="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/SHA256SUMS.txt"
INST_CONF="$CONFIG_DIR/install.conf"
. "$INST_CONF"
BIN_NAME="tailscaled-linux-amd64"
SUM_NAME="SHA256SUMS.txt"
BIN_PATH="/tmp/$BIN_NAME"
SUM_PATH="/tmp/$SUM_NAME"
VALID_MIRRORS="$CONFIG_DIR/valid_proxies.txt"
TMP_VALID_MIRRORS="/tmp/valid_mirrors.tmp"
MIRROR_LIST="$CONFIG_DIR/proxies.txt"
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

sha_expected=$(grep "$BIN_NAME" "$SUM_PATH" | awk '{print $1}')

# 镜像测试函数（下载并验证 tailscaled）
test_mirror() {
    local mirror=$(echo "$1" | sed 's|/*$|/|')
    local url_bin="${mirror}CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$BIN_NAME"
    local progress="$2"  # 当前/总数
    log_info "⏳   测试[$progress] $mirror"

    local start=$(date +%s.%N)

    if webget "$BIN_PATH" "$url_bin" "echooff" ; then
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

# 手动回退逻辑
manual_fallback() {
    log_info "🧩  手动选择镜像源："
    log_info "     1) ✍️ 手动输入备选镜像  2) 🌐  使用直连  3) ❌  退出"
    while :; do
        log_info "       请选择: " 1
        read choice
        case $choice in
            1)
                log_info "⏳  输入镜像URL (需要和 $MIRROR_FILE_URL 拼凑后能下载此文件，如 https://ghproxy.example.com/https://github.com/): " 1
                read  mirror
                mirror=$(echo "$mirror" | sed 's|/*$|/|')
                if echo "$mirror" | grep -qE '^https?://'; then
                    echo "$mirror" > "$MIRROR_LIST"
                    test_mirror "$mirror"
                    [ -s "$TMP_VALID_MIRRORS" ] && sort -n "$TMP_VALID_MIRRORS" | awk '{print $2}' > "$VALID_MIRRORS"
                    return 0
                else
                    log_warn "⚠️  地址必须以 http:// 或 https:// 开头"
                fi
                ;;
            2)
                touch "$VALID_MIRRORS"  # 空文件表示直连
                return 1
                ;;
            3)
                exit 1
                ;;
        esac
    done
}

# 下载镜像列表
MIRROR_FILE_URL_PROXY="https://ghproxy.ch3ng.top/https://github.com/${MIRROR_FILE_URL}"
MIRROR_FILE_URL_DIRECT="https://github.com/${MIRROR_FILE_URL}"

log_info "🛠️  正在下载镜像列表，请耐心等待..."

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
            manual_fallback
            exit 1
        }
    fi
fi


log_warn "⚠️  测试代理下载tailscale可执行文件花费的时间中, 每个代理最长需要 $TIME_OUT 秒, 安装时仅测试5个正常连通的代理，请耐心等待......"

# 主流程：测试所有镜像，限制最多5个有效代理
total=$(grep -cve '^\s*$' "$MIRROR_LIST")  # 排除空行
index=0

while read -r mirror; do
    [[ -n "$mirror" && "$mirror" == http* ]] || continue
    index=$((index + 1))
    test_mirror "$mirror" "$index/$total"
    
    # 读取 TMP_VALID_MIRRORS 文件行数
    valid_count=$(wc -l < "$TMP_VALID_MIRRORS" 2>/dev/null || echo 0)
    
    # 如果已经找到5个有效代理，则跳出循环
    if [ "$valid_count" -ge 5 ]; then
        log_info "✅ 已找到5个有效的代理，跳过剩余的代理"
        break
    fi
done < "$MIRROR_LIST"



# 排序并保存最佳镜像
if [ -s "$TMP_VALID_MIRRORS" ]; then
    sort -n "$TMP_VALID_MIRRORS" | awk '{print $2}' > "$VALID_MIRRORS"
    log_info "🏆 最佳镜像: $(head -n1 "$VALID_MIRRORS")"
elif [ -f "$VALID_MIRRORS" ] && [ ! -s "$VALID_MIRRORS" ]; then
    log_info "🌐  选择了直连模式，跳过测速结果"
else
    manual_fallback
fi

rm -f "$TMP_VALID_MIRRORS"
