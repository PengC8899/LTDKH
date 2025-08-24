#!/bin/bash

# LTDKH Bot VPS Deployment Script
# Usage: ./deploy.sh [--update]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="ltdkh-bot"
DOMAIN="7577.bet"
APP_DIR="/opt/$APP_NAME"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
SERVICE_NAME="$APP_NAME"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update system
    apt update && apt upgrade -y
    
    # Install required packages
    apt install -y \
        docker.io \
        docker-compose \
        nginx \
        certbot \
        python3-certbot-nginx \
        curl \
        git \
        ufw
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group
    usermod -aG docker $USER
    
    log_success "Dependencies installed successfully"
}

setup_firewall() {
    log_info "Configuring firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured successfully"
}

clone_repository() {
    log_info "Cloning repository..."
    
    # Create app directory
    mkdir -p $APP_DIR
    cd $APP_DIR
    
    # Clone repository
    if [[ "$1" == "--update" ]]; then
        log_info "Updating existing repository..."
        git pull origin main
    else
        git clone https://github.com/PengC8899/LTDKH.git .
    fi
    
    log_success "Repository cloned/updated successfully"
}

setup_environment() {
    log_info "Setting up environment..."
    
    # Copy production environment file
    if [[ ! -f ".env.prod" ]]; then
        log_error ".env.prod file not found. Please create it with your configuration."
        exit 1
    fi
    
    # Set proper permissions
    chmod 600 .env.prod
    
    log_success "Environment configured successfully"
}

setup_ssl() {
    log_info "Setting up SSL certificate..."
    
    # Stop nginx temporarily
    systemctl stop nginx
    
    # Obtain SSL certificate
    certbot certonly --standalone -d $DOMAIN -d www.$DOMAIN --agree-tos --no-eff-email --email admin@$DOMAIN
    
    log_success "SSL certificate obtained successfully"
}

setup_nginx() {
    log_info "Configuring Nginx..."
    
    # Copy nginx configuration
    cp nginx.conf $NGINX_CONF
    
    # Enable site
    ln -sf $NGINX_CONF $NGINX_ENABLED
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t
    
    # Start and enable nginx
    systemctl start nginx
    systemctl enable nginx
    
    log_success "Nginx configured successfully"
}

setup_systemd_service() {
    log_info "Setting up systemd service..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=LTDKH Bot Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker-compose -f docker-compose.prod.yml down
TimeoutStartSec=0
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    log_success "Systemd service configured successfully"
}

start_application() {
    log_info "Starting application..."
    
    # Build and start containers
    docker-compose -f docker-compose.prod.yml build
    docker-compose -f docker-compose.prod.yml up -d
    
    # Start systemd service
    systemctl start $SERVICE_NAME
    
    log_success "Application started successfully"
}

setup_ssl_renewal() {
    log_info "Setting up SSL certificate auto-renewal..."
    
    # Create renewal script
    cat > /usr/local/bin/renew-ssl.sh << 'EOF'
#!/bin/bash
certbot renew --quiet --nginx
systemctl reload nginx
EOF
    
    chmod +x /usr/local/bin/renew-ssl.sh
    
    # Add cron job for renewal
    echo "0 3 * * * root /usr/local/bin/renew-ssl.sh" > /etc/cron.d/ssl-renewal
    
    log_success "SSL auto-renewal configured successfully"
}

show_status() {
    log_info "Deployment Status:"
    echo "=========================================="
    echo "Domain: https://$DOMAIN"
    echo "Application Directory: $APP_DIR"
    echo "Service Status: $(systemctl is-active $SERVICE_NAME)"
    echo "Docker Containers:"
    docker-compose -f docker-compose.prod.yml ps
    echo "=========================================="
    
    log_info "Testing application..."
    sleep 10
    
    if curl -f -s https://$DOMAIN/health > /dev/null; then
        log_success "Application is running and healthy!"
        log_success "Visit: https://$DOMAIN"
    else
        log_warning "Application might not be fully ready yet. Please check logs:"
        echo "  docker-compose -f $APP_DIR/docker-compose.prod.yml logs"
    fi
}

# Main deployment function
main() {
    log_info "Starting LTDKH Bot deployment..."
    
    check_root
    
    if [[ "$1" == "--update" ]]; then
        log_info "Running update deployment..."
        cd $APP_DIR
        clone_repository --update
        docker-compose -f docker-compose.prod.yml build
        systemctl restart $SERVICE_NAME
        show_status
    else
        log_info "Running full deployment..."
        install_dependencies
        setup_firewall
        clone_repository
        setup_environment
        setup_ssl
        setup_nginx
        setup_systemd_service
        start_application
        setup_ssl_renewal
        show_status
    fi
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"