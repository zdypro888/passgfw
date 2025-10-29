#!/bin/bash

###############################################################################
# PassGFW - Pre-build Setup
# Common pre-build steps for all platforms:
#   1. Generate RSA keys if not exist
#   2. Embed public key into config.cpp
#   3. Encrypt config.cpp to config_encrypted.cpp
###############################################################################

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_step() {
    echo -e "${BLUE}==>${NC} ${GREEN}$1${NC}"
}

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

###############################################################################
# Main Pre-build Steps
###############################################################################

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           PassGFW - Pre-build Setup                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

cd "$CLIENT_ROOT"

# Step 1: Check and generate keys
log_step "Step 1: Checking RSA Keys"

PRIVATE_KEY="$CLIENT_ROOT/keys/private_key.pem"
PUBLIC_KEY="$CLIENT_ROOT/keys/public_key.pem"

if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ]; then
    log_info "Keys not found, generating..."
    "$SCRIPT_DIR/generate_keys.sh" || log_error "Key generation failed"
else
    log_info "Keys found"
fi
log_success "RSA keys ready"

# Step 2: Embed public key
log_step "Step 2: Embedding Public Key"

"$SCRIPT_DIR/embed_public_key.sh" || log_error "Public key embedding failed"
log_success "Public key embedded"

# Step 3: Encrypt config (optional, for obfuscation)
log_step "Step 3: Encrypting Configuration"

if [ -f "$SCRIPT_DIR/encrypt_config.sh" ]; then
    "$SCRIPT_DIR/encrypt_config.sh" || log_error "Configuration encryption failed"
    log_success "Configuration encrypted"
else
    log_info "Encryption script not found, using plaintext config"
fi

echo ""
log_success "Pre-build setup complete!"
echo ""

