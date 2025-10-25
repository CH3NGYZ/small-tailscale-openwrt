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


# 通用下载函数 (兼容curl/wget)
webget() {
    # 参数说明：
    # $1 下载路径
    # $2 下载URL
    # $3 输出控制 (echooff/echoon)
    # $4 重定向控制 (rediroff)
    local result=""

    if command -v curl >/dev/null 2>&1; then
        [ "$3" = "echooff" ] && local progress='-s' || local progress='-#'
        [ -z "$4" ] && local redirect='-L' || local redirect=''
        # 修正 curl 的参数：-o 用于指定输出文件
        result=$(timeout $TIME_OUT curl -w "%{http_code}" -H "User-Agent: Mozilla/5.0 (curl-compatible)" $progress $redirect -o "$1" "$2")
        # 判断返回的 HTTP 状态码是否为 2xx
        if [[ "$result" =~ ^2 ]]; then
            result="200"
        else
            result="non-200"
        fi
    else
        if command -v wget >/dev/null 2>&1; then
            [ "$3" = "echooff" ] && local progress='-q' || local progress='--show-progress'
            [ "$4" = "rediroff" ] && local redirect='--max-redirect=0' || local redirect=''
            local certificate='--no-check-certificate'
            timeout $TIME_OUT wget --header="User-Agent: Mozilla/5.0" $progress $redirect $certificate -O "$1" "$2"
            if [ $? -eq 0 ]; then
                result="200"
            else
                result="non-200"
            fi
        else
            log_error "Error: Neither curl nor wget available"
            return 1
        fi
    fi

    [ "$result" = "200" ] && return 0 || return 1
}


send_notify() {
    local host_name="$(uci get system.@system[0].hostname 2>/dev/null || echo OpenWrt)"
    local title="$host_name Tailscale通知"
    local user_title="$1"
    shift
    local body_content="$(printf "%s\n" "$@")"
    local content="$(printf "%s\n%s" "$user_title" "$body_content")"

    . "$NTF_CONF"  # 引入配置文件

    # 通用发送函数（curl 优先，wget 兼容）
    send_via_curl_or_wget() {
        local url="$1"
        local data="$2"
        local method="$3"
        local headers="$4"

        if command -v curl > /dev/null; then
            if [ "$method" = "POST" ]; then
                curl -sS -X POST "$url" -d "$data" -H "$headers"
            else
                curl -sS "$url" -d "$data" -H "$headers"
            fi
        elif command -v wget > /dev/null; then
            if [ "$method" = "POST" ]; then
                echo "$data" | wget --quiet --method=POST --body-file=- --header="$headers" "$url"
            else
                wget --quiet --post-data="$data" --header="$headers" "$url"
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

    # URL 编码函数
    urlencode() {
        local str="$1"
        local length="${#str}"
        i=0
        while [ "$i" -lt "$length" ]; do
            local c="${str:i:1}"
            case "$c" in
                [a-zA-Z0-9._-]) 
                    printf "$c"
                    ;;
                *)
                    printf "%%%02X" "'$c"
                    ;;
            esac
            i=$((i + 1))
        done
    }

    # Bark
    if [[ "$NOTIFY_BARK" == "1" && -n "$BARK_KEY" ]]; then
        title_enc=$(urlencode "$title")
        content_enc=$(urlencode "$content")
        
        url="${BARK_KEY}/${title_enc}/${content_enc}"
        
        if command -v curl > /dev/null; then
            response=$(curl -sS "$url")
            if [[ $? -eq 0 ]]; then
                log_info "✅  Bark 通知已发送"
            else
                log_error "❌  发送 Bark 通知失败，HTTP 状态码: $response"
            fi
        elif command -v wget > /dev/null; then
            if wget --quiet --output-document=/dev/null "$url"; then
                log_info "✅  Bark 通知已发送"
            else
                log_error "❌  发送 Bark 通知失败，wget 返回错误"
            fi
        else
            log_error "❌  curl 和 wget 都不可用，无法发送 Bark 通知"
        fi
    fi

    # ntfy
    if [ "$NOTIFY_NTFY" = "1" ] && [ -n "$NTFY_KEY" ]; then
        headers="Title: $title"
        send_via_curl_or_wget "https://ntfy.sh/$NTFY_KEY" "$content" "POST" "$headers" && log_info "✅  NTFY 通知已发送"
    fi

    # 无任何通知方式启用
    if [ "$NOTIFY_SERVERCHAN" != "1" ] && [ "$NOTIFY_BARK" != "1" ] && [ "$NOTIFY_NTFY" != "1" ]; then
        log_error "❌  未启用任何通知方式"
    fi
}