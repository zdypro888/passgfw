#!/bin/bash

###############################################################################
# PassGFW iOS Build Script
# Smart, automatic, foolproof build script for iOS platform
###############################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build-ios"

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
    echo "║         PassGFW iOS Build Script (Foolproof)              ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed"
        return 1
    fi
    return 0
}

###############################################################################
# Environment Checks
###############################################################################

check_environment() {
    log_info "Checking build environment..."
    
    # Check CMake
    if ! check_command cmake; then
        log_error "CMake is required but not installed"
        log_info "Install: brew install cmake"
        exit 1
    fi
    log_success "CMake: $(cmake --version | head -1)"
    
    # Check Xcode
    if ! check_command xcodebuild; then
        log_error "Xcode is required but not installed"
        log_info "Install from Mac App Store"
        exit 1
    fi
    log_success "Xcode: $(xcodebuild -version | head -1)"
    
    # Check Xcode Command Line Tools
    if ! xcode-select -p &> /dev/null; then
        log_error "Xcode Command Line Tools not installed"
        log_info "Install: xcode-select --install"
        exit 1
    fi
    log_success "Xcode Command Line Tools: $(xcode-select -p)"
    
    # Check if on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script must run on macOS"
        exit 1
    fi
    log_success "Platform: macOS $(sw_vers -productVersion)"
    
    echo ""
}

###############################################################################
# Build Configuration
###############################################################################

configure_build() {
    log_info "Configuring CMake for iOS..."
    
    cd "$PROJECT_ROOT"
    
    # Clean extended attributes from entire project BEFORE building
    log_info "Cleaning extended attributes from project..."
    xattr -cr . 2>/dev/null || true
    
    # Clean old build directory
    if [ -d "$BUILD_DIR" ]; then
        log_warning "Removing old build directory..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Configure with CMake
    # Note: CMAKE_BUILD_TYPE is not used with Xcode generator
    # Build type is controlled by xcodebuild -configuration flag
    cmake -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
        -DCMAKE_OSX_ARCHITECTURES="arm64;arm64e" \
        -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
        .. || {
        log_error "CMake configuration failed"
        exit 1
    }
    
    log_success "CMake configuration completed"
    echo ""
}

###############################################################################
# Build for Device
###############################################################################

build_device() {
    log_info "Building for iOS device (arm64)..."
    
    cd "$BUILD_DIR"
    
    xcodebuild \
        -configuration Release \
        -sdk iphoneos \
        -quiet \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build || {
        log_error "Build failed for iOS device"
        log_info "Check build logs above for details"
        exit 1
    }
    
    # Clean extended attributes from built framework
    log_info "Cleaning framework attributes..."
    xattr -cr "$BUILD_DIR/Release-iphoneos" 2>/dev/null || true
    
    log_success "Built for iOS device"
}

###############################################################################
# Build for Simulator (Optional)
###############################################################################

build_simulator() {
    log_info "Building for iOS Simulator (x86_64, arm64)..."
    
    cd "$BUILD_DIR"
    
    xcodebuild \
        -configuration Release \
        -sdk iphonesimulator \
        -quiet \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build || {
        log_warning "Build failed for iOS Simulator (this is optional)"
        return 1
    }
    
    # Clean extended attributes from built framework
    log_info "Cleaning simulator framework attributes..."
    xattr -cr "$BUILD_DIR/Release-iphonesimulator" 2>/dev/null || true
    
    log_success "Built for iOS Simulator"
}

###############################################################################
# Create Universal Framework (Optional)
###############################################################################

create_universal_framework() {
    log_info "Creating universal framework..."
    
    local DEVICE_FRAMEWORK="$BUILD_DIR/Release-iphoneos/passgfw_client.framework"
    local SIMULATOR_FRAMEWORK="$BUILD_DIR/Release-iphonesimulator/passgfw_client.framework"
    local UNIVERSAL_FRAMEWORK="$BUILD_DIR/passgfw_client.xcframework"
    
    # Check if both frameworks exist
    if [ ! -d "$DEVICE_FRAMEWORK" ] || [ ! -d "$SIMULATOR_FRAMEWORK" ]; then
        log_warning "Skipping universal framework (simulator build not available)"
        return 0
    fi
    
    # Remove old xcframework
    if [ -d "$UNIVERSAL_FRAMEWORK" ]; then
        rm -rf "$UNIVERSAL_FRAMEWORK"
    fi
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -framework "$DEVICE_FRAMEWORK" \
        -framework "$SIMULATOR_FRAMEWORK" \
        -output "$UNIVERSAL_FRAMEWORK" || {
        log_warning "Failed to create XCFramework"
        return 1
    }
    
    log_success "Universal framework created: $UNIVERSAL_FRAMEWORK"
}

###############################################################################
# Show Results
###############################################################################

show_results() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                    Build Completed                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Device framework
    local DEVICE_FRAMEWORK="$BUILD_DIR/Release-iphoneos/passgfw_client.framework"
    if [ -d "$DEVICE_FRAMEWORK" ]; then
        local SIZE=$(du -sh "$DEVICE_FRAMEWORK/passgfw_client" | cut -f1)
        log_success "iOS Device Framework:"
        echo "  📦 Path: $DEVICE_FRAMEWORK"
        echo "  📏 Size: $SIZE"
        echo "  🏗️  Arch: $(lipo -info "$DEVICE_FRAMEWORK/passgfw_client" 2>/dev/null | cut -d: -f3 || echo "arm64")"
    fi
    
    # Simulator framework
    local SIMULATOR_FRAMEWORK="$BUILD_DIR/Release-iphonesimulator/passgfw_client.framework"
    if [ -d "$SIMULATOR_FRAMEWORK" ]; then
        log_success "iOS Simulator Framework:"
        echo "  📦 Path: $SIMULATOR_FRAMEWORK"
    fi
    
    # XCFramework
    local XCFRAMEWORK="$BUILD_DIR/passgfw_client.xcframework"
    if [ -d "$XCFRAMEWORK" ]; then
        log_success "Universal XCFramework:"
        echo "  📦 Path: $XCFRAMEWORK"
        echo "  ✅ Supports both device and simulator"
    fi
    
    echo ""
    log_info "Integration Instructions:"
    echo "  1. Drag '$DEVICE_FRAMEWORK' into your Xcode project"
    echo "  2. Or use XCFramework: '$XCFRAMEWORK'"
    echo "  3. In Build Settings, add '-ObjC' to 'Other Linker Flags'"
    echo "  4. Import in your code: #import <passgfw_client/passgfw.h>"
    echo ""
}

###############################################################################
# Main
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
    
    # Configure
    configure_build
    
    # Build for device (required)
    build_device
    
    # Build for simulator (optional)
    build_simulator || true
    
    # Create universal framework (optional)
    create_universal_framework || true
    
    # Show results
    show_results
    
    log_success "All done! 🎉"
}

# Run main function
main "$@"

