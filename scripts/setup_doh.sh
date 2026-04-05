#!/bin/bash
# setup_doh.sh — Configure DNS-over-HTTPS on a WraithGate node
# Usage: bash setup_doh.sh <HOSTNAME> <ADGUARD_PORT>
# Example: bash setup_doh.sh vpn-eu1.katafract.com 3000
#
# Run on each node:
#   ssh -i ~/.ssh/id_ed25519 root@178.104.49.211 'bash -s' < setup_doh.sh vpn-eu1.katafract.com 3000
#   ssh -i ~/.ssh/id_ed25519 root@204.168.224.243 'bash -s' < setup_doh.sh vpn-eu2.katafract.com 3000
#   ssh -i ~/.ssh/id_ed25519 root@5.223.52.75    'bash -s' < setup_doh.sh vpn-sin.katafract.com 3000
#   ssh -i ~/.ssh/id_ed25519 root@85.239.240.208  'bash -s' < setup_doh.sh vpn-us.katafract.com 3001

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <HOSTNAME> <ADGUARD_PORT>" >&2
    echo "Example: $0 vpn-eu1.katafract.com 3000" >&2
    exit 1
fi

HOSTNAME="$1"
ADGUARD_PORT="$2"

if [[ ! "$HOSTNAME" =~ ^[a-z0-9.-]+$ ]]; then
    echo "Error: Invalid hostname format" >&2
    exit 1
fi

if [[ ! "$ADGUARD_PORT" =~ ^(3000|3001)$ ]]; then
    echo "Error: ADGUARD_PORT must be 3000 or 3001" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

# Install dependencies
apt-get update -qq
apt-get install -y -qq nginx certbot python3-certbot-nginx > /dev/null 2>&1

# Create nginx site config
NGINX_CONF="/etc/nginx/sites-available/$HOSTNAME"
cat > "$NGINX_CONF" << NGINX_EOF
server {
    listen 80;
    listen [::]:80;
    server_name $HOSTNAME;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $HOSTNAME;

    ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location /dns-query {
        proxy_pass http://127.0.0.1:$ADGUARD_PORT/dns-query;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }

    location / {
        return 404;
    }
}
NGINX_EOF

# Enable site
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$HOSTNAME"
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test config (HTTP only first, to allow certbot)
nginx -t
systemctl reload nginx

# Obtain certificate
mkdir -p /var/www/certbot
certbot certonly \
    --webroot \
    --webroot-path /var/www/certbot \
    --non-interactive \
    --agree-tos \
    --email christian@katafract.com \
    --domain "$HOSTNAME"

# Reload with SSL
systemctl reload nginx

# Auto-renewal
systemctl enable certbot.timer 2>/dev/null || true
systemctl start certbot.timer 2>/dev/null || true

echo "Done. Endpoint: https://$HOSTNAME/dns-query"
