#!/bin/bash

# Build PassGFW Client for macOS
# Outputs: Universal Binary (arm64 + x86_64)

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          PassGFW Client - macOS Build Script              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Step 1: Check prerequisites
print_step "Checking Prerequisites"

if ! command -v cmake &> /dev/null; then
    print_error "CMake not found. Install: brew install cmake"
fi
print_info "CMake found: $(cmake --version | head -1)"

if ! command -v xcodebuild &> /dev/null; then
    print_error "Xcode not found. Install from App Store"
fi
print_info "Xcode found: $(xcodebuild -version | head -1)"

# Step 2: Check and generate keys
print_step "Checking RSA Keys"

PRIVATE_KEY="$PROJECT_ROOT/keys/private_key.pem"
PUBLIC_KEY="$PROJECT_ROOT/keys/public_key.pem"

if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    print_info "Keys not found, generating..."
    "$SCRIPT_DIR/generate_keys.sh"
else
    print_info "Keys found"
fi

# Step 3: Embed public key
print_step "Embedding Public Key"

"$SCRIPT_DIR/embed_public_key.sh"
print_success "Public key embedded"

# Step 4: Build for arm64 (Apple Silicon)
print_step "Building for macOS ARM64 (Apple Silicon)"

BUILD_DIR_ARM64="$PROJECT_ROOT/build-macos-arm64"
rm -rf "$BUILD_DIR_ARM64"
mkdir -p "$BUILD_DIR_ARM64"

cd "$BUILD_DIR_ARM64"

cmake "$PROJECT_ROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -G Xcode

cmake --build . --config Release

print_success "ARM64 build complete"

# Step 5: Build for x86_64 (Intel)
print_step "Building for macOS x86_64 (Intel)"

BUILD_DIR_X86="$PROJECT_ROOT/build-macos-x86_64"
rm -rf "$BUILD_DIR_X86"
mkdir -p "$BUILD_DIR_X86"

cd "$BUILD_DIR_X86"

cmake "$PROJECT_ROOT" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 \
    -DCMAKE_SYSTEM_NAME=Darwin \
    -G Xcode

cmake --build . --config Release

print_success "x86_64 build complete"

# Step 6: Create Universal Binary
print_step "Creating Universal Binary"

UNIVERSAL_DIR="$PROJECT_ROOT/build-macos"
rm -rf "$UNIVERSAL_DIR"
mkdir -p "$UNIVERSAL_DIR/lib"
mkdir -p "$UNIVERSAL_DIR/include"

# Find the built libraries
ARM64_LIB=$(find "$BUILD_DIR_ARM64" -name "libpassgfw_client.a" | head -1)
X86_LIB=$(find "$BUILD_DIR_X86" -name "libpassgfw_client.a" | head -1)

if [ -z "$ARM64_LIB" ]; then
    print_error "ARM64 library not found"
fi

if [ -z "$X86_LIB" ]; then
    print_error "x86_64 library not found"
fi

# Create universal binary with lipo
lipo -create "$ARM64_LIB" "$X86_LIB" \
    -output "$UNIVERSAL_DIR/lib/libpassgfw_client.a"

print_success "Universal binary created"

# Step 7: Copy headers
print_step "Copying Headers"

cp "$PROJECT_ROOT/passgfw.h" "$UNIVERSAL_DIR/include/"
cp "$PROJECT_ROOT/firewall_detector.h" "$UNIVERSAL_DIR/include/"

print_success "Headers copied"

# Step 8: Verify architecture
print_step "Verifying Architecture"

echo ""
lipo -info "$UNIVERSAL_DIR/lib/libpassgfw_client.a"
echo ""

# Show file size
SIZE=$(du -sh "$UNIVERSAL_DIR/lib/libpassgfw_client.a" | cut -f1)
print_info "Library size: $SIZE"

# Step 9: Create pkg-config file
print_step "Creating pkg-config File"

cat > "$UNIVERSAL_DIR/passgfw_client.pc" << EOF
prefix=$UNIVERSAL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: passgfw_client
Description: PassGFW Client Library for macOS
Version: 1.0.2
Libs: -L\${libdir} -lpassgfw_client
Cflags: -I\${includedir}
EOF

print_success "pkg-config file created"

# Step 10: Create test program
print_step "Creating Test Program"

cat > "$UNIVERSAL_DIR/test.c" << 'EOF'
#include <stdio.h>
#include "passgfw.h"

int main() {
    printf("PassGFW Client Test\n");
    printf("==================\n\n");
    
    // Create detector
    PassGFWDetector* detector = passgfw_create();
    if (!detector) {
        printf("❌ Failed to create detector\n");
        return 1;
    }
    printf("✅ Detector created\n");
    
    // Note: passgfw_get_final_server() is blocking and will loop forever
    // For testing, we just verify the API is accessible
    
    // Clean up
    passgfw_destroy(detector);
    printf("✅ Detector destroyed\n");
    
    printf("\n✅ Test passed!\n");
    return 0;
}
EOF

# Compile test program
cd "$UNIVERSAL_DIR"
clang test.c -o test \
    -I./include \
    -L./lib \
    -lpassgfw_client \
    -framework Foundation \
    -framework Security \
    -lc++

print_success "Test program compiled"

# Run test
print_step "Running Test"
./test

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   ✅ Build Complete!                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Output:"
echo "   $UNIVERSAL_DIR/lib/libpassgfw_client.a"
echo ""
echo "📁 Structure:"
echo "   build-macos/"
echo "   ├── lib/"
echo "   │   └── libpassgfw_client.a  (Universal Binary)"
echo "   ├── include/"
echo "   │   ├── passgfw.h"
echo "   │   └── firewall_detector.h"
echo "   ├── passgfw_client.pc        (pkg-config)"
echo "   ├── test.c                    (Test source)"
echo "   └── test                      (Test binary)"
echo ""
echo "🏛️  Architectures:"
lipo -info "$UNIVERSAL_DIR/lib/libpassgfw_client.a"
echo ""
echo "📊 Size: $SIZE"
echo ""
echo "🔧 Usage:"
echo ""
echo "   # Link to your project:"
echo "   clang your_app.c -o your_app \\"
echo "       -I$UNIVERSAL_DIR/include \\"
echo "       -L$UNIVERSAL_DIR/lib \\"
echo "       -lpassgfw_client \\"
echo "       -framework Foundation \\"
echo "       -framework Security \\"
echo "       -lc++"
echo ""
echo "   # Or use pkg-config:"
echo "   export PKG_CONFIG_PATH=$UNIVERSAL_DIR"
echo "   clang your_app.c -o your_app \`pkg-config --cflags --libs passgfw_client\` \\"
echo "       -framework Foundation -framework Security -lc++"
echo ""
echo "✅ Build successful!"
echo ""

