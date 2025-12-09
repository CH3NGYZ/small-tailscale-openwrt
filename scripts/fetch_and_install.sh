#!/bin/sh

set -e

[ -f /etc/tailscale/tools.sh ] && . /etc/tailscale/tools.sh && safe_source "$INST_CONF"

set_direct_mode() {
    CUSTOM_RELEASE_PROXY="https://github.com"
    CUSTOM_RAW_PROXY="https://github.com"
    CUSTOM_API_PROXY="https://api.github.com"
}

set_proxy_mode() {
    CUSTOM_RELEASE_PROXY="https://gh.ch3ng.top"
    CUSTOM_RAW_PROXY="https://gh.ch3ng.top"
    CUSTOM_API_PROXY="https://ghapi.ch3ng.top"
}

[ "$GITHUB_DIRECT" = "true" ] && set_direct_mode || set_proxy_mode

GITHUB_API_LATEST_RELEASE_URL_SUFFIX="repos/CH3NGYZ/small-tailscale-openwrt/releases/latest"

# 获取最新版本
get_latest_version() {
    local api_url="${CUSTOM_API_PROXY}/${GITHUB_API_LATEST_RELEASE_URL_SUFFIX}"
    local tmp_json_file="/tmp/github_latest_release.json"
    local json=""
    local version=""

    # 使用 webget 下载 JSON
    if ! webget "$tmp_json_file" "$api_url" "echooff"; then
        log_error "❌  错误：获取版本信息失败。"
        return 1
    fi

    # 读取 JSON 内容
    json=$(cat "$tmp_json_file")
    rm -f "$tmp_json_file"

    # 使用 jq 或 grep/sed 提取 tag_name
    if command -v jq >/dev/null 2>&1; then
        version=$(echo "$json" | jq -r '.tag_name // empty')
    else
        version=$(echo "$json" \
            | grep -o '"tag_name"[ ]*:[ ]*"[^"]*"' \
            | sed 's/.*"tag_name"[ ]*:[ ]*"\([^"]*\)".*/\1/' \
            | head -n1)
    fi

    if [[ -z "$version" ]]; then
        log_error "❌  错误：版本号为空"
        return 1
    fi

    echo "$version"
}

get_checksum() {
    local sums_file=$1
    local target_name=$2
    grep "$target_name" "$sums_file" | grep -v "${target_name}.build" | awk '{print $1}'
}

download_file() {
    local url=$1
    local output=$2
    local mirror_list=${3:-}
    local checksum=${4:-}

    if [ "$GITHUB_DIRECT" = "true" ] ; then
        log_info "📄  使用 GitHub 直连: https://github.com/$url"
        if webget "$output" "https://github.com/$url" "echooff"; then
            [ -n "$checksum" ] && verify_checksum "$output" "$checksum"
            return 0
        else
            return 1
        fi
    fi

    if [ -f "$mirror_list" ]; then
        while read -r mirror; do
            mirror=$(echo "$mirror" | sed 's|/*$|/|')
            log_info "🔗  使用代理镜像下载: ${mirror}${url}"
            if webget "$output" "${mirror}${url}" "echooff"; then
                if [ -n "$checksum" ]; then
                    if verify_checksum "$output" "$checksum"; then
                        return 0
                    else
                        log_warn "⚠️  校验失败，尝试下一个镜像..."
                    fi
                else
                    return 0
                fi
            fi
        done < "$mirror_list"
    fi

    log_info "🔗  镜像全部失败，尝试 GitHub 直连: https://github.com/$url"
    if webget "$output" "https://github.com/$url" "echooff"; then
        [ -n "$checksum" ] && verify_checksum "$output" "$checksum"
        return 0
    else
        return 1
    fi
}


verify_checksum() {
    local file=$1
    local expected=$2

    local actual=""

    if [ ${#expected} -eq 64 ]; then
        actual=$(sha256sum "$file" | awk '{print $1}')
        log_info "🔗  预期 SHA256: $expected"
        log_info "🔗  计算 SHA256: $actual"
    elif [ ${#expected} -eq 32 ]; then
        actual=$(md5sum "$file" | awk '{print $1}')
        log_info "🔗  预期 MD5: $expected"
        log_info "🔗  计算 MD5: $actual"
    else
        log_info "🔗  预期: $expected"
        log_warn "⚠️  未知校验长度，跳过校验"
        return 0
    fi

    if [ "$expected" = "$actual" ]; then
        log_info "✅  校验通过"
        return 0
    else
        log_error "❌  校验失败"
        return 1
    fi
}


# 主安装流程
install_tailscale() {
    local version=$1
    local mode=$2
    local mirror_list=$3

    local arch="$ARCH"
    local tailscale_temp_path="/tmp/tailscaled.$$"
    local release_arch_filename="tailscaled-linux-$arch"
    local release_version_suffix="CH3NGYZ/small-tailscale-openwrt/releases/download/$version"

    log_info "🔗  准备校验文件..."
    sha_file="/tmp/SHA256SUMS.$$"
    md5_file="/tmp/MD5SUMS.$$"

    # 下载校验文件
    download_file "${release_version_suffix}/SHA256SUMS.txt" "$sha_file" "$mirror_list" || log_warn "⚠️  无法获取 SHA256 校验文件"
    download_file "${release_version_suffix}/MD5SUMS.txt" "$md5_file" "$mirror_list" || log_warn "⚠️  无法获取 MD5 校验文件"

    sha256=""
    md5=""
    [ -s "$sha_file" ] && sha256=$(get_checksum "$sha_file" "$release_arch_filename")
    [ -s "$md5_file" ] && md5=$(get_checksum "$md5_file" "$release_arch_filename")

    # 下载主程序并校验
    log_info "🔗  正在下载 Tailscale $version ($arch)..."
    if ! download_file "$release_version_suffix/$release_arch_filename" "$tailscale_temp_path" "$mirror_list" "$sha256"; then
        log_warn "⚠️  SHA256 校验失败，尝试使用 MD5..."
        if ! download_file "$release_version_suffix/$release_arch_filename" "$tailscale_temp_path" "$mirror_list" "$md5"; then
            log_error "❌  校验失败，安装中止"
            rm -f "$tailscale_temp_path"
            exit 1
        fi
    fi

    # 安装
    chmod +x "$tailscale_temp_path"
    if [ "$mode" = "local" ]; then
        mkdir -p /usr/local/bin
        mv "$tailscale_temp_path" /usr/local/bin/tailscaled
        ln -sf /usr/local/bin/tailscaled /usr/bin/tailscaled
        ln -sf /usr/local/bin/tailscaled /usr/bin/tailscale
        log_info "✅  安装到 /usr/local/bin/"
    else
        mv "$tailscale_temp_path" /tmp/tailscaled
        ln -sf /tmp/tailscaled /usr/bin/tailscaled
        ln -sf /tmp/tailscaled /usr/bin/tailscale
        log_info "✅  安装到 /tmp (内存模式)"
    fi

    echo "$version" > "$VERSION_FILE"
}

# 参数解析
MODE="local"
VERSION="latest"
MIRROR_LIST=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --mode=*) MODE="${1#*=}"; shift ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --mirror-list=*) MIRROR_LIST="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

if [ "$VERSION" = "latest" ]; then
    set +e
    while true; do
        VERSION=$(get_latest_version)
        if [ $? -eq 0 ] && [ -n "$VERSION" ]; then
            break
        fi
        sleep 1
    done
    set -e
fi

# 干跑模式（只输出版本号）
if [ "$DRY_RUN" = "true" ]; then
    echo "$VERSION"
    exit 0
fi

# 执行安装
install_tailscale "$VERSION" "$MODE" "$MIRROR_LIST"
