#!/bin/sh

set -e
clear

TIME_OUT=20
CONFIG_DIR="/etc/tailscale"
mkdir -p "$CONFIG_DIR"
INST_CONF="$CONFIG_DIR/install.conf"

if [ -f /tmp/tailscale-use-direct ]; then
    rm -f /tmp/tailscale-use-direct
    echo "GITHUB_DIRECT=true" > "$INST_CONF"
    GITHUB_DIRECT=true
    CUSTOM_RAW_PROXY="https://github.com"
else
    echo "GITHUB_DIRECT=false" > "$INST_CONF"
    GITHUB_DIRECT=false
    CUSTOM_RAW_PROXY="https://gh.ch3ng.top"
fi

SCRIPTS_TGZ_PATH="/tmp/tailscale-openwrt-scripts.tar.gz"
SCRIPTS_TGZ_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/tailscale-openwrt-scripts.tar.gz"
PRETEST_MIRRORS_SH_URL_SUFFIX="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/pretest_mirrors.sh"

# 预先计算的校验和
EXPECTED_CHECKSUM_SHA256="37ae1127e425beb9350508373931757effaa51717eebb9a900169ce289a3ff86"
EXPECTED_CHECKSUM_MD5="7ad83e165744523668ce051b0833293c"

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

if ! command -v opkg >/dev/null 2>&1; then
    log_error "❌  未检测到 opkg 命令，当前系统可能不是 OpenWRT 或缺少包管理器"
    log_error "❌  无法继续执行安装脚本"
    exit 1
fi

sync_time() {
    log_info "正在同步系统时间..."
    # 尝试多个常见 NTP 服务器，直到成功
    for server in ntp.aliyun.com time1.cloud.tencent.com pool.ntp.org; do
        if ntpdate -u "$server" >/dev/null 2>&1 || ntpd -q -n -p "$server" >/dev/null 2>&1; then
            log_info "时间同步成功（$server）"
            return 0
        fi
    done
    log_warn "所有 NTP 服务器都失败，尝试使用 HTTP 头时间"
    http_time=$(curl -I -s --connect-timeout 5 https://www.baidu.com | grep -i '^date:' | awk '{print $3,$4,$5,$6,$7}')
    [ -n "$http_time" ] && date -D "%d %b %Y %H:%M:%S %Z" -s "$http_time" && log_info "已用 HTTP 头设置时间"
}
sync_time

# 检查是否已经安装所有必要软件包
required_packages="libustream-openssl ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl jq"
need_install=0

# 一次性获取已安装包列表（性能优化）
installed_packages=$(opkg list-installed)

# 如果已安装 libustream-mbedtls，则跳过 libustream-openssl
skip_openssl=0
if echo "$installed_packages" | grep -q "^libustream-mbedtls"; then
    skip_openssl=1
fi

for package in $required_packages; do
    # 跳过 openssl 版本，仅标记，不输出日志
    if [ "$skip_openssl" -eq 1 ] && [ "$package" = "libustream-openssl" ]; then
        continue
    fi

    if ! echo "$installed_packages" | grep -q "^$package"; then
        log_warn "⚠️  包 $package 未安装"
        need_install=1
    fi
done

if [ "$need_install" -eq 0 ]; then
    log_info "✅  已安装所有必要组件"
else
    log_info "🔄  正在更新 opkg 源..."
    if ! opkg update 2>&1; then
        log_error "⚠️  opkg update 失败，请检查网络连接或源配置，继续执行..."
    else
        log_info "✅  opkg update 成功"
    fi

    for package in $required_packages; do
        # 在安装流程中才输出跳过提示
        if [ "$skip_openssl" -eq 1 ] && [ "$package" = "libustream-openssl" ]; then
            log_info "✅  检测到 libustream-mbedtls，跳过 libustream-openssl"
            continue
        fi

        if ! echo "$installed_packages" | grep -q "^$package"; then
            log_warn "⚠️  包 $package 未安装，开始安装..."
            if opkg install "$package" 2>&1; then
                log_info "✅  包 $package 安装成功"
            else
                # ★ 针对 jq 的特殊跳过逻辑 ★
                if [ "$package" = "jq" ]; then
                    log_warn "⚠️  安装 jq 失败，将使用回退解析方式，继续执行"
                    continue
                fi

                # 针对 coreutils 的替代逻辑
                if [ "$package" = "coreutils-timeout" ] || [ "$package" = "coreutils-nohup" ]; then
                    alt="coreutils"
                    log_warn "⚠️  安装 $package 失败，尝试安装 $alt 替代..."
                    if opkg install $alt 2>&1; then
                        log_info "✅  $alt 安装成功，可能已包含 $(echo $package | cut -d- -f2) 命令"
                        continue
                    fi
                fi

                log_error "❌  安装 $package 失败，无法继续，请手动安装此包"
                exit 1
            fi
        fi
    done

    # 最终检查命令可用性
    for cmd in timeout nohup curl jq; do
        if ! command -v $cmd >/dev/null 2>&1; then
            log_error "❌  未检测到 $cmd 命令，请手动安装后重新执行脚本"
            exit 1
        else
            log_info "✅  $cmd 命令已可用"
        fi
    done
fi

# 校验函数, 接收三个参数：文件路径、校验类型（sha256/md5）、预期值
verify_checksum() {
    local file=$1
    local type=$2
    local expected=$3
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

    # 校验结果对比
    if [ "$actual" != "$expected" ]; then
        log_error "❌  校验失败！预期: $expected, 实际: $actual"
        return 1
    fi

    return 0
}

webget() {
    # $1 输出文件
    # $2 URL
    # $3 是否静默: echooff/echoon
    # $4 是否禁止重定向: rediroff

    local outfile="$1"
    local url="$2"

    # 控制输出
    local quiet=""
    [ "$3" = "echooff" ] && quiet="-s" || quiet=""

    # 控制重定向
    local redirect="-L"
    [ "$4" = "rediroff" ] && redirect=""

    if command -v curl >/dev/null 2>&1; then
        timeout "$TIME_OUT" curl $quiet $redirect -o "$outfile" -H "User-Agent: Mozilla" "$url"
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        local q="--show-progress"
        [ "$3" = "echooff" ] && q="-q"

        local r=""
        [ "$4" = "rediroff" ] && r="--max-redirect=0"

        timeout "$TIME_OUT" wget $q $r --no-check-certificate -O "$outfile" "$url"
        return $?
    fi

    log_error "❌ curl 和 wget 都不存在"
    return 1
}

scripts_tgz_url="${CUSTOM_RAW_PROXY}/${SCRIPTS_TGZ_URL_SUFFIX}"

if webget "$SCRIPTS_TGZ_PATH" "$scripts_tgz_url" "echooff"; then
    log_info "📥  下载成功: $scripts_tgz_url"
else
    log_error "❌  下载失败"
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

if [ $sha_ok -eq 1 ] || [ $md5_ok -eq 1 ]; then
    log_info "✅  下载脚本包 + 校验成功!"
else
    log_error "❌  校验失败，安装中止"
    exit 1
fi

# 解压脚本
log_info "📦  解压脚本包..."
tar -xzf "$SCRIPTS_TGZ_PATH" -C "$CONFIG_DIR"

# 设置权限
chmod +x "$CONFIG_DIR"/*.sh

# 创建helper的软连接
ln -sf "$CONFIG_DIR/helper.sh" /usr/bin/tailscale-helper

# 检查软链接是否创建成功
if [ -L /usr/bin/tailscale-helper ]; then
    log_info "✅  软连接已成功创建：$CONFIG_DIR/helper.sh -> /usr/bin/tailscale-helper"
else
    log_error "❌  创建软连接失败"
fi

# 初始化通知配置
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
EOF


run_pretest_mirrors() {
    pretest_mirrors_sh_url="${CUSTOM_RAW_PROXY}/${PRETEST_MIRRORS_SH_URL_SUFFIX}"
    log_info "🔄  下载 $pretest_mirrors_sh_url 并执行测速..."
    if webget "/tmp/pretest_mirrors.sh" "$pretest_mirrors_sh_url" "echooff"; then
        sh /tmp/pretest_mirrors.sh
    else
        log_info "❌  下载 pretest_mirrors.sh 失败, 请重试!"
        return 1
    fi
}

if [ "$GITHUB_DIRECT" = "true" ] ; then
    log_info "✅  使用Github直连, 跳过测速！"
else
    if [ ! -f /etc/tailscale/proxies.txt ]; then
        log_info "🔍  本地不存在 proxies.txt, 将下载镜像列表并测速, 请等待..."
        run_pretest_mirrors
        ret=$?
        if [ $ret -eq 0 ]; then
            log_info "✅  下载镜像列表并测速完成！"
        elif [ $ret -eq 10 ]; then
            log_info "👋  用户取消安装"
            exit 0
        elif [ $ret -eq 1 ]; then
            log_info "❌  下载或测速失败, 无法继续!"
            exit 1
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
log_info "👋  回车直接执行, 输入其他字符退出: " 1
read choice
if [ -z "$choice" ]; then
    tailscale-helper
else
    log_info "👋  退出脚本....."
    sleep 1
    clear
    exit 0
fi
