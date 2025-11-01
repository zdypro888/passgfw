#!/bin/bash

set -e

# ============================================================================
# PassGFW Interactive Build Script v2.1
# ============================================================================
#
# 交互式构建脚本 - 在构建时询问配置参数
#
# Usage:
#   ./build_interactive.sh <platform>
#
# Platforms:
#   ios         Build iOS framework
#   macos       Build macOS library
#   android     Build Android library
#   harmony     Build HarmonyOS HAR package
#   all         Build all platforms
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="2.1.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║   🚀 PassGFW 交互式构建工具                                      ║"
    printf "║   Version %-55s║\n" "$VERSION"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠️${NC}  $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

prompt() {
    local question="$1"
    local default="$2"
    local var_name="$3"

    echo -e -n "${CYAN}❯${NC} $question"
    if [ -n "$default" ]; then
        echo -e -n " ${YELLOW}[默认: $default]${NC}"
    fi
    echo -n ": "

    read -r user_input

    if [ -z "$user_input" ] && [ -n "$default" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$user_input'"
    fi
}

prompt_yesno() {
    local question="$1"
    local default="$2"  # y or n

    local prompt_suffix
    if [ "$default" == "y" ]; then
        prompt_suffix="${YELLOW}[Y/n]${NC}"
    else
        prompt_suffix="${YELLOW}[y/N]${NC}"
    fi

    echo -e -n "${CYAN}❯${NC} $question $prompt_suffix: "
    read -r answer

    # 如果用户直接回车，使用默认值
    if [ -z "$answer" ]; then
        answer="$default"
    fi

    case "$answer" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# Parse Arguments
# ============================================================================

PLATFORM=""
if [ $# -eq 0 ]; then
    log_error "请指定平台！"
    echo ""
    echo "用法: $0 <platform>"
    echo ""
    echo "平台选项:"
    echo "  ios         构建 iOS framework"
    echo "  macos       构建 macOS library"
    echo "  android     构建 Android library"
    echo "  harmony     构建 HarmonyOS HAR"
    echo "  all         构建所有平台"
    exit 1
else
    PLATFORM="$1"
fi

# ============================================================================
# Welcome & Initialize
# ============================================================================

print_header

echo "本工具将引导您配置构建参数。"
echo "您可以直接按 Enter 使用默认值（黄色显示）。"
echo ""

# ============================================================================
# Configuration Input
# ============================================================================

print_section "📝 基础配置"

# 1. 是否使用默认配置
if prompt_yesno "是否使用所有默认配置？(快速构建)" "y"; then
    USE_DEFAULTS=true

    # 默认配置
    URLS='[{"method":"api","url":"http://localhost:8080/passgfw"},{"method":"api","url":"http://127.0.0.1:8080/passgfw"}]'
    PUBLIC_KEY_PATH="../server/keys/public_key.pem"
    CFG_REQUEST_TIMEOUT=5
    CFG_MAX_RETRIES=2
    CFG_RETRY_DELAY=0.5
    CFG_RETRY_INTERVAL=2
    CFG_URL_INTERVAL=0.5
    CFG_MAX_LIST_RECURSION=5
    CFG_NONCE_SIZE=32
    CFG_MAX_CLIENT_DATA=200
    CFG_ENABLE_CONCURRENT=true
    CFG_CONCURRENT_COUNT=3
    CFG_FILE_CONCURRENT=false

    log_info "使用默认配置"
else
    USE_DEFAULTS=false

    # ========================================================================
    # URL Configuration
    # ========================================================================

    print_section "🌐 URL 配置"

    echo "请输入检测 URL（支持多个）"
    echo "格式: method,url"
    echo "例如: api,http://example.com/passgfw"
    echo ""
    echo "支持的 method: api, file, navigate, remove"
    echo "输入空行完成输入"
    echo ""

    declare -a URL_ENTRIES
    URL_COUNT=0

    while true; do
        prompt "URL #$((URL_COUNT + 1))" "" url_input

        # 如果是空输入且已有至少一个URL，结束输入
        if [ -z "$url_input" ] && [ $URL_COUNT -gt 0 ]; then
            break
        fi

        # 如果是第一个且为空，使用默认
        if [ -z "$url_input" ] && [ $URL_COUNT -eq 0 ]; then
            URL_ENTRIES+=("api,http://localhost:8080/passgfw")
            URL_COUNT=$((URL_COUNT + 1))
            log_info "使用默认 URL: http://localhost:8080/passgfw"
            break
        fi

        # 解析输入
        if [[ "$url_input" == *","* ]]; then
            URL_ENTRIES+=("$url_input")
            URL_COUNT=$((URL_COUNT + 1))
            log_info "已添加: $url_input"
        else
            # 如果没有逗号，默认为 api method
            URL_ENTRIES+=("api,$url_input")
            URL_COUNT=$((URL_COUNT + 1))
            log_info "已添加: api,$url_input"
        fi
    done

    # 构建 JSON
    URLS="["
    for i in "${!URL_ENTRIES[@]}"; do
        IFS=',' read -r method url <<< "${URL_ENTRIES[$i]}"

        if [ $i -gt 0 ]; then
            URLS="$URLS,"
        fi
        URLS="$URLS{\"method\":\"$method\",\"url\":\"$url\"}"
    done
    URLS="$URLS]"

    echo ""
    log_info "已配置 $URL_COUNT 个 URL"

    # ========================================================================
    # Public Key
    # ========================================================================

    print_section "🔑 公钥配置"

    prompt "公钥文件路径" "../server/keys/public_key.pem" PUBLIC_KEY_PATH

    # ========================================================================
    # Network Settings
    # ========================================================================

    print_section "⚙️  网络参数"

    prompt "HTTP 请求超时 (秒)" "5" CFG_REQUEST_TIMEOUT
    prompt "最大重试次数" "2" CFG_MAX_RETRIES
    prompt "重试延迟 (秒)" "0.5" CFG_RETRY_DELAY
    prompt "全部失败后重试间隔 (秒)" "2" CFG_RETRY_INTERVAL
    prompt "URL 检测间隔 (秒)" "0.5" CFG_URL_INTERVAL

    # ========================================================================
    # Security Settings
    # ========================================================================

    print_section "🔒 安全参数"

    prompt "最大递归深度" "5" CFG_MAX_LIST_RECURSION
    prompt "Nonce 大小 (字节)" "32" CFG_NONCE_SIZE
    prompt "最大 client_data 大小 (字节)" "200" CFG_MAX_CLIENT_DATA

    # ========================================================================
    # Concurrent Settings
    # ========================================================================

    print_section "⚡ 并发配置"

    echo "并发检测可以显著提升检测速度（推荐启用）"
    echo ""

    if prompt_yesno "启用并发检测？" "y"; then
        CFG_ENABLE_CONCURRENT=true
        prompt "并发批次大小 (建议2-5)" "3" CFG_CONCURRENT_COUNT

        if prompt_yesno "File 类型允许并发？(不推荐，可能导致递归爆炸)" "n"; then
            CFG_FILE_CONCURRENT=true
        else
            CFG_FILE_CONCURRENT=false
        fi
    else
        CFG_ENABLE_CONCURRENT=false
        CFG_CONCURRENT_COUNT=1
        CFG_FILE_CONCURRENT=false
    fi
fi

# ============================================================================
# Confirmation
# ============================================================================

print_section "📋 配置摘要"

echo "平台:       $PLATFORM"
echo "URL 数量:   $(echo "$URLS" | grep -o "method" | wc -l | tr -d ' ')"
echo "公钥:       $PUBLIC_KEY_PATH"
echo "超时:       ${CFG_REQUEST_TIMEOUT}s"
echo "重试:       ${CFG_MAX_RETRIES}次"
echo "并发检测:   $([ "$CFG_ENABLE_CONCURRENT" == "true" ] && echo "启用 (批次大小: $CFG_CONCURRENT_COUNT)" || echo "禁用")"
echo ""

if ! prompt_yesno "确认开始构建？" "y"; then
    log_warn "构建已取消"
    exit 0
fi

# ============================================================================
# Save Configuration (Optional)
# ============================================================================

if [ "$USE_DEFAULTS" == "false" ]; then
    echo ""
    if prompt_yesno "是否保存此配置以供将来使用？" "n"; then
        prompt "配置文件名" "my_config.json" CONFIG_SAVE_NAME

        cat > "$CONFIG_SAVE_NAME" << EOF
{
  "urls": $URLS,
  "public_key_path": "$PUBLIC_KEY_PATH",
  "config": {
    "request_timeout": $CFG_REQUEST_TIMEOUT,
    "max_retries": $CFG_MAX_RETRIES,
    "retry_delay": $CFG_RETRY_DELAY,
    "retry_interval": $CFG_RETRY_INTERVAL,
    "url_interval": $CFG_URL_INTERVAL,
    "max_list_recursion_depth": $CFG_MAX_LIST_RECURSION,
    "nonce_size": $CFG_NONCE_SIZE,
    "max_client_data_size": $CFG_MAX_CLIENT_DATA,
    "enable_concurrent_check": $CFG_ENABLE_CONCURRENT,
    "concurrent_check_count": $CFG_CONCURRENT_COUNT,
    "file_method_concurrent": $CFG_FILE_CONCURRENT
  }
}
EOF

        log_info "配置已保存到: $CONFIG_SAVE_NAME"
        echo "下次可使用: ./build.sh $PLATFORM --config $CONFIG_SAVE_NAME"
    fi
fi

# ============================================================================
# Generate Temporary Config File
# ============================================================================

print_section "🔨 开始构建"

TEMP_CONFIG="/tmp/passgfw_build_$$.json"

cat > "$TEMP_CONFIG" << EOF
{
  "urls": $URLS,
  "public_key_path": "$PUBLIC_KEY_PATH",
  "config": {
    "request_timeout": $CFG_REQUEST_TIMEOUT,
    "max_retries": $CFG_MAX_RETRIES,
    "retry_delay": $CFG_RETRY_DELAY,
    "retry_interval": $CFG_RETRY_INTERVAL,
    "url_interval": $CFG_URL_INTERVAL,
    "max_list_recursion_depth": $CFG_MAX_LIST_RECURSION,
    "nonce_size": $CFG_NONCE_SIZE,
    "max_client_data_size": $CFG_MAX_CLIENT_DATA,
    "enable_concurrent_check": $CFG_ENABLE_CONCURRENT,
    "concurrent_check_count": $CFG_CONCURRENT_COUNT,
    "file_method_concurrent": $CFG_FILE_CONCURRENT
  }
}
EOF

log_info "临时配置文件已创建"

# ============================================================================
# Call Original Build Script
# ============================================================================

echo ""
log_info "调用构建脚本..."
echo ""

# 调用原始构建脚本
if [ -f "./build.sh" ]; then
    ./build.sh "$PLATFORM" --config "$TEMP_CONFIG"
    BUILD_EXIT_CODE=$?
else
    log_error "找不到 build.sh 脚本"
    rm -f "$TEMP_CONFIG"
    exit 1
fi

# ============================================================================
# Cleanup
# ============================================================================

rm -f "$TEMP_CONFIG"

# ============================================================================
# Done
# ============================================================================

echo ""
if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║   🎉 构建成功完成！                                               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
else
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║   ❌ 构建失败                                                     ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
fi
echo ""

exit $BUILD_EXIT_CODE
