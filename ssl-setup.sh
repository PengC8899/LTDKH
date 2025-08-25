#!/bin/bash

# SSL Certificate Setup Script for 7575.PRO
# This script automates Let's Encrypt SSL certificate setup

set -e

# Configuration
DOMAIN="7575.PRO"
EMAIL="admin@7575.PRO"  # Change this to your email
WEBROOT="/var/www/certbot"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== SSL Certificate Setup for ${DOMAIN} ===${NC}"

# Check if domain is accessible
echo -e "${YELLOW}Checking domain accessibility...${NC}"
if ! curl -s --connect-timeout 10 "http://${DOMAIN}" > /dev/null; then
    echo -e "${RED}Warning: Domain ${DOMAIN} is not accessible. Please ensure:${NC}"
    echo "1. DNS is properly configured"
    echo "2. Domain points to this server's IP"
    echo "3. Port 80 is open and accessible"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create webroot directory
echo -e "${YELLOW}Creating webroot directory...${NC}"
sudo mkdir -p "$WEBROOT"
sudo chown -R www-data:www-data "$WEBROOT" 2>/dev/null || sudo chown -R nginx:nginx "$WEBROOT" 2>/dev/null || true

# Create initial nginx config for challenge
echo -e "${YELLOW}Creating initial Nginx configuration...${NC}"
sudo tee /etc/nginx/sites-available/default > /dev/null <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root ${WEBROOT};
    }
    
    location / {
        return 200 'SSL setup in progress...';
        add_header Content-Type text/plain;
    }
}
EOF

# Test and reload nginx
echo -e "${YELLOW}Testing Nginx configuration...${NC}"
sudo nginx -t
sudo systemctl reload nginx

# Install certbot if not present
if ! command -v certbot &> /dev/null; then
    echo -e "${YELLOW}Installing Certbot...${NC}"
    sudo apt update
    sudo apt install -y certbot python3-certbot-nginx
fi

# Obtain SSL certificate
echo -e "${YELLOW}Obtaining SSL certificate for ${DOMAIN}...${NC}"
sudo certbot certonly \
    --webroot \
    --webroot-path="$WEBROOT" \
    --email="$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --domains="$DOMAIN,www.$DOMAIN" \
    --non-interactive

if [ $? -eq 0 ]; then
    echo -e "${GREEN}SSL certificate obtained successfully!${NC}"
else
    echo -e "${RED}Failed to obtain SSL certificate${NC}"
    exit 1
fi

# Set up automatic renewal
echo -e "${YELLOW}Setting up automatic SSL renewal...${NC}"

# Create renewal script
sudo tee /usr/local/bin/certbot-renew.sh > /dev/null <<EOF
#!/bin/bash
/usr/bin/certbot renew --quiet
/usr/bin/systemctl reload nginx
EOF

sudo chmod +x /usr/local/bin/certbot-renew.sh

# Add cron job for renewal (runs twice daily)
(sudo crontab -l 2>/dev/null; echo "0 */12 * * * /usr/local/bin/certbot-renew.sh") | sudo crontab -

echo -e "${GREEN}SSL certificate setup completed!${NC}"
echo -e "${GREEN}Certificate location: /etc/letsencrypt/live/${DOMAIN}/${NC}"
echo -e "${GREEN}Automatic renewal configured via cron${NC}"

# Test renewal
echo -e "${YELLOW}Testing certificate renewal...${NC}"
sudo certbot renew --dry-run

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Certificate renewal test passed!${NC}"
else
    echo -e "${YELLOW}Certificate renewal test failed, but certificate is still valid${NC}"
fi

echo -e "${GREEN}=== SSL Setup Complete ===${NC}"
echo "Next steps:"
echo "1. Update your Nginx configuration to use SSL"
echo "2. Restart your Docker services"
echo "3. Test HTTPS access to your domain"