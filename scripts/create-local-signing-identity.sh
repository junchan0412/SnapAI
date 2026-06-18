#!/bin/bash
# Create a stable local code-signing identity for SnapAI releases.
#
# This does not require an Apple Developer account. It creates a self-signed
# certificate in the user's login keychain so repeated builds can be signed with
# the same identity instead of a new ad-hoc CDHash each time.
set -euo pipefail

IDENTITY_NAME="${1:-SnapAI Local Signing}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v | grep -F "\"${IDENTITY_NAME}\"" >/dev/null; then
  echo "Signing identity already exists: ${IDENTITY_NAME}"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
P12_PASSWORD="snapai-local-signing"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/openssl.cnf" <<EOF
[ req ]
prompt = no
default_bits = 2048
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[ dn ]
CN = ${IDENTITY_NAME}

[ codesign_ext ]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

echo "==> Creating self-signed code-signing certificate: ${IDENTITY_NAME}"
openssl req -new -x509 -nodes -days 3650 \
  -config "${TMP_DIR}/openssl.cnf" \
  -keyout "${TMP_DIR}/identity.key" \
  -out "${TMP_DIR}/identity.crt" >/dev/null 2>&1

openssl pkcs12 -legacy -export \
  -inkey "${TMP_DIR}/identity.key" \
  -in "${TMP_DIR}/identity.crt" \
  -name "${IDENTITY_NAME}" \
  -out "${TMP_DIR}/identity.p12" \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

echo "==> Importing identity into login keychain"
security import "${TMP_DIR}/identity.p12" \
  -k "${KEYCHAIN}" \
  -P "${P12_PASSWORD}" \
  -T /usr/bin/codesign >/dev/null

echo "==> Trusting certificate for local code signing"
security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "${KEYCHAIN}" \
  "${TMP_DIR}/identity.crt" >/dev/null

echo "==> Verifying identity"
security find-identity -p codesigning -v | grep -F "\"${IDENTITY_NAME}\""
echo ""
echo "Done. Future builds will use this identity automatically, or explicitly with:"
echo "  CODESIGN_IDENTITY=\"${IDENTITY_NAME}\" ./build.sh"
