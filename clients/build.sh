#!/bin/bash

set -e

# ============================================================================
# PassGFW Build Script
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
#   all         Build all platforms
#
# Options:
#   --config FILE       Use custom config file (default: build_config.json)
#   --urls "url1,url2"  Override URLs temporarily
#   --clean             Clean before build
#
# Examples:
#   ./build.sh ios
#   ./build.sh android --clean
#   ./build.sh all --config production_config.json
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
CONFIG_FILE="build_config.json"
DEFAULT_URLS='["http://localhost:8080/passgfw"]'
DEFAULT_KEY_PATH="../server/keys/public_key.pem"
CLEAN_BUILD=false
CUSTOM_URLS=""

# Parse arguments
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
        *)
            echo "❌ Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$PLATFORM" ]; then
    echo "❌ Platform not specified!"
    echo ""
    echo "Usage: $0 <platform> [options]"
    echo ""
    echo "Platforms: ios, macos, android, harmony, all"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║   🚀 PassGFW Build Script                                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Load Configuration
# ============================================================================

URLS=""
PUBLIC_KEY_PATH=""

if [ -n "$CUSTOM_URLS" ]; then
    # Use custom URLs from command line
    echo "📝 Using custom URLs from command line"
    IFS=',' read -ra URL_ARRAY <<< "$CUSTOM_URLS"
    URLS="["
    for i in "${!URL_ARRAY[@]}"; do
        if [ $i -gt 0 ]; then
            URLS="$URLS,"
        fi
        URLS="$URLS\"${URL_ARRAY[$i]}\""
    done
    URLS="$URLS]"
    PUBLIC_KEY_PATH="$DEFAULT_KEY_PATH"
elif [ -f "$CONFIG_FILE" ]; then
    # Load from config file
    echo "📝 Loading configuration from: $CONFIG_FILE"
    
    # Extract URLs (using Python for JSON parsing)
    if command -v python3 &> /dev/null; then
        URLS=$(python3 -c "import json; print(json.dumps(json.load(open('$CONFIG_FILE'))['urls']))")
        PUBLIC_KEY_PATH=$(python3 -c "import json; config=json.load(open('$CONFIG_FILE')); print(config.get('public_key_path', '$DEFAULT_KEY_PATH'))")
    else
        echo "⚠️  Python3 not found, using default configuration"
        URLS="$DEFAULT_URLS"
        PUBLIC_KEY_PATH="$DEFAULT_KEY_PATH"
    fi
else
    # Use default values
    echo "📝 No config file found, using default: localhost:8080"
    URLS="$DEFAULT_URLS"
    PUBLIC_KEY_PATH="$DEFAULT_KEY_PATH"
fi

echo "   URLs: $URLS"
echo "   Key:  $PUBLIC_KEY_PATH"
echo ""

# ============================================================================
# Load Public Key
# ============================================================================

if [ ! -f "$PUBLIC_KEY_PATH" ]; then
    echo "⚠️  Public key not found: $PUBLIC_KEY_PATH"
    echo "   Generating keys..."
    
    mkdir -p "$(dirname "$PUBLIC_KEY_PATH")"
    openssl genrsa -out "$(dirname "$PUBLIC_KEY_PATH")/private_key.pem" 2048
    openssl rsa -in "$(dirname "$PUBLIC_KEY_PATH")/private_key.pem" -pubout -out "$PUBLIC_KEY_PATH"
    
    echo "✅ Keys generated successfully"
fi

PUBLIC_KEY=$(cat "$PUBLIC_KEY_PATH")

echo "✅ Public key loaded"
echo ""

# ============================================================================
# Generate Config Code for Each Platform
# ============================================================================

generate_swift_config() {
    local urls_array=""
    local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    
    for i in $(seq 0 $((url_count - 1))); do
        local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i])" 2>/dev/null || echo "")
        if [ -n "$url" ]; then
            urls_array="$urls_array            \"$url\""
            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        fi
    done
    
    # Indent public key for Swift multi-line string (8 spaces)
    local indented_key=$(echo "$PUBLIC_KEY" | sed 's/^/        /')
    
    cat > /tmp/swift_config.txt << EOF
    // BUILD_CONFIG_START - Auto-generated by build script, DO NOT EDIT MANUALLY
    /// Get built-in URL list
    /// These URLs are generated during build from build_config.json
    static func getBuiltinURLs() -> [String] {
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
    // BUILD_CONFIG_END
EOF
}

generate_kotlin_config() {
    local urls_array=""
    local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    
    for i in $(seq 0 $((url_count - 1))); do
        local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i])" 2>/dev/null || echo "")
        if [ -n "$url" ]; then
            urls_array="$urls_array            \"$url\""
            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        fi
    done
    
    cat > /tmp/kotlin_config.txt << EOF
    // BUILD_CONFIG_START - Auto-generated by build script, DO NOT EDIT MANUALLY
    /**
     * Get built-in URL list
     * These URLs are generated during build from build_config.json
     */
    fun getBuiltinURLs(): List<String> {
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
    // BUILD_CONFIG_END
EOF
}

generate_arkts_config() {
    local urls_array=""
    local url_count=$(echo "$URLS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
    
    for i in $(seq 0 $((url_count - 1))); do
        local url=$(echo "$URLS" | python3 -c "import json,sys; print(json.load(sys.stdin)[$i])" 2>/dev/null || echo "")
        if [ -n "$url" ]; then
            urls_array="$urls_array      '$url'"
            if [ $i -lt $((url_count - 1)) ]; then
                urls_array="$urls_array,
"
            fi
        fi
    done
    
    cat > /tmp/arkts_config.txt << EOF
  // BUILD_CONFIG_START - Auto-generated by build script, DO NOT EDIT MANUALLY
  /**
   * Get built-in URL list
   * These URLs are generated during build from build_config.json
   */
  static getBuiltinURLs(): string[] {
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
  // BUILD_CONFIG_END
EOF
}

# ============================================================================
# Update Config Files
# ============================================================================

update_config_file() {
    local config_file="$1"
    local temp_config="$2"
    
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
}

# ============================================================================
# Build Functions
# ============================================================================

build_ios() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Cleaning iOS/macOS..."
    else
        echo "📱 Building iOS/macOS..."
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd ios-macos
    
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Removing build artifacts..."
        swift package clean
        rm -rf .build
        echo "✅ iOS/macOS clean complete"
        return 0
    fi
    
    generate_swift_config
    update_config_file "Sources/PassGFW/Config.swift" "/tmp/swift_config.txt"
    
    swift build -c release
    echo "✅ iOS/macOS build complete"
    echo "📦 Output: $(pwd)/.build/release/"
}

build_macos() {
    # macOS uses the same build as iOS (Swift Package supports both)
    build_ios
}

build_android() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Cleaning Android..."
    else
        echo "🤖 Building Android..."
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd android
    
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Removing build artifacts..."
        ./gradlew clean
        echo "✅ Android clean complete"
        return 0
    fi
    
    generate_kotlin_config
    update_config_file "passgfw/src/main/kotlin/com/passgfw/Config.kt" "/tmp/kotlin_config.txt"
    
    ./gradlew :passgfw:assembleRelease
    
    echo "✅ Android build complete"
    echo "📦 Output: $(pwd)/passgfw/build/outputs/aar/"
}

build_harmony() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Cleaning HarmonyOS..."
    else
        echo "🔷 Building HarmonyOS..."
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd harmony
    
    if [ "$CLEAN_BUILD" = true ]; then
        echo "🧹 Removing build artifacts..."
        rm -rf entry/build .hvigor build
        echo "✅ HarmonyOS clean complete"
        return 0
    fi
    
    generate_arkts_config
    update_config_file "entry/src/main/ets/passgfw/Config.ets" "/tmp/arkts_config.txt"
    
    echo "⚠️  HarmonyOS requires DevEco Studio to build"
    echo "   Config file updated, please build in DevEco Studio"
    
    echo "✅ HarmonyOS config updated"
}

# ============================================================================
# Main Build Logic
# ============================================================================

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
        build_ios
        echo ""
        build_macos
        echo ""
        build_android
        echo ""
        build_harmony
        ;;
esac

# ============================================================================
# Cleanup
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 Cleaning up temporary files..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Cleanup temp files
rm -f /tmp/swift_config.txt /tmp/kotlin_config.txt /tmp/arkts_config.txt

echo "✅ Cleanup complete"
echo ""

if [ "$CLEAN_BUILD" = false ]; then
    echo "📝 Note: Config files have been updated with URLs from build_config.json"
    echo "   This is normal - these files should contain your real configuration."
    echo ""
fi

echo "╔══════════════════════════════════════════════════════════════════╗"
if [ "$CLEAN_BUILD" = true ]; then
    echo "║   ✅ Clean Complete!                                             ║"
else
    echo "║   🎉 Build Complete!                                             ║"
fi
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

