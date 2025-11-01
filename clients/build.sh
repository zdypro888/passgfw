#!/bin/bash

set -e

# ============================================================================
# PassGFW Build Script v2.0
# ============================================================================
#
# Usage:
#   ./build.sh <platform> [options]
#
# Platforms:
#   ios         Build iOS framework
#   macos       Build macOS library
#   android     Build Android library
#   harmony     Build HarmonyOS HAR package
#   all         Build all platforms (sequentially)
#
# Options:
#   --config FILE       Use custom config file (default: build_config.json)
#   --urls "url1,url2"  Override URLs temporarily
#   --clean             Clean before build
#   --parallel          Build platforms in parallel (for 'all')
#   --verify            Verify build after completion
#   --help              Show this help message
#
# Examples:
#   ./build.sh ios
#   ./build.sh android --clean
#   ./build.sh all --config production_config.json
#   ./build.sh all --parallel
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Version
VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CONFIG_FILE="build_config.json"
DEFAULT_URLS='[{"method":"api","url":"http://localhost:8080/passgfw"}]'
DEFAULT_KEY_PATH="../server/keys/public_key.pem"
CLEAN_BUILD=false
CUSTOM_URLS=""
PARALLEL_BUILD=false
VERIFY_BUILD=false

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║   $1"
    printf "║   PassGFW Build Script v%-41s║\n" "$VERSION"
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

show_help() {
    head -n 35 "$0" | tail -n +3
    exit 0
}

# Check required tools
check_dependencies() {
    local missing_deps=()

    # Check for jq or python3 (for JSON parsing)
    if ! command -v jq &> /dev/null && ! command -v python3 &> /dev/null; then
        missing_deps+=("jq or python3")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "   - $dep"
        done
        echo ""
        log_info "Install using: brew install jq (recommended)"
        exit 1
    fi
}

# Parse JSON using jq or python3
parse_json() {
    local json="$1"
    local query="$2"

    if command -v jq &> /dev/null; then
        echo "$json" | jq -r "$query" 2>/dev/null
    elif command -v python3 &> /dev/null; then
        echo "$json" | python3 -c "import json,sys; data=json.load(sys.stdin); $query" 2>/dev/null
    fi
}

# ============================================================================
# Parse Arguments
# ============================================================================

PLATFORM=""
while [[ $# -gt 0 ]]; do
    case $1 in
        ios|macos|android|harmony|all)
            PLATFORM="$1"
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --urls)
            CUSTOM_URLS="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --parallel)
            PARALLEL_BUILD=true
            shift
            ;;
        --verify)
            VERIFY_BUILD=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            echo ""
            echo "Run './build.sh --help' for usage information"
            exit 1
            ;;
    esac
done

if [ -z "$PLATFORM" ]; then
    log_error "Platform not specified!"
    echo ""
    echo "Usage: $0 <platform> [options]"
    echo ""
    echo "Platforms: ios, macos, android, harmony, all"
    echo "Run './build.sh --help' for more information"
    exit 1
fi

# ============================================================================
# Initialize
# ============================================================================

print_header "🚀 Build Starting..."

# Check dependencies
check_dependencies

# ============================================================================
# Load Configuration
# ============================================================================

URLS=""
PUBLIC_KEY_PATH=""

print_section "📝 Loading Configuration"

if [ -n "$CUSTOM_URLS" ]; then
    # Use custom URLs from command line
    echo "Using custom URLs from command line"
    IFS=',' read -ra URL_ARRAY <<< "$CUSTOM_URLS"
    URLS="["
    for i in "${!URL_ARRAY[@]}"; do
        if [ $i -gt 0 ]; then
            URLS="$URLS,"
        fi
        URLS="$URLS{\"method\":\"api\",\"url\":\"${URL_ARRAY[$i]}\"}"
    done
    URLS="$URLS]"
    PUBLIC_KEY_PATH="$DEFAULT_KEY_PATH"
elif [ -f "$CONFIG_FILE" ]; then
    # Load from config file
    echo "Loading configuration from: $CONFIG_FILE"

    CONFIG_JSON=$(cat "$CONFIG_FILE")
    URLS=$(echo "$CONFIG_JSON" | parse_json "$CONFIG_JSON" '.urls')
    PUBLIC_KEY_PATH=$(echo "$CONFIG_JSON" | parse_json "$CONFIG_JSON" '.public_key_path // "'$DEFAULT_KEY_PATH'"')

    if [ -z "$URLS" ] || [ "$URLS" == "null" ]; then
        log_warn "Failed to parse URLs from config, using defaults"
        URLS="$DEFAULT_URLS"
    fi
else
    # Use default values
    log_warn "No config file found, using default: localhost:8080"
    URLS="$DEFAULT_URLS"
    PUBLIC_KEY_PATH="$DEFAULT_KEY_PATH"
fi

echo "   URLs: $(echo "$URLS" | parse_json "$URLS" 'length') entries"
echo "   Key:  $PUBLIC_KEY_PATH"

# Load config parameters (with defaults if not specified)
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_JSON=$(cat "$CONFIG_FILE")

    if command -v jq &> /dev/null; then
        CFG_REQUEST_TIMEOUT=$(echo "$CONFIG_JSON" | jq -r '.config.request_timeout // 5')
        CFG_MAX_RETRIES=$(echo "$CONFIG_JSON" | jq -r '.config.max_retries // 2')
        CFG_RETRY_DELAY=$(echo "$CONFIG_JSON" | jq -r '.config.retry_delay // 0.5')
        CFG_RETRY_INTERVAL=$(echo "$CONFIG_JSON" | jq -r '.config.retry_interval // 2')
        CFG_URL_INTERVAL=$(echo "$CONFIG_JSON" | jq -r '.config.url_interval // 0.5')
        CFG_MAX_LIST_RECURSION=$(echo "$CONFIG_JSON" | jq -r '.config.max_list_recursion_depth // 5')
        CFG_NONCE_SIZE=$(echo "$CONFIG_JSON" | jq -r '.config.nonce_size // 32')
        CFG_MAX_CLIENT_DATA=$(echo "$CONFIG_JSON" | jq -r '.config.max_client_data_size // 200')
        CFG_ENABLE_CONCURRENT=$(echo "$CONFIG_JSON" | jq -r '.config.enable_concurrent_check // true')
        CFG_CONCURRENT_COUNT=$(echo "$CONFIG_JSON" | jq -r '.config.concurrent_check_count // 3')
        CFG_FILE_CONCURRENT=$(echo "$CONFIG_JSON" | jq -r '.config.file_method_concurrent // false')
    else
        CFG_REQUEST_TIMEOUT=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('request_timeout', 5))")
        CFG_MAX_RETRIES=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('max_retries', 2))")
        CFG_RETRY_DELAY=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('retry_delay', 0.5))")
        CFG_RETRY_INTERVAL=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('retry_interval', 2))")
        CFG_URL_INTERVAL=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('url_interval', 0.5))")
        CFG_MAX_LIST_RECURSION=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('max_list_recursion_depth', 5))")
        CFG_NONCE_SIZE=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('nonce_size', 32))")
        CFG_MAX_CLIENT_DATA=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('max_client_data_size', 200))")
        CFG_ENABLE_CONCURRENT=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('config', {}).get('enable_concurrent_check', True)).lower())")
        CFG_CONCURRENT_COUNT=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('config', {}).get('concurrent_check_count', 3))")
        CFG_FILE_CONCURRENT=$(echo "$CONFIG_JSON" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('config', {}).get('file_method_concurrent', False)).lower())")
    fi
else
    # Default config values
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
fi

echo "   Config: timeout=${CFG_REQUEST_TIMEOUT}s, retries=${CFG_MAX_RETRIES}, delay=${CFG_RETRY_DELAY}s"

# ============================================================================
# Load Public Key
# ============================================================================

print_section "🔑 Loading Public Key"

if [ ! -f "$PUBLIC_KEY_PATH" ]; then
    log_warn "Public key not found: $PUBLIC_KEY_PATH"
    echo "   Generating RSA key pair..."

    mkdir -p "$(dirname "$PUBLIC_KEY_PATH")"
    openssl genrsa -out "$(dirname "$PUBLIC_KEY_PATH")/private_key.pem" 2048 2>/dev/null
    openssl rsa -in "$(dirname "$PUBLIC_KEY_PATH")/private_key.pem" -pubout -out "$PUBLIC_KEY_PATH" 2>/dev/null

    log_info "RSA key pair generated successfully"
fi

PUBLIC_KEY=$(cat "$PUBLIC_KEY_PATH")
log_info "Public key loaded ($(echo "$PUBLIC_KEY" | wc -l | tr -d ' ') lines)"

# ============================================================================
# Generate Config Code for Each Platform
# ============================================================================

generate_swift_config() {
    local urls_array=""

    if command -v jq &> /dev/null; then
        local url_count=$(echo "$URLS" | jq 'length')
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | jq -r ".[$i].method // \"api\"")
            local url=$(echo "$URLS" | jq -r ".[$i].url")
            local store=$(echo "$URLS" | jq -r ".[$i].store // false")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array            URLEntry(method: \"$method\", url: \"$url\", store: true)"
            else
                urls_array="$urls_array            URLEntry(method: \"$method\", url: \"$url\")"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    else
        # Fallback to python3
        local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i].get('method', 'api'))")
            local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['url'])")
            local store=$(echo "$URLS" | python3 -c "import json,sys; print(str(json.load(sys.stdin)[$i].get('store', False)).lower())")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array            URLEntry(method: \"$method\", url: \"$url\", store: true)"
            else
                urls_array="$urls_array            URLEntry(method: \"$method\", url: \"$url\")"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    fi

    # Indent public key for Swift multi-line string (8 spaces)
    local indented_key=$(echo "$PUBLIC_KEY" | sed 's/^/        /')

    cat > /tmp/swift_config.txt << EOF
    // BUILD_CONFIG_START - Auto-generated by build script v$VERSION, DO NOT EDIT MANUALLY
    /// Get built-in URL list
    /// These URLs are generated during build from $CONFIG_FILE
    static func getBuiltinURLs() -> [URLEntry] {
        return [
$urls_array
        ]
    }

    /// Get public key (PEM format)
    /// This key is embedded during build from $PUBLIC_KEY_PATH
    static func getPublicKey() -> String {
        return """
$indented_key
        """
    }

    // MARK: - Timeout Settings

    /// HTTP request timeout (seconds)
    static let requestTimeout: TimeInterval = $CFG_REQUEST_TIMEOUT

    /// Retry interval when all URLs fail (seconds)
    static let retryInterval: TimeInterval = $CFG_RETRY_INTERVAL

    /// Interval between URL checks (seconds)
    static let urlInterval: TimeInterval = $CFG_URL_INTERVAL

    // MARK: - Retry Settings

    /// Maximum number of retries per URL
    static let maxRetries = $CFG_MAX_RETRIES

    /// Delay between retries (seconds)
    static let retryDelay: TimeInterval = $CFG_RETRY_DELAY

    // MARK: - Security Limits

    /// Maximum nested list# depth
    static let maxListRecursionDepth = $CFG_MAX_LIST_RECURSION

    /// Random nonce size in bytes
    static let nonceSize = $CFG_NONCE_SIZE

    /// Maximum client_data length (RSA 2048 limit ~245 bytes for payload)
    static let maxClientDataSize = $CFG_MAX_CLIENT_DATA

    // MARK: - Concurrent Check Settings

    /// Enable concurrent URL checking
    static let enableConcurrentCheck = $CFG_ENABLE_CONCURRENT

    /// Number of URLs to check concurrently (batch size)
    static let concurrentCheckCount = $CFG_CONCURRENT_COUNT

    /// Allow concurrent checking for File method (false recommended to avoid recursion explosion)
    static let fileMethodConcurrent = $CFG_FILE_CONCURRENT
    // BUILD_CONFIG_END
EOF
}

generate_kotlin_config() {
    local urls_array=""

    if command -v jq &> /dev/null; then
        local url_count=$(echo "$URLS" | jq 'length')
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | jq -r ".[$i].method // \"api\"")
            local url=$(echo "$URLS" | jq -r ".[$i].url")
            local store=$(echo "$URLS" | jq -r ".[$i].store // false")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array            URLEntry(method = \"$method\", url = \"$url\", store = true)"
            else
                urls_array="$urls_array            URLEntry(method = \"$method\", url = \"$url\")"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    else
        local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i].get('method', 'api'))")
            local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['url'])")
            local store=$(echo "$URLS" | python3 -c "import json,sys; print(str(json.load(sys.stdin)[$i].get('store', False)).lower())")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array            URLEntry(method = \"$method\", url = \"$url\", store = true)"
            else
                urls_array="$urls_array            URLEntry(method = \"$method\", url = \"$url\")"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    fi

    # Convert float to long for Kotlin (e.g., 0.5 -> 500 milliseconds)
    local kotlin_retry_delay=$( echo "$CFG_RETRY_DELAY * 1000" | bc | cut -d'.' -f1 )
    local kotlin_request_timeout=$( echo "$CFG_REQUEST_TIMEOUT * 1000" | bc | cut -d'.' -f1 )
    local kotlin_retry_interval=$( echo "$CFG_RETRY_INTERVAL * 1000" | bc | cut -d'.' -f1 )
    local kotlin_url_interval=$( echo "$CFG_URL_INTERVAL * 1000" | bc | cut -d'.' -f1 )

    cat > /tmp/kotlin_config.txt << EOF
    // BUILD_CONFIG_START - Auto-generated by build script v$VERSION, DO NOT EDIT MANUALLY
    /**
     * Get built-in URL list
     * These URLs are generated during build from $CONFIG_FILE
     */
    fun getBuiltinURLs(): List<URLEntry> {
        return listOf(
$urls_array
        )
    }

    /**
     * Get public key (PEM format)
     * This key is embedded during build from $PUBLIC_KEY_PATH
     */
    fun getPublicKey(): String {
        return """
$PUBLIC_KEY
        """.trimIndent()
    }

    // Timeout settings
    const val REQUEST_TIMEOUT = ${kotlin_request_timeout}L  // milliseconds
    const val RETRY_INTERVAL = ${kotlin_retry_interval}L
    const val URL_INTERVAL = ${kotlin_url_interval}L

    // Retry settings
    const val MAX_RETRIES = $CFG_MAX_RETRIES
    const val RETRY_DELAY = ${kotlin_retry_delay}L  // milliseconds

    // Security limits
    const val MAX_LIST_RECURSION_DEPTH = $CFG_MAX_LIST_RECURSION
    const val NONCE_SIZE = $CFG_NONCE_SIZE
    const val MAX_CLIENT_DATA_SIZE = $CFG_MAX_CLIENT_DATA

    // Concurrent check settings
    const val ENABLE_CONCURRENT_CHECK = $CFG_ENABLE_CONCURRENT    // 是否启用并发检测
    const val CONCURRENT_CHECK_COUNT = $CFG_CONCURRENT_COUNT        // 同时检测的 URL 数量（批次大小）
    const val FILE_METHOD_CONCURRENT = $CFG_FILE_CONCURRENT    // File 类型是否允许并发（建议false避免递归爆炸）
    // BUILD_CONFIG_END
EOF
}

generate_arkts_config() {
    local urls_array=""

    if command -v jq &> /dev/null; then
        local url_count=$(echo "$URLS" | jq 'length')
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | jq -r ".[$i].method // \"api\"")
            local url=$(echo "$URLS" | jq -r ".[$i].url")
            local store=$(echo "$URLS" | jq -r ".[$i].store // false")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array      { method: '$method', url: '$url', store: true }"
            else
                urls_array="$urls_array      { method: '$method', url: '$url' }"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    else
        local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
        for i in $(seq 0 $((url_count - 1))); do
            local method=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i].get('method', 'api'))")
            local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i]['url'])")
            local store=$(echo "$URLS" | python3 -c "import json,sys; print(str(json.load(sys.stdin)[$i].get('store', False)).lower())")

            if [ "$store" == "true" ]; then
                urls_array="$urls_array      { method: '$method', url: '$url', store: true }"
            else
                urls_array="$urls_array      { method: '$method', url: '$url' }"
            fi

            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        done
    fi

    # Convert float to milliseconds for ArkTS (e.g., 0.5 -> 500)
    local arkts_retry_delay=$( echo "$CFG_RETRY_DELAY * 1000" | bc | cut -d'.' -f1 )
    local arkts_request_timeout=$( echo "$CFG_REQUEST_TIMEOUT * 1000" | bc | cut -d'.' -f1 )
    local arkts_retry_interval=$( echo "$CFG_RETRY_INTERVAL * 1000" | bc | cut -d'.' -f1 )
    local arkts_url_interval=$( echo "$CFG_URL_INTERVAL * 1000" | bc | cut -d'.' -f1 )

    cat > /tmp/arkts_config.txt << EOF
  // BUILD_CONFIG_START - Auto-generated by build script v$VERSION, DO NOT EDIT MANUALLY
  /**
   * Get built-in URL list
   * These URLs are generated during build from $CONFIG_FILE
   */
  static getBuiltinURLs(): URLEntry[] {
    return [
$urls_array
    ];
  }

  /**
   * Get public key (PEM format)
   * This key is embedded during build from $PUBLIC_KEY_PATH
   */
  static getPublicKey(): string {
    return \`$PUBLIC_KEY\`;
  }

  // Timeout settings (milliseconds)
  static readonly REQUEST_TIMEOUT: number = $arkts_request_timeout;
  static readonly RETRY_INTERVAL: number = $arkts_retry_interval;
  static readonly URL_INTERVAL: number = $arkts_url_interval;

  // Retry settings
  static readonly MAX_RETRIES: number = $CFG_MAX_RETRIES;
  static readonly RETRY_DELAY: number = $arkts_retry_delay;

  // Security limits
  static readonly MAX_LIST_RECURSION_DEPTH: number = $CFG_MAX_LIST_RECURSION;
  static readonly NONCE_SIZE: number = $CFG_NONCE_SIZE;
  static readonly MAX_CLIENT_DATA_SIZE: number = $CFG_MAX_CLIENT_DATA;

  // Concurrent check settings
  static readonly ENABLE_CONCURRENT_CHECK: boolean = $CFG_ENABLE_CONCURRENT;
  static readonly CONCURRENT_CHECK_COUNT: number = $CFG_CONCURRENT_COUNT;
  static readonly FILE_METHOD_CONCURRENT: boolean = $CFG_FILE_CONCURRENT;
  // BUILD_CONFIG_END
EOF
}

# ============================================================================
# Update Config Files
# ============================================================================

update_config_file() {
    local config_file="$1"
    local temp_config="$2"

    if [ ! -f "$config_file" ]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    # Use awk to replace content between markers
    awk '
        /BUILD_CONFIG_START/ {
            print
            while ((getline line < "'$temp_config'") > 0) {
                if (line !~ /BUILD_CONFIG_START/ && line !~ /BUILD_CONFIG_END/) {
                    print line
                }
            }
            skip=1
            next
        }
        /BUILD_CONFIG_END/ {
            skip=0
        }
        !skip
    ' "$config_file" > "$config_file.new"

    mv "$config_file.new" "$config_file"
    log_info "Config updated: $config_file"
}

# ============================================================================
# Build Functions
# ============================================================================

build_ios() {
    print_section "📱 Building iOS/macOS"

    cd ios-macos

    if [ "$CLEAN_BUILD" = true ]; then
        echo "Cleaning build artifacts..."
        swift package clean 2>/dev/null || true
        rm -rf .build
        log_info "iOS/macOS clean complete"
        cd ..
        return 0
    fi

    generate_swift_config
    update_config_file "Sources/PassGFW/Config.swift" "/tmp/swift_config.txt"

    echo "Building Swift package..."
    if swift build -c release 2>&1 | grep -v "^Fetching" | grep -v "^Cloning"; then
        log_info "iOS/macOS build complete"
        echo "   Output: $(pwd)/.build/release/"

        if [ "$VERIFY_BUILD" = true ]; then
            if [ -d ".build/release" ]; then
                log_info "Build verification passed"
            else
                log_error "Build verification failed"
                cd ..
                return 1
            fi
        fi
    else
        log_error "iOS/macOS build failed"
        cd ..
        return 1
    fi

    cd ..
}

build_macos() {
    # macOS uses the same build as iOS (Swift Package supports both)
    build_ios
}

build_android() {
    print_section "🤖 Building Android"

    cd android

    if [ "$CLEAN_BUILD" = true ]; then
        echo "Cleaning build artifacts..."

        # Run gradle clean first
        ./gradlew clean > /dev/null 2>&1

        # Clean build artifacts (after gradlew clean)
        rm -f build.log 2>/dev/null
        rm -rf build 2>/dev/null

        # Clean IDE files
        rm -rf .idea 2>/dev/null
        rm -f *.iml 2>/dev/null
        rm -rf */build 2>/dev/null
        rm -rf */*.iml 2>/dev/null

        # Clean .gradle (must be after gradlew clean as it recreates it)
        rm -rf .gradle 2>/dev/null

        # Note: local.properties is kept because it contains SDK path needed for builds

        log_info "Android clean complete"
        cd ..
        return 0
    fi

    # Check for gradlew
    if [ ! -f "./gradlew" ]; then
        log_error "gradlew not found. Please run from correct directory."
        cd ..
        return 1
    fi

    generate_kotlin_config
    update_config_file "passgfw/src/main/kotlin/com/passgfw/Config.kt" "/tmp/kotlin_config.txt"

    echo "Building AAR library and test APK..."
    if ./gradlew :passgfw:assembleRelease :app:assembleDebug --no-daemon 2>&1 | grep -E "(BUILD|SUCCESSFUL|FAILED)"; then
        local build_success=true

        # Check AAR
        if [ -f "passgfw/build/outputs/aar/passgfw-release.aar" ]; then
            log_info "AAR library built successfully"
            echo "   AAR: $(pwd)/passgfw/build/outputs/aar/passgfw-release.aar"

            if [ "$VERIFY_BUILD" = true ]; then
                local aar_size=$(stat -f%z "passgfw/build/outputs/aar/passgfw-release.aar" 2>/dev/null || stat -c%s "passgfw/build/outputs/aar/passgfw-release.aar" 2>/dev/null)
                if [ "$aar_size" -gt 1000 ]; then
                    log_info "AAR verification passed (size: $aar_size bytes)"
                else
                    log_warn "AAR file is suspiciously small: $aar_size bytes"
                fi
            fi
        else
            log_error "AAR file not generated"
            build_success=false
        fi

        # Check APK
        if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
            log_info "Test APK built successfully"
            echo "   APK: $(pwd)/app/build/outputs/apk/debug/app-debug.apk"

            if [ "$VERIFY_BUILD" = true ]; then
                local apk_size=$(stat -f%z "app/build/outputs/apk/debug/app-debug.apk" 2>/dev/null || stat -c%s "app/build/outputs/apk/debug/app-debug.apk" 2>/dev/null)
                if [ "$apk_size" -gt 100000 ]; then
                    log_info "APK verification passed (size: $apk_size bytes)"
                else
                    log_warn "APK file is suspiciously small: $apk_size bytes"
                fi
            fi
        else
            log_warn "Test APK not generated (this is OK if only building library)"
        fi

        if [ "$build_success" = false ]; then
            cd ..
            return 1
        fi
    else
        log_error "Android build failed"
        cd ..
        return 1
    fi

    cd ..
}

build_harmony() {
    print_section "🔷 Building HarmonyOS"

    cd harmony

    if [ "$CLEAN_BUILD" = true ]; then
        echo "Cleaning build artifacts..."
        rm -rf entry/build .hvigor build
        log_info "HarmonyOS clean complete"
        cd ..
        return 0
    fi

    generate_arkts_config
    update_config_file "entry/src/main/ets/passgfw/Config.ets" "/tmp/arkts_config.txt"

    log_warn "HarmonyOS requires DevEco Studio to build"
    echo "   Config file updated successfully"
    echo "   Please build in DevEco Studio to generate HAR package"

    log_info "HarmonyOS config updated"

    cd ..
}

# ============================================================================
# Main Build Logic
# ============================================================================

print_section "🔨 Starting Build Process"

BUILD_START=$(date +%s)

if [ "$PLATFORM" == "all" ] && [ "$PARALLEL_BUILD" = true ]; then
    log_info "Building all platforms in parallel..."

    # Run builds in background
    build_ios &
    PID_IOS=$!

    build_android &
    PID_ANDROID=$!

    build_harmony &
    PID_HARMONY=$!

    # Wait for all builds
    wait $PID_IOS
    EXIT_IOS=$?

    wait $PID_ANDROID
    EXIT_ANDROID=$?

    wait $PID_HARMONY
    EXIT_HARMONY=$?

    # Check results
    if [ $EXIT_IOS -ne 0 ] || [ $EXIT_ANDROID -ne 0 ] || [ $EXIT_HARMONY -ne 0 ]; then
        log_error "Some builds failed"
        exit 1
    fi
else
    # Sequential builds
    case "$PLATFORM" in
        ios)
            build_ios
            ;;
        macos)
            build_macos
            ;;
        android)
            build_android
            ;;
        harmony)
            build_harmony
            ;;
        all)
            build_ios || exit 1
            build_android || exit 1
            build_harmony || exit 1
            ;;
    esac
fi

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

# ============================================================================
# Cleanup
# ============================================================================

print_section "🧹 Cleanup"

rm -f /tmp/swift_config.txt /tmp/kotlin_config.txt /tmp/arkts_config.txt
log_info "Temporary files removed"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
if [ "$CLEAN_BUILD" = true ]; then
    echo "║   ✅ Clean Complete!                                             ║"
else
    echo "║   🎉 Build Complete!                                             ║"
fi
echo "║                                                                  ║"
printf "║   Build time: %-51s║\n" "${BUILD_TIME}s"
printf "║   Platform:   %-51s║\n" "$PLATFORM"
printf "║   Config:     %-51s║\n" "$CONFIG_FILE"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$CLEAN_BUILD" = false ]; then
    log_info "Config files updated with URLs from $CONFIG_FILE"
    log_info "Build artifacts ready for integration"
fi

echo ""
