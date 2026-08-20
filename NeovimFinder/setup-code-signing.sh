#!/usr/bin/env bash

set -euo pipefail

identity_name=${NEOVIM_FINDER_SIGNING_IDENTITY:-Neovim Finder Local Code Signing}
login_keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$login_keychain" 2>/dev/null \
    | grep -F "\"$identity_name\"" >/dev/null; then
    echo "Code-signing identity already exists: $identity_name"
    exit 0
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/neovim-finder-codesign.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
umask 077

private_key="$work_dir/private-key.pem"
certificate="$work_dir/certificate.pem"
archive="$work_dir/identity.p12"
archive_password=$(openssl rand -hex 24)

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
    -keyout "$private_key" -out "$certificate" \
    -subj "/CN=$identity_name/O=Local Development" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,digitalSignature,keyCertSign" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "subjectKeyIdentifier=hash"

openssl pkcs12 -export -inkey "$private_key" -in "$certificate" \
    -name "$identity_name" -out "$archive" -passout "pass:$archive_password"

security import "$archive" -k "$login_keychain" -P "$archive_password" \
    -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$login_keychain" "$certificate"

security find-identity -v -p codesigning "$login_keychain"
echo "Neovim Finder code-signing identity is ready."
