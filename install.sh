#!/bin/sh
set -e

CONFIG_DIR="/etc/tailscale"
MIRROR_LIST_URL="CH3NGYZ/ts-test/main/mirrors.txt"
SCRIPTS_TGZ_URL="CH3NGYZ/ts-test/main/tailscale-openwrt-scripts.tar.gz"

# 预先计算的校验和
EXPECTED_CHECKSUM_SHA256="92af889fb8fc8864479a916be70ae7d1e0ea7efed42535a1540e775f66d6974e"
EXPECTED_CHECKSUM_MD5="ac81156d2092b886c87fd240eda4b3d1"

# 校验函数，接收三个参数：文件路径、校验类型（sha256/md5）、预期值
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
                echo "❌ 系统缺少 sha256sum 或 openssl，无法校验文件"
                return 1
            fi
            ;;
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                actual=$(md5sum "$file" | awk '{print $1}')
            elif command -v openssl >/dev/null 2>&1; then
                actual=$(openssl dgst -md5 "$file" | awk '{print $2}')
            else
                echo "❌ 系统缺少 md5sum 或 openssl，无法校验文件"
                return 1
            fi
            ;;
        *)
            echo "❌ 校验类型无效: $type"
            return 1
            ;;
    esac

    # 校验结果对比
    if [ "$actual" != "$expected" ]; then
        echo "❌ 校验失败！预期: $expected，实际: $actual"
        return 1
    fi

    echo "✅ 校验通过"
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
        result=$(curl -w %{http_code} --connect-timeout 10 $progress $redirect -ko "$1" "$2")
        [ -n "$(echo "$result" | grep -e ^2)" ] && result="200"
    else
        if command -v wget >/dev/null 2>&1; then
            [ "$3" = "echooff" ] && local progress='-q' || local progress='--show-progress'
            [ "$4" = "rediroff" ] && local redirect='--max-redirect=0' || local redirect=''
            local certificate='--no-check-certificate'
            local timeout='--timeout=10'
            wget $progress $redirect $certificate $timeout -O "$1" "$2"
            [ $? -eq 0 ] && result="200"
        else
            echo "Error: Neither curl nor wget available"
            return 1
        fi
    fi

    [ "$result" = "200" ] && return 0 || return 1
}

# 使用有效镜像代理进行下载
mirror_fetch() {
    local real_url=$1
    local output=$2
    local mirror_list_file="$CONFIG_DIR/valid_mirrors.txt"

    if [ -f "$mirror_list_file" ]; then
        while read -r mirror; do
            mirror=$(echo "$mirror" | sed 's|/*$|/|')  # 去掉结尾斜杠
            full_url="${mirror}${real_url}"
            echo "Trying mirror: $full_url"
            if webget "$output" "$full_url" "echooff"; then
                return 0
            fi
        done < "$mirror_list_file"
    fi

    # 如果所有代理都失败，尝试直接下载
    echo "Trying direct: $real_url"
    webget "$output" "$real_url" "echooff"
}

SCRIPTS_PATH="/tmp/tailscale-openwrt-scripts.tar.gz"
success=0

# 检查镜像并下载
if [ -f "$CONFIG_DIR/valid_mirrors.txt" ]; then
    while read -r mirror; do
        mirror=$(echo "$mirror" | sed 's|/*$|/|')
        full_url="${mirror}${SCRIPTS_TGZ_URL}"
        echo "🌐 尝试镜像: $full_url"

        if webget "$SCRIPTS_PATH" "$full_url" "echooff"; then
            if verify_checksum "$SCRIPTS_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256"; then
                success=1
                break
            else
                echo "⚠️ SHA256校验失败，尝试下一个镜像"
            fi
            if verify_checksum "$SCRIPTS_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"; then
                success=1
                break
            else
                echo "⚠️ MD5校验失败，尝试下一个镜像"
            fi
        fi
    done < "$CONFIG_DIR/valid_mirrors.txt"
fi

# 所有镜像失败后尝试直连
if [ "$success" -ne 1 ]; then
    echo "🌐 尝试直连: $SCRIPTS_TGZ_URL"
    if webget "$SCRIPTS_PATH" "$SCRIPTS_TGZ_URL" "echooff" && \
       verify_checksum "$SCRIPTS_PATH" "sha256" "$EXPECTED_CHECKSUM_SHA256"; then
        success=1
    fi
    if [ "$success" -ne 1 ]; then
        if webget "$SCRIPTS_PATH" "$SCRIPTS_TGZ_URL" "echooff" && \
           verify_checksum "$SCRIPTS_PATH" "md5" "$EXPECTED_CHECKSUM_MD5"; then
            success=1
        fi
    fi
fi

if [ "$success" -ne 1 ]; then
    echo "❌ 所有镜像与直连均失败，安装中止"
    exit 1
fi

# 解压脚本
echo "📦 解压脚本包..."
tar -xzf "$SCRIPTS_PATH" -C "$CONFIG_DIR"

# 设置权限
chmod +x "$CONFIG_DIR"/*.sh

# 初始化通知配置
cat > "$CONFIG_DIR/notify.conf" <<'EOF'
# 通知开关 (1=启用 0=禁用)
NOTIFY_UPDATE=1
NOTIFY_MIRROR_FAIL=1
NOTIFY_EMERGENCY=1

# Server酱SendKey
SERVERCHAN_KEY=""
EOF

echo "✅ 基础安装完成！请执行："
echo "   /etc/tailscale/setup.sh [options]"
