#!/bin/sh

set -e
set -o pipefail 2>/dev/null || true

# 仅在交互终端清屏，避免无 TERM 时出错
[ -t 1 ] && clear 2>/dev/null || true

TIME_OUT=20
CONFIG_DIR="/etc/tailscale"
mkdir -p "$CONFIG_DIR"
INST_CONF="$CONFIG_DIR/install.conf"

# -------------------- GitHub 直连/代理模式 --------------------
if [ -f /tmp/tailscale-use-direct ]; then
    rm -f /tmp/tailscale-use-direct
    GITHUB_DIRECT=true
    CUSTOM_RAW_PROXY="https://github.com"
else
    GITHUB_DIRECT=false
    CUSTOM_RAW_PROXY="https://gh.ch3ng.top"
fi

# 写入最小配置，供后续脚本使用
printf 'GITHUB_DIRECT=%s\n' "$GITHUB_DIRECT" > "$INST_CONF"

SCRIPTS_TGZ_PATH="/tmp/tailscale-openwrt-scripts.tar.gz"
SCRIPTS_TGZ_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/tailscale-openwrt-scripts.tar.gz"
PRETEST_MIRRORS_SH_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/pretest_mirrors.sh"

# 预先计算的校验和（由 GitHub Actions 自动回填）
EXPECTED_CHECKSUM_SHA256="a0960cbe05df6188f3c89e2ccf4b77c93e0baa9d9da4d4398a01cc267ede1ee7"
EXPECTED_CHECKSUM_MD5="aaaf3f96927e34356dfd5f10e60e7718"

# -------------------- 日志 --------------------
log_info() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [INFO] $1"
    [ $# -eq 2 ] || echo
}

log_warn() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [WARN] $1"
    [ $# -eq 2 ] || echo
}

log_error() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')] [INSTALL] [ERROR] $1"
    [ $# -eq 2 ] || echo
}

is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

# -------------------- 包管理器适配(opkg/apk) --------------------
PKG_MGR=""
if command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
else
    log_error "❌  未检测到 opkg 或 apk 命令，当前系统可能不是 OpenWrt 或缺少包管理器"
    log_error "❌  无法继续执行安装脚本"
    exit 1
fi

pkg_list_installed() {
    case "$PKG_MGR" in
        opkg) opkg list-installed ;;
        apk) apk info -e ;;
    esac
}

pkg_is_installed() {
    # $1: pkg name
    local pkg="$1"
    case "$PKG_MGR" in
        opkg) echo "$INSTALLED_PKGS" | grep -q "^${pkg} -" ;;
        apk) echo "$INSTALLED_PKGS" | grep -qx "$pkg" ;;
    esac
}

pkg_update() {
    case "$PKG_MGR" in
        opkg) opkg update ;;
        apk) apk update ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        opkg) opkg install "$1" ;;
        apk) apk add "$1" ;;
    esac
}

# -------------------- 时间同步（尽量在 HTTPS 前校时） --------------------
sync_time() {
    log_info "正在同步系统时间..."

    # 尝试 NTP
    for server in ntp.aliyun.com time1.cloud.tencent.com pool.ntp.org; do
        if command -v ntpdate >/dev/null 2>&1; then
            if ntpdate -u "$server" >/dev/null 2>&1; then
                log_info "时间同步成功（$server）"
                return 0
            fi
        fi
        if command -v ntpd >/dev/null 2>&1; then
            if ntpd -q -n -p "$server" >/dev/null 2>&1; then
                log_info "时间同步成功（$server）"
                return 0
            fi
        fi
    done

    # HTTP 头时间（依赖 curl/wget 任一可用即可）
    log_warn "所有 NTP 服务器都失败或未安装 ntpdate/ntpd，尝试使用 HTTP 头时间"

    http_date_line=""
    if command -v curl >/dev/null 2>&1; then
        http_date_line=$(curl -fsSI -A "Tailscale-Helper" --connect-timeout 5 https://www.baidu.com 2>/dev/null | grep -i '^date:' | head -n1 || true)
    elif command -v wget >/dev/null 2>&1; then
        # wget 会把响应头写到 stderr
        http_date_line=$(wget -S --spider --timeout=5 --user-agent="Tailscale-Helper" https://www.baidu.com 2>&1 | grep -i '^  Date:' | head -n1 | sed 's/^  //')
        http_date_line=$(echo "$http_date_line" | sed 's/^Date:/date:/I')
    fi

    [ -z "$http_date_line" ] && log_warn "无法获取 HTTP 头时间（可能缺少 curl/wget 或网络受限）" && return 1

    http_time=$(echo "$http_date_line" | awk '{
        # 解析 RFC1123: date: Fri, 13 Mar 2026 03:11:54 GMT
        split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", months, " ");
        for (i=1; i<=12; i++) m[months[i]] = i;
        # 去掉逗号
        gsub(/,/, "", $3);
        # $4=13  $5=Mar $6=2026 $7=03:11:54
        if ($4 ~ /^[0-9]+$/) {
            printf "%04d-%02d-%02d %s", $6, m[$5], $4, $7
        } else {
            # 兼容部分实现差异
            printf "%04d-%02d-%02d %s", $5, m[$4], $3, $6
        }
    }')

    if [ -n "$http_time" ] && date -u -s "$http_time" >/dev/null 2>&1; then
        log_info "已用 HTTP 头设置时间"
        return 0
    fi

    log_warn "HTTP 头时间解析/设置失败"
    return 1
}

# 尝试一次：尽早校时，避免 TLS 证书时间错误
sync_time || true

# -------------------- 依赖检查与安装 --------------------
# 先缓存已安装包列表（避免循环中多次调用包管理器）
INSTALLED_PKGS=$(pkg_list_installed 2>/dev/null || true)

# jq 可选：脚本内置 grep/sed 回退
JQ_REQUIRED=0
JQ_AVAILABLE=1

# 依赖包列表（按包管理器区分）
REQUIRED_PACKAGES=""
OPTIONAL_PACKAGES=""

case "$PKG_MGR" in
    opkg)
        # 如果已安装 libustream-mbedtls，则跳过 libustream-openssl
        if echo "$INSTALLED_PKGS" | grep -q "^libustream-mbedtls -"; then
            SKIP_OPENSSL=1
        else
            SKIP_OPENSSL=0
        fi

        REQUIRED_PACKAGES="ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl"
        [ "$SKIP_OPENSSL" -eq 0 ] && REQUIRED_PACKAGES="libustream-openssl $REQUIRED_PACKAGES"
        OPTIONAL_PACKAGES="jq"
        ;;
    apk)
        # Alpine 环境仅尽可能保证基础命令存在（此项目主要面向 OpenWrt/opkg）
        REQUIRED_PACKAGES="ca-certificates curl coreutils"
        OPTIONAL_PACKAGES="jq"
        ;;
    *)
        log_error "❌  不支持的包管理器: $PKG_MGR"
        exit 1
        ;;
esac

need_install=0
for package in $REQUIRED_PACKAGES $OPTIONAL_PACKAGES; do
    if ! pkg_is_installed "$package"; then
        log_warn "⚠️  包 $package 未安装"
        need_install=1
    fi
done

if [ "$need_install" -eq 1 ]; then
    log_info "🔄  正在更新 $PKG_MGR 源..."
    if ! pkg_update 2>&1; then
        log_warn "⚠️  $PKG_MGR update 失败（可能网络/源异常），继续尝试安装..."
    else
        log_info "✅  $PKG_MGR update 成功"
    fi

    for package in $REQUIRED_PACKAGES $OPTIONAL_PACKAGES; do
        if pkg_is_installed "$package"; then
            continue
        fi

        log_warn "⚠️  包 $package 未安装，开始安装..."
        if pkg_install "$package" 2>&1; then
            log_info "✅  包 $package 安装成功"
        else
            # 针对 jq：允许失败
            if [ "$package" = "jq" ] && [ "$JQ_REQUIRED" -eq 0 ]; then
                JQ_AVAILABLE=0
                log_warn "⚠️  安装 jq 失败，将使用回退解析方式，继续执行"
                continue
            fi

            # coreutils-timeout / coreutils-nohup 失败：尝试 coreutils
            if [ "$PKG_MGR" = "opkg" ] && { [ "$package" = "coreutils-timeout" ] || [ "$package" = "coreutils-nohup" ]; }; then
                alt="coreutils"
                log_warn "⚠️  安装 $package 失败，尝试安装 $alt 替代..."
                if pkg_install "$alt" 2>&1; then
                    log_info "✅  $alt 安装成功"
                    continue
                fi
            fi

            log_error "❌  安装 $package 失败，无法继续，请手动安装后重试"
            exit 1
        fi
    done

    # 重新刷新已安装列表
    INSTALLED_PKGS=$(pkg_list_installed 2>/dev/null || true)
else
    log_info "✅  已安装所有必要组件"
fi

# 安装完依赖后再尝试校时（提高 curl/wget 可用概率）
sync_time || true

# 最终检查关键命令
for cmd in timeout nohup tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "❌  未检测到 $cmd 命令，请安装后重新执行脚本"
        exit 1
    fi
done

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    log_error "❌  curl 和 wget 都不可用，无法继续"
    exit 1
fi

# -------------------- 下载工具（与 tools.sh 保持一致的返回语义：仅 2xx 成功） --------------------
webget() {
    # $1 输出文件
    # $2 URL
    # $3 是否静默: echooff
    # $4 禁止重定向: rediroff
    local outfile="$1"
    local url="$2"

    local ua="Tailscale-Helper"

    local quiet=""
    [ "$3" = "echooff" ] && quiet="-s"

    local redirect="-L"
    [ "$4" = "rediroff" ] && redirect=""

    if command -v curl >/dev/null 2>&1; then
        http_code=$(timeout "$TIME_OUT" curl $quiet $redirect \
            -A "$ua" \
            -w "%{http_code}" \
            -o "$outfile" \
            "$url" 2>/dev/null || true)

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    if command -v wget >/dev/null 2>&1; then
        local q="--show-progress"
        [ "$3" = "echooff" ] && q="-q"

        local r=""
        [ "$4" = "rediroff" ] && r="--max-redirect=0"

        headers=$(mktemp)
        timeout "$TIME_OUT" wget $q $r \
            --server-response --no-check-certificate \
            --header="User-Agent: $ua" \
            -O "$outfile" "$url" 2>"$headers" || true

        http_code=$(grep -oE 'HTTP/[0-9\.]+ [0-9]+' "$headers" | tail -n1 | awk '{print $2}')
        rm -f "$headers"

        case "$http_code" in 2*) return 0 ;; *) return 1 ;; esac
    fi

    log_error "❌ curl 和 wget 都不存在"
    return 1
}

verify_checksum() {
    # $1 file  $2 type(sha256/md5)  $3 expected
    local file="$1"
    local type="$2"
    local expected="$3"
    local actual=""

    case "$type" in
        sha256)
            if command -v sha256sum >/dev/null 2>&1; then
                actual=$(sha256sum "$file" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                actual=$(openssl dgst -sha256 "$file" | awk '{print $2}')
            else
                log_error "❌  系统缺少 sha256sum 或 openssl, 无法校验文件"
                return 1
            fi
            ;;
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                actual=$(md5sum "$file" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                actual=$(openssl dgst -md5 "$file" | awk '{print $2}')
            else
                log_error "❌  系统缺少 md5sum 或 openssl, 无法校验文件"
                return 1
            fi
            ;;
        *)
            log_error "❌  校验类型无效: $type"
            return 1
            ;;
    esac

    if [ "$actual" != "$expected" ]; then
        log_error "❌  校验失败！预期: $expected, 实际: $actual"
        return 1
    fi

    return 0
}

# -------------------- 下载脚本包并校验 --------------------
scripts_tgz_url="${CUSTOM_RAW_PROXY}/${SCRIPTS_TGZ_URL_SUFFIX}"

if webget "$SCRIPTS_TGZ_PATH" "$scripts_tgz_url" "echooff"; then
    log_info "📥  下载成功: $scripts_tgz_url"
else
    log_error "❌  下载失败: $scripts_tgz_url"
    exit 1
fi

sha_ok=0
md5_ok=0

if verify_checksum "$SCRIPTS_TGZ_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256"; then
    log_info "🔐  SHA256 校验通过"
    sha_ok=1
else
    log_warn "⚠️  SHA256 校验失败 (忽略, 尝试 MD5)"
fi

if verify_checksum "$SCRIPTS_TGZ_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"; then
    log_info "🔐  MD5 校验通过"
    md5_ok=1
else
    log_warn "⚠️  MD5 校验失败"
fi

if [ "$sha_ok" -eq 0 ] && [ "$md5_ok" -eq 0 ]; then
    log_error "❌  校验失败，安装中止"
    exit 1
fi

log_info "✅  下载脚本包 + 校验成功!"

# -------------------- 解压脚本包 --------------------
log_info "📦  解压脚本包..."
tar -xzf "$SCRIPTS_TGZ_PATH" -C "$CONFIG_DIR"

# 设置权限（避免通配符未匹配导致失败）
find "$CONFIG_DIR" -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} \;

# 创建 helper 的软连接
ln -sf "$CONFIG_DIR/helper.sh" /usr/bin/tailscale-helper
if [ -L /usr/bin/tailscale-helper ]; then
    log_info "✅  软连接已成功创建：$CONFIG_DIR/helper.sh -> /usr/bin/tailscale-helper"
else
    log_warn "⚠️  创建软连接失败（可能 /usr/bin 不存在或只读）"
fi

# 初始化通知配置（若不存在则创建）
[ -f "$CONFIG_DIR/notify.conf" ] || cat > "$CONFIG_DIR/notify.conf" <<'EOF'
# 通知开关 (1=启用 0=禁用)
NOTIFY_UPDATE=1
NOTIFY_MIRROR_FAIL=1
NOTIFY_EMERGENCY=1

NOTIFY_SERVERCHAN=0
SERVERCHAN_KEY=""
NOTIFY_BARK=0
BARK_KEY=""
NOTIFY_NTFY=0
NTFY_KEY=""
NOTIFY_PUSHPLUS=0
PUSHPLUS_TOKEN=""
EOF

run_pretest_mirrors() {
    pretest_mirrors_sh_url="${CUSTOM_RAW_PROXY}/${PRETEST_MIRRORS_SH_URL_SUFFIX}"
    log_info "🔄  下载 $pretest_mirrors_sh_url 并执行测速..."

    if webget "/tmp/pretest_mirrors.sh" "$pretest_mirrors_sh_url" "echooff"; then
        sh /tmp/pretest_mirrors.sh
    else
        log_error "❌  下载 pretest_mirrors.sh 失败, 请重试!"
        return 1
    fi
}

if [ "$GITHUB_DIRECT" = "true" ]; then
    log_info "✅  使用 GitHub 直连, 跳过测速！"
else
    # proxies.txt 不存在或为空时才重新下载/测速
    if [ ! -s "$CONFIG_DIR/proxies.txt" ]; then
        log_info "🔍  本地不存在 proxies.txt(或为空), 将下载镜像列表并测速, 请等待..."
        run_pretest_mirrors
        ret=$?
        if [ "$ret" -eq 0 ]; then
            log_info "✅  下载镜像列表并测速完成！"
        elif [ "$ret" -eq 10 ]; then
            log_info "👋  用户取消安装"
            exit 0
        else
            log_error "❌  下载或测速失败, 无法继续!"
            exit 1
        fi
    else
        log_info "✅  本地存在 proxies.txt, 无需再次下载!"
    fi
fi

log_info "✅  配置工具安装完毕!"
log_info "✅  运行 tailscale-helper 可以打开功能菜单"

# 非交互模式：直接退出，避免 read 阻塞
if ! is_interactive; then
    exit 0
fi

log_info "👋  回车直接执行, 输入其他字符退出: " 1
read -r choice
if [ -z "$choice" ]; then
    tailscale-helper
else
    log_info "👋  退出脚本....."
    sleep 1
    clear 2>/dev/null || true
    exit 0
fi
