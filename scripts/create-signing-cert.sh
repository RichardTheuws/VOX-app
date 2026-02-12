#!/bin/bash
# create-signing-cert.sh — Create a self-signed code signing certificate for VOX
#
# This certificate allows codesign to sign VOX.app with a consistent identity,
# so macOS TCC (Transparency, Consent, and Control) preserves Accessibility
# permissions across rebuilds. Without this, every rebuild changes the binary's
# CDHash and macOS revokes the AX permission.
#
# Usage:
#   ./scripts/create-signing-cert.sh
#
# You only need to run this ONCE per machine.
# The certificate is stored in your login keychain and valid for 10 years.

set -euo pipefail

CERT_NAME="VOX Developer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TEMP_DIR=$(mktemp -d)

echo "==> Creating self-signed code signing certificate: '${CERT_NAME}'"
echo ""

# Check if certificate already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "    Certificate '${CERT_NAME}' already exists in keychain."
    echo "    To recreate, first delete it from Keychain Access."
    exit 0
fi

# Step 1: Create OpenSSL config for code signing certificate
cat > "${TEMP_DIR}/cert.conf" << 'CERTEOF'
[ req ]
distinguished_name = req_dn
x509_extensions = codesign_ext
prompt = no

[ req_dn ]
CN = VOX Developer
O = VOX

[ codesign_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
CERTEOF

# Step 2: Generate certificate and private key
echo "    Generating RSA 2048-bit certificate (valid 10 years)..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 \
    -nodes \
    -keyout "${TEMP_DIR}/key.pem" \
    -out "${TEMP_DIR}/cert.pem" \
    -config "${TEMP_DIR}/cert.conf" \
    2>/dev/null

# Step 3: Bundle into PKCS12
openssl pkcs12 -export \
    -out "${TEMP_DIR}/cert.p12" \
    -inkey "${TEMP_DIR}/key.pem" \
    -in "${TEMP_DIR}/cert.pem" \
    -passout pass:voxtemp \
    2>/dev/null

# Step 4: Import into login keychain
echo "    Importing into login keychain..."
echo "    (You may be prompted for your macOS login password)"
echo ""
security import "${TEMP_DIR}/cert.p12" \
    -k "$KEYCHAIN" \
    -P voxtemp \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Step 5: Allow codesign to use the certificate without prompting
# This requires the keychain password
echo ""
echo "    Setting key partition list (may prompt for keychain password)..."
security set-key-partition-list -S apple-tool:,apple: -s \
    -k "" "$KEYCHAIN" 2>/dev/null || {
    echo ""
    echo "    NOTE: If codesign prompts 'allow access', click 'Always Allow'."
    echo "    Or re-run with your keychain password:"
    echo "      security set-key-partition-list -S apple-tool:,apple: -s -k 'YOUR_PASSWORD' '$KEYCHAIN'"
}

# Step 6: Clean up temp files
rm -rf "$TEMP_DIR"

# Step 7: Verify
echo ""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> SUCCESS: Certificate '${CERT_NAME}' created and ready for code signing."
    echo ""
    echo "    Now rebuild VOX with: ./scripts/build-app.sh --install"
    echo "    The build script will automatically sign with this certificate."
    echo "    AX permissions will persist across rebuilds!"
else
    echo "==> WARNING: Certificate created but not found in codesigning identities."
    echo "    Try opening Keychain Access and setting the trust for '${CERT_NAME}' to:"
    echo "    'Always Trust' for Code Signing."
    echo ""
    echo "    Steps:"
    echo "    1. Open Keychain Access"
    echo "    2. Find '${CERT_NAME}' in 'login' keychain"
    echo "    3. Double-click → Trust → Code Signing → Always Trust"
    echo "    4. Close and enter password"
fi
