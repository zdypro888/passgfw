#!/bin/bash

# RSA Key Pair Generation Script
# Generates private key and public key for PassGFW
# - Private key: Used by server to decrypt and sign
# - Public key: Embedded in client for encryption and verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KEYS_DIR="${CLIENT_ROOT}/keys"
PRIVATE_KEY="${KEYS_DIR}/private_key.pem"
PUBLIC_KEY="${KEYS_DIR}/public_key.pem"

echo "🔐 PassGFW Key Generation"
echo "=========================="
echo ""

# Create keys directory
mkdir -p "${KEYS_DIR}"

# Check if keys already exist
if [ -f "${PRIVATE_KEY}" ] && [ -f "${PUBLIC_KEY}" ]; then
    echo "⚠️  Keys already exist:"
    echo "   Private: ${PRIVATE_KEY}"
    echo "   Public:  ${PUBLIC_KEY}"
    echo ""
    read -p "Regenerate keys? This will invalidate existing clients! (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "✅ Using existing keys"
        exit 0
    fi
    echo ""
    echo "🔄 Regenerating keys..."
fi

# Generate RSA private key (2048 bits)
echo "📝 Generating RSA private key (2048 bits)..."
openssl genrsa -out "${PRIVATE_KEY}" 2048 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Failed to generate private key"
    exit 1
fi

# Generate public key from private key
echo "📝 Extracting public key..."
openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ Failed to extract public key"
    exit 1
fi

# Set proper permissions
chmod 600 "${PRIVATE_KEY}"
chmod 644 "${PUBLIC_KEY}"

echo ""
echo "✅ Keys generated successfully!"
echo ""
echo "📁 Output:"
echo "   Private Key: ${PRIVATE_KEY}"
echo "   Public Key:  ${PUBLIC_KEY}"
echo ""
echo "🔒 Security Notes:"
echo "   - Private key is for SERVER use only"
echo "   - Public key will be embedded in CLIENT"
echo "   - Keep private key secure and never commit it!"
echo ""

# Display key info
echo "📊 Key Information:"
openssl rsa -in "${PRIVATE_KEY}" -text -noout 2>/dev/null | head -n 1

echo ""
echo "✅ Done!"

