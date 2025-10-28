#!/bin/sh
set -e

CONFIG_DIR="/etc/tailscale"
mkdir -p "$CONFIG_DIR"
INST_CONF="$CONFIG_DIR/install.conf"

if [ -f /tmp/tailscale-use-direct ]; then
    echo "GITHUB_DIRECT=true" > "$INST_CONF"
    GITHUB_DIRECT=true
    CUSTOM_PROXY_URL=""
    rm -f /tmp/tailscale-use-direct
else
    echo "GITHUB_DIRECT=false" > "$INST_CONF"
    GITHUB_DIRECT=false
    CUSTOM_PROXY_URL="https://ghproxy.ch3ng.top/"
fi

SCRIPTS_TGZ_URL="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/tailscale-openwrt-scripts.tar.gz"
SCRIPTS_PATH="/tmp/tailscale-openwrt-scripts.tar.gz"
PRETEST_MIRRORS_SH_URL="CH3NGYZ/small-tailscale-openwrt/raw/refs/heads/main/pretest_mirrors.sh"

# 预先计算的校验和
EXPECTED_CHECKSUM_SHA256="86503a19d2dbbbf0b97db72947d8bc70a2f280d292162d7d01264345bf10ccda"
EXPECTED_CHECKSUM_MD5="a3cdbfb94bfc30b04b45e754e005acd2"
TIME_OUT=30

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

# 检查是否已经安装所有必要软件包
required_packages="libustream-openssl ca-bundle kmod-tun coreutils-timeout coreutils-nohup curl"
need_install=0

# 如果已安装 libustream-mbedtls，则跳过 libustream-openssl
skip_openssl=0
if opkg list-installed | grep -q "^libustream-mbedtls"; then
    skip_openssl=1
fi

for package in $required_packages; do
    # 跳过 openssl 版本，仅标记，不输出日志
    if [ "$skip_openssl" -eq 1 ] && [ "$package" = "libustream-openssl" ]; then
        continue
    fi

    if ! opkg list-installed | grep -q "^$package"; then
        log_warn "⚠️ 包 $package 未安装"
        need_install=1
    fi
done

if [ "$need_install" -eq 0 ]; then
    log_info "✅ 已安装所有必要组件"
else
    log_info "🔄 正在更新 opkg 源..."
    if ! opkg update 2>&1; then
        log_error "❌ opkg update 失败，请检查网络连接或源配置"
        exit 1
    fi

    for package in $required_packages; do
        # 在安装流程中才输出跳过提示
        if [ "$skip_openssl" -eq 1 ] && [ "$package" = "libustream-openssl" ]; then
            log_info "✅ 检测到 libustream-mbedtls，跳过 libustream-openssl"
            continue
        fi

        if ! opkg list-installed | grep -q "^$package"; then
            log_warn "⚠️ 包 $package 未安装，开始安装..."
            if opkg install "$package" 2>&1; then
                log_info "✅ 包 $package 安装成功"
            else
                if [ "$package" = "coreutils-timeout" ] || [ "$package" = "coreutils-nohup" ]; then
                    alt="coreutils"
                    log_warn "⚠️ 安装 $package 失败，尝试安装 $alt 替代..."
                    if opkg install $alt 2>&1; then
                        log_info "✅ $alt 安装成功，可能已包含 $(echo $package | cut -d- -f2) 命令"
                        continue
                    fi
                fi
                log_error "❌ 安装 $package 失败，无法继续，请手动安装此包"
                exit 1
            fi
        fi
    done

    # 最终检查命令可用性
    for cmd in timeout nohup; do
        if ! command -v $cmd >/dev/null 2>&1; then
            log_error "❌ 未检测到 $cmd 命令，请手动安装后重新执行脚本"
            exit 1
        else
            log_info "✅ $cmd 命令已可用"
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

    log_info "✅  校验通过"
    return 0
}

# 下载文件的函数
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
        result=$(timeout "$TIME_OUT" curl -w "%{http_code}" -H "User-Agent: Mozilla/5.0 (curl-compatible)" $progress $redirect -o "$1" "$2")
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
            timeout "$TIME_OUT" wget --header="User-Agent: Mozilla/5.0" $progress $redirect $certificate -O "$1" "$2"
            if [ $? -eq 0 ]; then
                result="200"
            else
                result="non-200"
            fi
        else
            echo "Error: Neither curl nor wget available"
            return 1
        fi
    fi

    [ "$result" = "200" ] && return 0 || return 1
}

# 使用自建代理
proxy_url="${CUSTOM_PROXY_URL}https://github.com/${SCRIPTS_TGZ_URL}"
direct_url="https://github.com/${SCRIPTS_TGZ_URL}"
success=0

if [ "$GITHUB_DIRECT" = "true" ] ; then
    log_info "📄  使用 GitHub 直连下载: $direct_url"
    if webget "$SCRIPTS_PATH" "$direct_url" "echooff" && \
       (verify_checksum "$SCRIPTS_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256" || \
        verify_checksum "$SCRIPTS_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"); then
        success=1
    fi
else
    log_info "🔗  使用自建代理下载: $proxy_url"
    if webget "$SCRIPTS_PATH" "$proxy_url" "echooff" && \
       (verify_checksum "$SCRIPTS_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256" || \
        verify_checksum "$SCRIPTS_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"); then
        success=1
    else
        log_info "🔗  代理失效，尝试直连: $direct_url"
        if webget "$SCRIPTS_PATH" "$direct_url" "echooff" && \
           (verify_checksum "$SCRIPTS_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256" || \
            verify_checksum "$SCRIPTS_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"); then
            success=1
        fi
    fi
fi



if [ "$success" -ne 1 ]; then
    log_error "❌  镜像与直连均失败, 安装中止"
    exit 1
fi

# 解压脚本
log_info "📦  解压脚本包..."
tar -xzf "$SCRIPTS_PATH" -C "$CONFIG_DIR"

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
    log_info "🔄  下载 pretest_mirrors.sh 并执行测速..."

    proxy_url="${CUSTOM_PROXY_URL}https://github.com/${PRETEST_MIRRORS_SH_URL}"
    raw_url="https://github.com/${PRETEST_MIRRORS_SH_URL}"
    if webget "/tmp/pretest_mirrors.sh" "$proxy_url" "echooff"; then
        sh /tmp/pretest_mirrors.sh
    else
        log_info "🔗  代理失效，尝试 GitHub 直连: $raw_url"
        if webget "/tmp/pretest_mirrors.sh" "$raw_url" "echooff"; then
            sh /tmp/pretest_mirrors.sh
        else
            return 1
        fi
    fi
}

if [ "$GITHUB_DIRECT" = "true" ] ; then
    log_info "✅  使用Github直连, 跳过测速！"
else
    if [ ! -f /etc/tailscale/proxies.txt ]; then
        log_info "🔍 本地不存在 proxies.txt, 将下载镜像列表并测速, 请等待..."
        if run_pretest_mirrors; then
            log_info "✅  下载镜像列表并测速完成！"
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
log_info "👋  回车直接执行, 输入其他字符退出......"
read choice
if [ -z "$choice" ]; then
    tailscale-helper
else
    log_info "👋  退出脚本....."
    sleep 2
    clear
    exit 0
fi