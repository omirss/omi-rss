#!/bin/bash

# SSL Certificate Setup Script for Omi RSS
# Supports both Let's Encrypt and self-signed certificates

set -e

DOMAIN=${1:-localhost}
SSL_DIR="./nginx/ssl"
CERT_TYPE=${2:-letsencrypt} # letsencrypt or self-signed

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[SSL Setup]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Create SSL directory
mkdir -p "$SSL_DIR"

if [ "$CERT_TYPE" = "letsencrypt" ]; then
    log "Setting up Let's Encrypt certificate for $DOMAIN"
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        error "Certbot is not installed. Please install certbot first."
    fi
    
    # Stop nginx if running
    docker-compose -f docker-compose.prod.yml stop nginx 2>/dev/null || true
    
    # Get certificate
    certbot certonly \
        --standalone \
        --preferred-challenges http \
        --email admin@$DOMAIN \
        --agree-tos \
        --no-eff-email \
        --force-renewal \
        -d $DOMAIN \
        -d www.$DOMAIN
    
    # Copy certificates to SSL directory
    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$SSL_DIR/cert.pem"
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem "$SSL_DIR/key.pem"
    
    # Set up auto-renewal
    cat > /etc/cron.d/certbot-renew << EOF
0 0,12 * * * root certbot renew --quiet --no-self-upgrade --post-hook "docker-compose -f /path/to/docker-compose.prod.yml restart nginx"
EOF
    
    log "Let's Encrypt certificate installed successfully"
    
else
    log "Generating self-signed certificate for $DOMAIN"
    
    # Generate private key
    openssl genrsa -out "$SSL_DIR/key.pem" 2048
    
    # Generate certificate signing request
    openssl req -new -key "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/csr.pem" \
        -subj "/C=US/ST=State/L=City/O=Omi RSS/CN=$DOMAIN"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 \
        -in "$SSL_DIR/csr.pem" \
        -signkey "$SSL_DIR/key.pem" \
        -out "$SSL_DIR/cert.pem"
    
    # Remove CSR
    rm "$SSL_DIR/csr.pem"
    
    log "Self-signed certificate generated successfully"
fi

# Set permissions
chmod 600 "$SSL_DIR/key.pem"
chmod 644 "$SSL_DIR/cert.pem"

# Generate DH parameters for extra security
if [ ! -f "$SSL_DIR/dhparam.pem" ]; then
    log "Generating DH parameters (this may take a while)..."
    openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048
fi

log "SSL setup completed successfully"
log "Certificate files:"
log "  - Certificate: $SSL_DIR/cert.pem"
log "  - Private Key: $SSL_DIR/key.pem"
log "  - DH Params: $SSL_DIR/dhparam.pem"

# Update nginx configuration to include DH params
if [ -f "$SSL_DIR/dhparam.pem" ]; then
    cat >> nginx/conf.d/ssl-params.conf << EOF
# SSL Parameters
ssl_dhparam /etc/nginx/ssl/dhparam.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# Modern configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
EOF
fi