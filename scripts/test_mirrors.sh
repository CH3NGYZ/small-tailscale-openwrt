#!/bin/sh

set -e
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

safe_source "$INST_CONF"
if [ "$GITHUB_DIRECT" = "true" ]; then
    log_info "🌐  不测速代理池..."
    exit 0
fi
set_proxy_mode

TIME_OUT=20
SUM_FILE_NAME="SHA256SUMS.txt"
BIN_FILE_NAME="tailscaled-linux-amd64"
SUM_FILE_PATH="/tmp/$SUM_FILE_NAME"
BIN_FILE_PATH="/tmp/$BIN_FILE_NAME"
MIRROR_FILE_URL_SUFFIX="CH3NGYZ/test-github-proxies/raw/refs/heads/main/proxies.txt"
SUM_FILE_SUFFIX="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$SUM_FILE_NAME"
BIN_FILE_SUFFIX="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$BIN_FILE_NAME"

rm -f "$TMP_VALID_MIRRORS"

# 提前下载校验文件
SUM_URL_PROXY="${CUSTOM_RELEASE_PROXY}/${SUM_FILE_SUFFIX}"

if ! webget "$SUM_FILE_PATH" "$SUM_URL_PROXY" "echooff"; then
    log_error "❌  无法下载校验文件"
    exit 1
fi

sha_expected=$(grep "$BIN_FILE_NAME" "$SUM_FILE_PATH" | grep -v "$BIN_FILE_NAME.build" | awk '{print $1}')

# 镜像测试函数（下载并验证 tailscaled）
test_mirror() {
    local mirror=$(echo "$1" | sed 's|/*$|/|')
    local progress="$2"  # 当前/总数
    log_info "⏳  测试[$progress] $mirror"

    local start=$(date +%s.%N)

    if webget "$BIN_FILE_PATH" "${mirror}$BIN_FILE_SUFFIX" "echooff" ; then
        sha_actual=$(sha256sum "$BIN_FILE_PATH" | awk '{print $1}')
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
    rm -f "$BIN_FILE_PATH" "$SUM_FILE_PATH"
}

# 下载镜像列表
MIRROR_FILE_URL="${CUSTOM_RAW_PROXY}/${MIRROR_FILE_URL_SUFFIX}"

log_info "🛠️  正在下载镜像列表，请耐心等待..."

if webget "$MIRROR_LIST" "$MIRROR_FILE_URL" "echooff"; then
    log_info "✅  已下载镜像列表"
else
    log_warn "⚠️  无法下载镜像列表"
    send_notify "⚠️  下载远程镜像列表失败，已使用本地存在的镜像列表"
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