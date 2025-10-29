#!/bin/bash

# PassGFW Debug Setup Script
# Automatically prepares everything needed for debugging

set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         PassGFW Debug Environment Setup                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}==>${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

# Step 1: Build client library
log_info "Building client library for macOS..."
cd client/scripts
./build_macos.sh > /dev/null 2>&1
log_success "Client library built"

# Step 2: Compile debug test program
log_info "Compiling debug test program..."
cd "$PROJECT_ROOT/client/build-macos"

clang -g -O0 ../examples/test_debug.c -o test_debug \
    -I./include -L./lib -lpassgfw_client \
    -framework Foundation -framework Security -lc++

log_success "Debug program compiled: client/build-macos/test_debug"

# Step 3: Compile macOS example
log_info "Compiling macOS example..."
clang -g -O0 ../examples/example_macos.c -o example \
    -I./include -L./lib -lpassgfw_client \
    -framework Foundation -framework Security -lc++

log_success "Example compiled: client/build-macos/example"

# Step 4: Check if server dependencies are installed
log_info "Checking server dependencies..."
cd "$PROJECT_ROOT/server"

if [ -f "go.mod" ]; then
    go mod download > /dev/null 2>&1 || true
    log_success "Server dependencies ready"
fi

# Step 5: Verify keys
log_info "Checking RSA keys..."
if [ -f "$PROJECT_ROOT/client/keys/private_key.pem" ]; then
    log_success "Keys found"
else
    log_warning "Keys not found, generating..."
    cd "$PROJECT_ROOT/client/scripts"
    ./generate_keys.sh
    log_success "Keys generated"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ✅ Debug Environment Ready!                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Files created:"
echo "   ✅ client/build-macos/test_debug (debug program)"
echo "   ✅ client/build-macos/example (example program)"
echo "   ✅ client/build-macos/lib/libpassgfw_client.a (library)"
echo ""
echo "🎯 Next steps:"
echo ""
echo "1️⃣  Start server (in new terminal):"
echo "   cd server && go run main.go"
echo ""
echo "2️⃣  Test debug program:"
echo "   cd client/build-macos"
echo "   ./test_debug"
echo ""
echo "3️⃣  Start debugging in IDE:"
echo "   a. Open client/firewall_detector.cpp"
echo "   b. Set breakpoints (line 85, 120, 145)"
echo "   c. Press F5"
echo "   d. Select '(lldb) Debug PassGFW Client'"
echo ""
echo "📖 Full guide: DEBUG_GUIDE.md"
echo ""
echo "🚀 Happy debugging!"
echo ""

