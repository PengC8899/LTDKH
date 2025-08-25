#!/bin/bash

# LTDKH Bot VPS Complete Deployment Script
# This script automates the complete deployment of LTDKH Bot on a VPS
# Domain: 7575.PRO
# Repository: https://github.com/PengC8899/LTDKH.git

set -e

# Configuration
DOMAIN="7575.PRO"
REPO_URL="https://github.com/PengC8899/LTDKH.git"
INSTALL_DIR="/opt/ltdkh-bot"
SERVICE_NAME="ltdkh-bot"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root. Use: sudo $0"
    fi
}

# System information
show_system_info() {
    log "=== System Information ==="
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')"
    echo "Disk: $(df -h / | awk 'NR==2 {print $4" available"}')"
    echo "Domain: $DOMAIN"
    echo "Install Directory: $INSTALL_DIR"
    echo
}

# Update system
update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
    apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
}

# Install Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log "Docker is already installed: $(docker --version)"
        return
    fi
    
    log "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group
    usermod -aG docker $USER
    
    log "Docker installed successfully: $(docker --version)"
}

# Install Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        log "Docker Compose is already installed: $(docker-compose --version)"
        return
    fi
    
    log "Installing Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log "Docker Compose installed successfully: $(docker-compose --version)"
}

# Install Nginx
install_nginx() {
    if command -v nginx &> /dev/null; then
        log "Nginx is already installed: $(nginx -v 2>&1)"
        return
    fi
    
    log "Installing Nginx..."
    apt install -y nginx
    
    # Start and enable Nginx
    systemctl start nginx
    systemctl enable nginx
    
    log "Nginx installed successfully"
}

# Clone repository
clone_repository() {
    log "Cloning LTDKH Bot repository..."
    
    if [ -d "$INSTALL_DIR" ]; then
        warn "Directory $INSTALL_DIR already exists. Backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    log "Repository cloned successfully"
}

# Setup environment
setup_environment() {
    log "Setting up environment configuration..."
    
    cd "$INSTALL_DIR"
    
    if [ ! -f ".env.vps.template" ]; then
        error "Environment template file not found!"
    fi
    
    # Copy template to production config
    cp .env.vps.template .env.prod
    
    echo
    echo -e "${YELLOW}=== Environment Configuration Required ===${NC}"
    echo "Please edit the .env.prod file with your actual configuration:"
    echo "- Database passwords"
    echo "- Telegram API credentials"
    echo "- Domain settings"
    echo "- Security keys"
    echo
    read -p "Press Enter to open the configuration file in nano editor..."
    nano .env.prod
    
    log "Environment configuration completed"
}

# Create directories
create_directories() {
    log "Creating required directories..."
    
    cd "$INSTALL_DIR"
    mkdir -p data/logs
    mkdir -p data/uploads
    mkdir -p data/backups
    mkdir -p data/postgres
    mkdir -p data/redis
    mkdir -p ssl/certs
    
    # Set permissions
    chown -R 1000:1000 data/
    chmod -R 755 data/
    
    log "Directories created successfully"
}

# Configure firewall
setup_firewall() {
    log "Configuring firewall..."
    
    # Install ufw if not present
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    # Configure firewall rules
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful!)
    ufw allow ssh
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow application port (internal)
    ufw allow 8012/tcp
    
    # Enable firewall
    ufw --force enable
    
    log "Firewall configured successfully"
}

# Setup SSL certificates
setup_ssl() {
    log "Setting up SSL certificates..."
    
    cd "$INSTALL_DIR"
    
    if [ -f "ssl-setup.sh" ]; then
        chmod +x ssl-setup.sh
        ./ssl-setup.sh
    else
        warn "SSL setup script not found. Manual SSL configuration required."
    fi
}

# Configure Nginx
setup_nginx() {
    log "Configuring Nginx..."
    
    cd "$INSTALL_DIR"
    
    # Copy Nginx configuration
    if [ -f "nginx/nginx.conf" ]; then
        cp nginx/nginx.conf /etc/nginx/nginx.conf
    fi
    
    if [ -f "nginx/conf.d/7575.PRO.conf" ]; then
        cp nginx/conf.d/7575.PRO.conf "$NGINX_AVAILABLE/$DOMAIN"
        ln -sf "$NGINX_AVAILABLE/$DOMAIN" "$NGINX_ENABLED/$DOMAIN"
    fi
    
    # Remove default site
    rm -f "$NGINX_ENABLED/default"
    
    # Test configuration
    nginx -t
    
    # Reload Nginx
    systemctl reload nginx
    
    log "Nginx configured successfully"
}

# Install systemd service
install_service() {
    log "Installing systemd service..."
    
    cd "$INSTALL_DIR"
    
    if [ -f "ltdkh-bot.service" ]; then
        cp ltdkh-bot.service "/etc/systemd/system/$SERVICE_NAME.service"
        
        # Reload systemd
        systemctl daemon-reload
        
        # Enable service
        systemctl enable "$SERVICE_NAME"
        
        log "Systemd service installed successfully"
    else
        warn "Service file not found. Manual service setup required."
    fi
}

# Start services
start_services() {
    log "Starting LTDKH Bot services..."
    
    cd "$INSTALL_DIR"
    
    # Pull Docker images
    docker-compose -f docker-compose.vps.yml pull
    
    # Start services
    docker-compose -f docker-compose.vps.yml up -d
    
    # Wait for services to start
    sleep 30
    
    # Check service status
    docker-compose -f docker-compose.vps.yml ps
    
    log "Services started successfully"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check Docker containers
    echo "Docker containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    
    # Check application health
    echo "Checking application health..."
    if curl -f http://localhost:8012/health &> /dev/null; then
        log "✓ Application is responding on port 8012"
    else
        warn "✗ Application health check failed"
    fi
    
    # Check domain access
    echo "Checking domain access..."
    if curl -f "http://$DOMAIN" &> /dev/null; then
        log "✓ Domain $DOMAIN is accessible"
    else
        warn "✗ Domain $DOMAIN is not accessible"
    fi
    
    # Check HTTPS
    if curl -f "https://$DOMAIN" &> /dev/null; then
        log "✓ HTTPS is working for $DOMAIN"
    else
        warn "✗ HTTPS is not working for $DOMAIN"
    fi
    
    # Show service status
    echo
    echo "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
}

# Show completion message
show_completion() {
    echo
    log "=== LTDKH Bot Deployment Completed ==="
    echo
    echo -e "${GREEN}✓ System updated and configured${NC}"
    echo -e "${GREEN}✓ Docker and Docker Compose installed${NC}"
    echo -e "${GREEN}✓ Nginx installed and configured${NC}"
    echo -e "${GREEN}✓ Repository cloned to $INSTALL_DIR${NC}"
    echo -e "${GREEN}✓ Environment configured${NC}"
    echo -e "${GREEN}✓ SSL certificates set up${NC}"
    echo -e "${GREEN}✓ Firewall configured${NC}"
    echo -e "${GREEN}✓ Systemd service installed${NC}"
    echo -e "${GREEN}✓ Services started${NC}"
    echo
    echo -e "${BLUE}Access your application:${NC}"
    echo "HTTP:  http://$DOMAIN"
    echo "HTTPS: https://$DOMAIN"
    echo "API:   https://$DOMAIN/api"
    echo
    echo -e "${BLUE}Service management:${NC}"
    echo "Start:   sudo systemctl start $SERVICE_NAME"
    echo "Stop:    sudo systemctl stop $SERVICE_NAME"
    echo "Restart: sudo systemctl restart $SERVICE_NAME"
    echo "Status:  sudo systemctl status $SERVICE_NAME"
    echo "Logs:    sudo journalctl -u $SERVICE_NAME -f"
    echo
    echo -e "${BLUE}Docker management:${NC}"
    echo "Status:  cd $INSTALL_DIR && docker-compose -f docker-compose.vps.yml ps"
    echo "Logs:    cd $INSTALL_DIR && docker-compose -f docker-compose.vps.yml logs -f"
    echo "Update:  cd $INSTALL_DIR && docker-compose -f docker-compose.vps.yml pull && docker-compose -f docker-compose.vps.yml up -d"
    echo
    echo -e "${YELLOW}Important files:${NC}"
    echo "Configuration: $INSTALL_DIR/.env.prod"
    echo "Logs:         $INSTALL_DIR/data/logs/"
    echo "Nginx config: /etc/nginx/sites-available/$DOMAIN"
    echo "SSL certs:    /etc/letsencrypt/live/$DOMAIN/"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Verify all services are running correctly"
    echo "2. Test the application functionality"
    echo "3. Set up monitoring and backups"
    echo "4. Configure additional security measures"
    echo
}

# Main deployment function
main() {
    log "Starting LTDKH Bot VPS deployment..."
    
    check_root
    show_system_info
    
    # Confirm deployment
    echo -e "${YELLOW}This script will install and configure:${NC}"
    echo "- Docker and Docker Compose"
    echo "- Nginx web server"
    echo "- SSL certificates (Let's Encrypt)"
    echo "- LTDKH Bot application"
    echo "- Systemd service for auto-start"
    echo "- Firewall configuration"
    echo
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    update_system
    install_docker
    install_docker_compose
    install_nginx
    clone_repository
    setup_environment
    create_directories
    setup_firewall
    setup_ssl
    setup_nginx
    install_service
    start_services
    verify_deployment
    show_completion
    
    log "LTDKH Bot deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "LTDKH Bot VPS Deployment Script"
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --version     Show version information"
        exit 0
        ;;
    --version)
        echo "LTDKH Bot VPS Deployment Script v1.0"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac