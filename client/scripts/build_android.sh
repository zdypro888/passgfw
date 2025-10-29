#!/bin/bash

###############################################################################
# PassGFW Android Build Script
# Smart, automatic, foolproof build script for Android platform
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
BUILD_DIR="$PROJECT_ROOT/build-android"
NDK_VERSION="26.1.10909125"

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
    echo "║       PassGFW Android Build Script (Foolproof)            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

###############################################################################
# Find Android NDK
###############################################################################

find_android_ndk() {
    log_info "Looking for Android NDK..."
    
    # Check environment variable
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        export NDK_PATH="$ANDROID_NDK_HOME"
        log_success "Found NDK: $NDK_PATH"
        return 0
    fi
    
    if [ -n "$ANDROID_NDK" ] && [ -d "$ANDROID_NDK" ]; then
        export NDK_PATH="$ANDROID_NDK"
        log_success "Found NDK: $NDK_PATH"
        return 0
    fi
    
    # Common NDK locations
    local NDK_LOCATIONS=(
        "$HOME/Library/Android/sdk/ndk/$NDK_VERSION"
        "$HOME/Android/Sdk/ndk/$NDK_VERSION"
        "/usr/local/android-sdk/ndk/$NDK_VERSION"
        "$HOME/Library/Android/sdk/ndk-bundle"
    )
    
    for location in "${NDK_LOCATIONS[@]}"; do
        if [ -d "$location" ]; then
            export NDK_PATH="$location"
            log_success "Found NDK: $NDK_PATH"
            return 0
        fi
    done
    
    log_error "Android NDK not found"
    log_info "Please install Android NDK:"
    log_info "  1. Open Android Studio"
    log_info "  2. Go to Tools -> SDK Manager"
    log_info "  3. Select 'SDK Tools' tab"
    log_info "  4. Check 'NDK (Side by side)'"
    log_info "  5. Click Apply"
    log_info ""
    log_info "Or set environment variable:"
    log_info "  export ANDROID_NDK_HOME=/path/to/ndk"
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
    
    # Find NDK
    find_android_ndk
    
    # Check toolchain
    local TOOLCHAIN="$NDK_PATH/build/cmake/android.toolchain.cmake"
    if [ ! -f "$TOOLCHAIN" ]; then
        log_error "Android NDK toolchain not found at: $TOOLCHAIN"
        exit 1
    fi
    log_success "NDK Toolchain: $TOOLCHAIN"
    
    echo ""
}

###############################################################################
# Build for Android
###############################################################################

build_android() {
    local ABI=$1
    local API_LEVEL=$2
    
    log_info "Building for Android $ABI (API $API_LEVEL)..."
    
    local BUILD_ABI_DIR="$BUILD_DIR/$ABI"
    
    cd "$PROJECT_ROOT"
    
    # Create build directory
    mkdir -p "$BUILD_ABI_DIR"
    cd "$BUILD_ABI_DIR"
    
    # Configure
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI=$ABI \
        -DANDROID_PLATFORM=android-$API_LEVEL \
        -DCMAKE_BUILD_TYPE=Release \
        -DANDROID_STL=c++_static \
        ../.. || {
        log_error "CMake configuration failed for $ABI"
        return 1
    }
    
    # Build
    cmake --build . --config Release || {
        log_error "Build failed for $ABI"
        return 1
    }
    
    log_success "Built for $ABI"
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
    
    # Build for common ABIs
    local ABIS=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")
    local API_LEVEL=21
    
    log_info "Building for ABIs: ${ABIS[*]}"
    echo ""
    
    local SUCCESS_COUNT=0
    for abi in "${ABIS[@]}"; do
        if build_android "$abi" "$API_LEVEL"; then
            ((SUCCESS_COUNT++))
        fi
    done
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Build Completed                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_success "Built $SUCCESS_COUNT/${#ABIS[@]} architectures"
    echo ""
    
    # Show results
    for abi in "${ABIS[@]}"; do
        local LIB="$BUILD_DIR/$abi/libpassgfw_client.a"
        if [ -f "$LIB" ]; then
            local SIZE=$(du -sh "$LIB" | cut -f1)
            echo "  📦 $abi: $SIZE"
        fi
    done
    
    echo ""
    log_info "Integration Instructions:"
    echo "  1. Copy libraries to your Android project:"
    echo "     app/src/main/jniLibs/<abi>/libpassgfw_client.a"
    echo "  2. Copy Java helper:"
    echo "     platform/android/NetworkHelper.java"
    echo "  3. Create JNI wrapper to call C functions"
    echo ""
    
    log_success "All done! 🎉"
}

# Run main
main "$@"

