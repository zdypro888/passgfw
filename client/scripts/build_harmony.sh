#!/bin/bash

###############################################################################
# PassGFW HarmonyOS Build Script
# Smart, automatic, foolproof build script for HarmonyOS platform
###############################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_ROOT/build-harmony"

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     PassGFW HarmonyOS Build Script (Foolproof)            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

###############################################################################
# Find HarmonyOS SDK
###############################################################################

find_harmony_sdk() {
    log_info "Looking for HarmonyOS SDK..."
    
    # Check environment variable
    if [ -n "$OHOS_SDK_NATIVE" ] && [ -d "$OHOS_SDK_NATIVE" ]; then
        export SDK_PATH="$OHOS_SDK_NATIVE"
        log_success "Found SDK: $SDK_PATH"
        return 0
    fi
    
    if [ -n "$OHOS_NDK_HOME" ] && [ -d "$OHOS_NDK_HOME" ]; then
        export SDK_PATH="$OHOS_NDK_HOME"
        log_success "Found SDK: $SDK_PATH"
        return 0
    fi
    
    # Common SDK locations
    local SDK_LOCATIONS=(
        "$HOME/Library/Huawei/Sdk/openharmony"
        "$HOME/Huawei/Sdk/openharmony"
        "$HOME/HarmonyOS/Sdk"
        "/usr/local/openharmony/sdk"
    )
    
    for location in "${SDK_LOCATIONS[@]}"; do
        if [ -d "$location/native" ]; then
            export SDK_PATH="$location/native"
            log_success "Found SDK: $SDK_PATH"
            return 0
        fi
    done
    
    log_error "HarmonyOS SDK not found"
    log_info "Please install HarmonyOS SDK:"
    log_info "  1. Open DevEco Studio"
    log_info "  2. Go to File -> Settings -> SDK"
    log_info "  3. Install 'Native' component"
    log_info ""
    log_info "Or set environment variable:"
    log_info "  export OHOS_SDK_NATIVE=/path/to/sdk/native"
    exit 1
}

###############################################################################
# Check Environment
###############################################################################

check_environment() {
    log_info "Checking build environment..."
    
    # Check CMake
    if ! command -v cmake &> /dev/null; then
        log_error "CMake is required but not installed"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            log_info "Install: brew install cmake"
        else
            log_info "Install: apt-get install cmake"
        fi
        exit 1
    fi
    log_success "CMake: $(cmake --version | head -1)"
    
    # Find SDK
    find_harmony_sdk
    
    # Check toolchain
    local TOOLCHAIN="$SDK_PATH/build/cmake/ohos.toolchain.cmake"
    if [ ! -f "$TOOLCHAIN" ]; then
        log_error "HarmonyOS toolchain not found at: $TOOLCHAIN"
        exit 1
    fi
    log_success "Toolchain: $TOOLCHAIN"
    
    echo ""
}

###############################################################################
# Build for HarmonyOS
###############################################################################

build_harmony() {
    local ARCH=$1
    local API_LEVEL=${2:-8}
    
    log_info "Building for HarmonyOS $ARCH (API $API_LEVEL)..."
    
    local BUILD_ARCH_DIR="$BUILD_DIR/$ARCH"
    
    cd "$PROJECT_ROOT"
    
    # Create build directory
    mkdir -p "$BUILD_ARCH_DIR"
    cd "$BUILD_ARCH_DIR"
    
    # Find toolchain
    local TOOLCHAIN="$SDK_PATH/build/cmake/ohos.toolchain.cmake"
    
    # Configure
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DOHOS_ARCH=$ARCH \
        -DOHOS_PLATFORM=OHOS \
        -DCMAKE_BUILD_TYPE=Release \
        -DHARMONY=ON \
        ../.. || {
        log_error "CMake configuration failed for $ARCH"
        return 1
    }
    
    # Build
    cmake --build . --config Release || {
        log_error "Build failed for $ARCH"
        return 1
    }
    
    log_success "Built for $ARCH"
    return 0
}

###############################################################################
# Main Build Process
###############################################################################

main() {
    print_header
    
    # Check environment
    check_environment
    
    # Pre-build setup (keys, embedding, encryption)
    log_info "Running pre-build setup..."
    "$SCRIPT_DIR/prebuild.sh" || {
        log_error "Pre-build setup failed"
        exit 1
    }
    log_success "Pre-build setup complete"
    echo ""
    
    # Clean old build
    if [ -d "$BUILD_DIR" ]; then
        log_warning "Removing old build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Build for common architectures
    local ARCHS=("arm64-v8a" "armeabi-v7a")
    local API_LEVEL=8
    
    log_info "Building for architectures: ${ARCHS[*]}"
    echo ""
    
    local SUCCESS_COUNT=0
    for arch in "${ARCHS[@]}"; do
        if build_harmony "$arch" "$API_LEVEL"; then
            ((SUCCESS_COUNT++))
        fi
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Build Completed                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ $SUCCESS_COUNT -eq 0 ]; then
        log_error "All builds failed"
        exit 1
    fi
    
    log_success "Built $SUCCESS_COUNT/${#ARCHS[@]} architectures"
    echo ""
    
    # Show results
    for arch in "${ARCHS[@]}"; do
        local LIB="$BUILD_DIR/$arch/libpassgfw_client.a"
        if [ -f "$LIB" ]; then
            local SIZE=$(du -sh "$LIB" | cut -f1)
            echo "  📦 $arch: $SIZE"
        fi
    done
    
    echo ""
    log_info "Integration Instructions:"
    echo "  1. Copy libraries to your HarmonyOS project:"
    echo "     entry/libs/<arch>/libpassgfw_client.a"
    echo "  2. Copy ArkTS helper:"
    echo "     platform/harmony/network_helper.ets"
    echo "  3. Create NAPI wrapper to call C functions"
    echo "  4. Import in your ArkTS code"
    echo ""
    
    log_warning "Note: ArkTS wrapper (network_helper.ets) needs to be completed"
    log_info "This is a framework. Implement NAPI bindings in your HarmonyOS project"
    echo ""
    
    log_success "All done! 🎉"
}

# Run main
main "$@"

