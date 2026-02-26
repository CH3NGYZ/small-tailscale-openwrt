#!/bin/sh
# /etc/tailscale/tools.sh
CONFIG_DIR="/etc/tailscale"
mkdir -p "$CONFIG_DIR"
LOG_FILE="/var/log/tailscale_install.log"
VERSION_FILE="$CONFIG_DIR/current_version"
NTF_CONF="$CONFIG_DIR/notify.conf"
INST_CONF="$CONFIG_DIR/install.conf"
MIRROR_LIST="$CONFIG_DIR/proxies.txt"
VALID_MIRRORS="$CONFIG_DIR/valid_proxies.txt"
TMP_VALID_MIRRORS="/tmp/valid_mirrors.tmp"
REMOTE_SCRIPTS_VERSION_FILE="$CONFIG_DIR/remote_ts_scripts_version"
TIME_OUT=30

# GitHub 代理模式配置
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

# 根据配置自动设置模式
apply_github_mode() {
    [ "$GITHUB_DIRECT" = "true" ] && set_direct_mode || set_proxy_mode
}

# 初始化日志系统
log_info() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    [ $# -eq 2 ] || echo
}

log_warn() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    [ $# -eq 2 ] || echo
}

log_error() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    [ $# -eq 2 ] || echo
}

# 安全加载配置文件
safe_source() {
    local file="$1"
    if [ -f "$file" ] && [ -s "$file" ]; then
        . "$file"
    else
        log_warn "⚠️  配置文件 $file 不存在或为空"
    fi
}

webget() {
    # $1 输出文件
    # $2 URL
    # $3 是否静默: echooff
    # $4 禁止重定向: rediroff
    local outfile="$1"
    local url="$2"

    local ua="Tailscale-Helper"

    # 是否静默
    local quiet=""
    [ "$3" = "echooff" ] && quiet="-s"

    # 是否禁用重定向
    local redirect="-L"
    [ "$4" = "rediroff" ] && redirect=""

    # ----  优先使用 curl ----
    if command -v curl >/dev/null 2>&1; then
        http_code=$(timeout "$TIME_OUT" curl $quiet $redirect \
            -A "$ua" \
            -w "%{http_code}" \
            -o "$outfile" \
            "$url" 2>/dev/null)

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    # ----  回退到 wget ----
    if command -v wget >/dev/null 2>&1; then
        local q="--show-progress"
        [ "$3" = "echooff" ] && q="-q"

        local r=""
        [ "$4" = "rediroff" ] && r="--max-redirect=0"

        # wget 不直接返回 HTTP 状态码，需要解析 headers
        headers=$(mktemp)
        timeout "$TIME_OUT" wget $q $r \
            --server-response --no-check-certificate \
            --header="User-Agent: $ua" \
            -O "$outfile" "$url" 2>"$headers"

        # 提取最后的 HTTP 状态码
        http_code=$(grep -oE 'HTTP/[0-9\.]+ [0-9]+' "$headers" | tail -n1 | awk '{print $2}')
        rm -f "$headers"

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    log_error "❌ curl 和 wget 都不存在"
    return 1
}

# 校验函数, 自动根据长度判断类型, 支持 openssl 回退
verify_checksum() {
    local file=$1
    local expected=$2
    local actual=""

    if [ ${#expected} -eq 64 ]; then
        if command -v sha256sum >/dev/null 2>&1; then
            actual=$(sha256sum "$file" | awk '{print $1}')
        elif command -v openssl >/dev/null 2>&1; then
            actual=$(openssl dgst -sha256 "$file" | awk '{print $2}')
        else
            log_warn "⚠️  缺少 sha256sum 或 openssl，跳过校验"
            return 0
        fi
    elif [ ${#expected} -eq 32 ]; then
        if command -v md5sum >/dev/null 2>&1; then
            actual=$(md5sum "$file" | awk '{print $1}')
        elif command -v openssl >/dev/null 2>&1; then
            actual=$(openssl dgst -md5 "$file" | awk '{print $2}')
        else
            log_warn "⚠️  缺少 md5sum 或 openssl，跳过校验"
            return 0
        fi
    else
        log_warn "⚠️  未知校验长度 (${#expected})，跳过校验"
        return 0
    fi

    if [ "$expected" = "$actual" ]; then
        log_info "✅  校验通过"
        return 0
    else
        log_error "❌  校验失败！预期: $expected, 实际: $actual"
        return 1
    fi
}

# URL 编码函数 (纯 shell 内建操作, 无外部命令依赖)
urlencode() {
    local str="$1" c rest
    rest="$str"
    while [ -n "$rest" ]; do
        c="${rest%"${rest#?}"}"
        rest="${rest#?}"
        case "$c" in
            [A-Za-z0-9._~-]) printf '%s' "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}


send_notify() {
    local host_name="$(uci get system.@system[0].hostname 2>/dev/null || echo OpenWrt)"
    local title="$host_name Tailscale通知"
    local user_title="$1"
    shift
    local body_content="$(printf "%s\n" "$@")"
    local content="$(printf "%s\n%s" "$user_title" "$body_content")"

    safe_source "$NTF_CONF"  # 引入配置文件

    # 通用发送函数（curl 优先，wget 兼容）
    # 用法: send_via_curl_or_wget URL [DATA] [METHOD] [HEADER]
    # METHOD: GET / POST(默认当有DATA时)
    send_via_curl_or_wget() {
        local url="$1"
        local data="$2"
        local method="$3"
        local headers="$4"

        if command -v curl > /dev/null; then
            if [ "$method" = "GET" ] || [ -z "$data" ]; then
                curl -sS -A "Tailscale-Helper" "$url"
            else
                curl -sS -A "Tailscale-Helper" -X POST "$url" -d "$data" -H "$headers"
            fi
        elif command -v wget > /dev/null; then
            if [ "$method" = "GET" ] || [ -z "$data" ]; then
                wget --quiet --header="User-Agent: Tailscale-Helper" -O /dev/null "$url"
            else
                echo "$data" | wget --quiet --header="User-Agent: Tailscale-Helper" --method=POST --body-file=- --header="$headers" "$url"
            fi
        else
            log_error "❌  curl 和 wget 都不可用，无法发送通知"
            return 1
        fi
    }

    # Server酱
    if [ "$NOTIFY_SERVERCHAN" = "1" ] && [ -n "$SERVERCHAN_KEY" ]; then
        data="text=$title&desp=$content"
        send_via_curl_or_wget "https://sctapi.ftqq.com/$SERVERCHAN_KEY.send" "$data" "POST" && log_info "✅  Server酱 通知已发送"
    fi

    # Bark
    if [ "$NOTIFY_BARK" = "1" ] && [ -n "$BARK_KEY" ]; then
        title_enc=$(urlencode "$title")
        content_enc=$(urlencode "$content")
        bark_url="${BARK_KEY}/${title_enc}/${content_enc}"
        send_via_curl_or_wget "$bark_url" "" "GET" && log_info "✅  Bark 通知已发送"
    fi

    # ntfy
    if [ "$NOTIFY_NTFY" = "1" ] && [ -n "$NTFY_KEY" ]; then
        headers="Title: $title"
        send_via_curl_or_wget "https://ntfy.sh/$NTFY_KEY" "$content" "POST" "$headers" && log_info "✅  NTFY 通知已发送"
    fi

    # PushPlus
    if [ "$NOTIFY_PUSHPLUS" = "1" ] && [ -n "$PUSHPLUS_TOKEN" ]; then
        pushplus_data="{\"token\":\"$PUSHPLUS_TOKEN\",\"title\":\"$title\",\"content\":\"$content\",\"template\":\"txt\"}"
        send_via_curl_or_wget "http://www.pushplus.plus/send" "$pushplus_data" "POST" "Content-Type: application/json" && log_info "✅  PushPlus 通知已发送"
    fi

    # 无任何通知方式启用
    if [ "$NOTIFY_SERVERCHAN" != "1" ] && [ "$NOTIFY_BARK" != "1" ] && [ "$NOTIFY_NTFY" != "1" ] && [ "$NOTIFY_PUSHPLUS" != "1" ]; then
        log_error "❌  未启用任何通知方式"
    fi
}

# 检查是否需要发送通知
should_notify() {
    local notify_type=$1
    safe_source "$NTF_CONF"
    local notify_var
    case "$notify_type" in
        "update") notify_var="$NOTIFY_UPDATE" ;;
        "mirror_fail") notify_var="$NOTIFY_MIRROR_FAIL" ;;
        "emergency") notify_var="$NOTIFY_EMERGENCY" ;;
        *)
            log_error "❌  未知通知类型: $notify_type"
            return 1
            ;;
    esac
    [ "$notify_var" = "1" ]
}