#!/bin/bash

###############################################################################
# PassGFW - Clean Build Artifacts
# Remove all build directories and output files
###############################################################################

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           PassGFW - Clean Build Artifacts                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd "$PROJECT_ROOT"
log_info "Working directory: $PROJECT_ROOT"
echo ""

# Clean iOS
if [ -d "build-ios" ]; then
    log_info "Cleaning iOS build directory..."
    rm -rf build-ios
    log_success "Removed build-ios/"
else
    log_warning "build-ios/ not found, skipping"
fi

# Clean macOS
if [ -d "build-macos" ]; then
    log_info "Cleaning macOS build directory..."
    rm -rf build-macos
    log_success "Removed build-macos/"
fi

if [ -d "build-macos-arm64" ]; then
    log_info "Cleaning macOS ARM64 build directory..."
    rm -rf build-macos-arm64
    log_success "Removed build-macos-arm64/"
fi

if [ -d "build-macos-x86_64" ]; then
    log_info "Cleaning macOS x86_64 build directory..."
    rm -rf build-macos-x86_64
    log_success "Removed build-macos-x86_64/"
fi

# Clean Android
if [ -d "build-android" ]; then
    log_info "Cleaning Android build directory..."
    rm -rf build-android
    log_success "Removed build-android/"
else
    log_warning "build-android/ not found, skipping"
fi

# Clean Harmony
if [ -d "build-harmony" ]; then
    log_info "Cleaning HarmonyOS build directory..."
    rm -rf build-harmony
    log_success "Removed build-harmony/"
else
    log_warning "build-harmony/ not found, skipping"
fi

# Clean output
if [ -d "output" ]; then
    log_info "Cleaning output directory..."
    rm -rf output
    log_success "Removed output/"
fi

# Clean generated encrypted config
if [ -f "config_encrypted.cpp" ]; then
    log_info "Cleaning generated encrypted config..."
    rm -f config_encrypted.cpp
    log_success "Removed config_encrypted.cpp"
fi

# Clean CMake cache files
log_info "Cleaning CMake cache files..."
find . -name "CMakeCache.txt" -delete 2>/dev/null || true
find . -name "CMakeFiles" -type d -exec rm -rf {} + 2>/dev/null || true
find . -name "cmake_install.cmake" -delete 2>/dev/null || true
log_success "CMake cache cleaned"

# Clean Xcode derived data (optional)
if [ -d "*.xcodeproj" ]; then
    log_info "Cleaning Xcode project files..."
    find . -name "*.xcodeproj" -type d -exec rm -rf {} + 2>/dev/null || true
fi

echo ""
log_success "All build artifacts cleaned! 🎉"
echo ""
log_info "Ready to rebuild:"
echo "  ./build_ios.sh      - Build for iOS"
echo "  ./build_macos.sh    - Build for macOS"
echo "  ./build_android.sh  - Build for Android"
echo "  ./build_harmony.sh  - Build for HarmonyOS"
echo ""
