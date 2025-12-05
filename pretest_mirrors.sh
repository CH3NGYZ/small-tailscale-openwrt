#!/bin/sh

set -e
set -o pipefail
[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh

TIME_OUT=10
CONFIG_DIR="/etc/tailscale"
INST_CONF="$CONFIG_DIR/install.conf"
safe_source "$INST_CONF"

BIN_NAME="tailscaled-linux-amd64"
BIN_PATH="/tmp/$BIN_NAME"
SUM_NAME="SHA256SUMS.txt"
SUM_PATH="/tmp/$SUM_NAME"

BIN_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$BIN_NAME"
SHA256SUMS_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/releases/latest/download/$SUM_NAME"

PROXIES_LIST_NAME="proxies.txt"
PROXIES_LIST_PATH="$CONFIG_DIR/$PROXIES_LIST_NAME"
PROXIES_LIST_URL_SUFFIX="CH3NGYZ/test-github-proxies/main/$PROXIES_LIST_NAME"

VALID_MIRRORS_PATH="$CONFIG_DIR/valid_proxies.txt"
TMP_VALID_MIRRORS_PATH="/tmp/valid_mirrors.tmp"
rm -f "$TMP_VALID_MIRRORS_PATH"
touch "$TMP_VALID_MIRRORS_PATH"

# ========= URL 配置 =========
set_direct_mode() {
    CUSTOM_RELEASE_PROXY="https://github.com"
    CUSTOM_RAW_PROXY="https://raw.githubusercontent.com"
}

set_proxy_mode() {
    CUSTOM_RELEASE_PROXY="https://ghproxy.ch3ng.top/https://github.com"
    CUSTOM_RAW_PROXY="https://ghraw.ch3ng.top"
}

[ "$GITHUB_DIRECT" = "true" ] && set_direct_mode || set_proxy_mode


# ========= 日志 =========
log_info() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [PRETEST] [INFO] $1"
    [ $# -eq 2 ] || echo
}

log_warn() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [PRETEST] [WARN] $1"
    [ $# -eq 2 ] || echo
}

log_error() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [PRETEST] [ERROR] $1"
    [ $# -eq 2 ] || echo
}

# ========= 统一下载函数 =========
webget() {
    local dest="$1"
    local url="$2"
    if command -v curl >/dev/null 2>&1; then
        timeout $TIME_OUT curl -sSL --fail -A "Mozilla/5.0" -o "$dest" "$url"
        return $?
    elif command -v wget >/dev/null 2>&1; then
        timeout $TIME_OUT wget -q --no-check-certificate -O "$dest" "$url"
        return $?
    else
        log_error "❌  curl 和 wget 都不可用"
        return 1
    fi
}

# ========= 下载尝试逻辑（可重建 URL） =========
rebuild_url() {
    case "$1" in
        sha)     echo "${CUSTOM_RELEASE_PROXY}/${SHA256SUMS_URL_SUFFIX}" ;;
        proxies) echo "${CUSTOM_RAW_PROXY}/${PROXIES_LIST_URL_SUFFIX}" ;;
    esac
}

download_with_retry() {
    local dest="$1" type="$2" prefix="$3"
    local max_retry=3
    local attempt=1

    # 初次构建 URL（默认镜像）
    local url
    url="$(rebuild_url "$type")"

    while true; do
        attempt=1
        while [ $attempt -le $max_retry ]; do
            log_info "⏳  下载 $type 文件 [$attempt/$max_retry]：$url → $dest"

            if webget "$dest" "$url"; then
                return 0
            fi

            log_warn "❌  下载 $type 失败 [$attempt/$max_retry]"
            attempt=$((attempt + 1))
        done

        # ⛔ 走到这里说明同一个镜像 3 次都失败
        log_warn "⚠  当前镜像连续 $max_retry 次下载失败，需重新配置镜像"
        
        local suffix
        case "$type" in
            sha)     suffix="${SHA256SUMS_URL_SUFFIX}" ;;
            proxies) suffix="${PROXIES_LIST_URL_SUFFIX}" ;;
        esac

        if ! manual_fallback_with_reconfig "$prefix" "$suffix"; then
            log_error "❌  镜像配置异常"
            exit 1
        fi

        # 重新配置镜像后重新生成URL
        url="$(rebuild_url "$type")"

        # 如果用户选择“强制直连”，manual_fallback_with_reconfig 会处理
        if [ "$GLOBAL_DIRECT_MODE" = "1" ]; then
            log_info "🔁  已进入直连模式，重试下载"
        fi
    done
}

force_direct_mode() {
    set_direct_mode
    sed -i -e '/^GITHUB_DIRECT=/d' -e '$aGITHUB_DIRECT=true' "$INST_CONF" 2>/dev/null || true
    : > "$VALID_MIRRORS_PATH"
    log_info "✅  已切换到 GitHub 直连模式"
}

# ========= 手动选镜像 =========
manual_fallback_with_reconfig() {
    local prefix="$1" suffix="$2"
    log_info "镜像不可用，请选择："
    log_info "  1) 手动输入镜像"
    log_info "  2) 强制直连"
    log_info "  3) 退出安装"

    while :; do
        log_info "请选择 1~3: " 1
        read -r choice || choice=2

        case "$choice" in
            1)
                log_info "> 请输入您提供的镜像地址,"
                log_info "> 镜像地址需要与 $suffix 拼凑后能下载此文件,"
                log_info "> 且镜像地址以 https:// 开头, 以 / 结尾,"
                log_info "> 例如: $prefix: " 1
                read -r input
                [ -z "$input" ] && continue
                case "$input" in
                    http*://*)
                        mirror="${input%/}"
                        CUSTOM_RELEASE_PROXY="${mirror}"
                        CUSTOM_RAW_PROXY="${mirror}"
                        echo "$mirror" > "$VALID_MIRRORS_PATH"
                        log_info "✅  已切换至镜像：$mirror"
                        return 0 ;;
                esac
                log_warn "❌  无效地址"
                ;;
            2) force_direct_mode; return 0 ;;
            3) exit 10 ;;
            *) log_warn "⏳  请输入 1~3: " 1;;
        esac
    done
}

# ========= STEP 1：下载校验文件 =========
download_with_retry "$SUM_PATH" sha "https://ghproxy.example.com/https://github.com/"

sha_expected="$(grep -E " ${BIN_NAME}$" "$SUM_PATH" | awk '{print $1}')"
if [ -z "$sha_expected" ]; then
    log_error "❌  校验文件格式异常"
    force_direct_mode
    exit 1
fi

# ========= STEP 2：下载代理列表 =========
download_with_retry "$PROXIES_LIST_PATH" proxies "https://ghproxy.example.com/https://raw.githubusercontent.com/"
log_info "✅  代理列表下载成功"

# ========= STEP 3：测速挑最快镜像 =========
log_info "⏳  开始代理测速..."

total=$(grep -cve '^\s*$' "$PROXIES_LIST_PATH")
index=0

test_mirror() {
    mirror="${1%/}/"
    progress="$2"

    local url="${mirror}${BIN_URL_SUFFIX}"
    log_info "⏳  测试[$progress] $url"

    local start=$(date +%s.%N)
    if ! webget "$BIN_PATH" "$url"; then
        log_warn "❌  下载失败"
        return
    fi

    local sha_actual
    sha_actual=$(sha256sum "$BIN_PATH" | awk '{print $1}')

    if [ "$sha_expected" != "$sha_actual" ]; then
        log_warn "❌  SHA256 错误：$sha_actual"
        return
    fi

    local end=$(date +%s.%N)
    local cost=$(awk "BEGIN {printf \"%.2f\", $end - $start}")
    log_info "✅  通过，用时 ${cost}s"

    echo "$cost $mirror" >> "$TMP_VALID_MIRRORS_PATH"
}

while read -r mirror; do
    case "$mirror" in http*) ;; *) continue ;; esac
    index=$((index+1))
    test_mirror "$mirror" "$index/$total"

    valid_count=$(wc -l < "$TMP_VALID_MIRRORS_PATH")
    [ "$valid_count" -ge 3 ] && log_info "✅  已找到 3 个有效代理，提前结束测速" && break
done < "$PROXIES_LIST_PATH"

rm -f "$BIN_PATH"

# ========= STEP 4：保存最佳镜像 =========
if [ -s "$TMP_VALID_MIRRORS_PATH" ]; then
    sort -n "$TMP_VALID_MIRRORS_PATH" | awk '{print $2}' > "$VALID_MIRRORS_PATH"
    log_info "🏆  最佳镜像：$(head -n1 "$VALID_MIRRORS_PATH")"
else
    log_info "❌  未找到可用代理, 安装失败, 请考虑使用直连模式"
    exit 1
fi

rm -f "$TMP_VALID_MIRRORS_PATH"
exit 0