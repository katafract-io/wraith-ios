#!/bin/bash
# sign_mobileconfig.sh
# Signs haven_dns.mobileconfig with the Let's Encrypt cert for connect.katafract.com
# Run as root on artemis where the cert lives.
#
# Usage: bash sign_mobileconfig.sh
# Output: haven_dns_signed.mobileconfig  (deploy to connect.katafract.com)

set -euo pipefail

DOMAIN="connect.katafract.com"
CERT="/etc/letsencrypt/live/$DOMAIN/cert.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
CHAIN="/etc/letsencrypt/live/$DOMAIN/chain.pem"
INPUT="haven_dns.mobileconfig"
OUTPUT="haven_dns_signed.mobileconfig"

if [[ ! -f "$CERT" ]]; then
    echo "Cert not found for $DOMAIN — trying fullchain from another domain"
    DOMAIN="api.katafract.com"
    CERT="/etc/letsencrypt/live/$DOMAIN/cert.pem"
    KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    CHAIN="/etc/letsencrypt/live/$DOMAIN/chain.pem"
fi

openssl smime -sign \
    -in "$INPUT" \
    -out "$OUTPUT" \
    -signer "$CERT" \
    -inkey "$KEY" \
    -certfile "$CHAIN" \
    -outform der \
    -nodetach

echo "Signed: $OUTPUT"
echo "Deploy to: /opt/katafract-platform/apps/client-portal/haven_dns_signed.mobileconfig"
echo ""
echo "Add to connect.katafract.com with a download link:"
echo "  <a href='/haven_dns_signed.mobileconfig'>Install Haven DNS Profile</a>"
