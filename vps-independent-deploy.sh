#!/bin/bash

# LTDKH Bot VPS 独立部署脚本
# 此脚本需要在VPS服务器上手动执行
# 服务器信息: 18.142.231.74 (ubuntu用户)

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 检查是否为root用户
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "检测到root用户，建议使用sudo执行"
    fi
}

# 检查系统
check_system() {
    log_info "检查系统环境..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warning "此脚本针对Ubuntu优化，当前系统: $ID"
    fi
    
    log_success "系统检查完成: $PRETTY_NAME"
}

# 更新系统
update_system() {
    log_info "更新系统包..."
    sudo apt update && sudo apt upgrade -y
    log_success "系统更新完成"
}

# 安装依赖
install_dependencies() {
    log_info "安装必要依赖..."
    
    # 安装基础工具
    sudo apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release
    
    # 安装Docker
    if ! command -v docker &> /dev/null; then
        log_info "安装Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo usermod -aG docker $USER
        log_success "Docker安装完成"
    else
        log_info "Docker已安装"
    fi
    
    # 安装Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_info "安装Docker Compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        log_success "Docker Compose安装完成"
    else
        log_info "Docker Compose已安装"
    fi
    
    # 安装Nginx
    if ! command -v nginx &> /dev/null; then
        log_info "安装Nginx..."
        sudo apt install -y nginx
        sudo systemctl enable nginx
        log_success "Nginx安装完成"
    else
        log_info "Nginx已安装"
    fi
    
    # 安装Certbot
    if ! command -v certbot &> /dev/null; then
        log_info "安装Certbot..."
        sudo apt install -y certbot python3-certbot-nginx
        log_success "Certbot安装完成"
    else
        log_info "Certbot已安装"
    fi
}

# 配置防火墙
setup_firewall() {
    log_info "配置防火墙..."
    
    # 启用UFW
    sudo ufw --force enable
    
    # 允许SSH
    sudo ufw allow ssh
    
    # 允许HTTP和HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # 允许我们的应用端口（8012）- 仅本地访问
    sudo ufw allow from 127.0.0.1 to any port 8012
    
    log_success "防火墙配置完成"
}

# 创建项目目录
setup_project_directory() {
    log_info "创建项目目录..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    
    # 检查目录是否存在
    if [[ -d "$PROJECT_DIR" ]]; then
        log_warning "项目目录已存在: $PROJECT_DIR"
        read -p "是否删除现有目录并重新创建? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf "$PROJECT_DIR"
            log_info "已删除现有目录"
        else
            log_info "使用现有目录"
        fi
    fi
    
    # 创建目录
    sudo mkdir -p "$PROJECT_DIR"
    sudo chown $USER:$USER "$PROJECT_DIR"
    
    log_success "项目目录创建完成: $PROJECT_DIR"
}

# 克隆代码
clone_repository() {
    log_info "克隆代码仓库..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    REPO_URL="https://github.com/PengC8899/LTDKH.git"
    
    cd "$PROJECT_DIR"
    
    if [[ -d ".git" ]]; then
        log_info "更新现有仓库..."
        git pull origin main
    else
        log_info "克隆新仓库..."
        git clone "$REPO_URL" .
    fi
    
    log_success "代码克隆完成"
}

# 配置环境变量
setup_environment() {
    log_info "配置环境变量..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    cd "$PROJECT_DIR"
    
    # 复制环境变量模板
    if [[ ! -f ".env.prod" ]]; then
        log_error "未找到.env.prod文件"
        exit 1
    fi
    
    # 创建实际的环境变量文件
    cp .env.prod .env
    
    log_warning "请手动编辑 $PROJECT_DIR/.env 文件，配置以下参数:"
    echo "  - TELEGRAM_BOT_TOKEN"
    echo "  - ACCOUNT_API_ID"
    echo "  - ACCOUNT_API_HASH"
    echo "  - ACCOUNT_PHONE_NUMBER"
    echo "  - POSTGRES_PASSWORD"
    echo "  - DOMAIN (如果需要)"
    
    read -p "按回车键继续..."
    
    log_success "环境变量配置完成"
}

# 构建和启动应用
start_application() {
    log_info "构建和启动应用..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    cd "$PROJECT_DIR"
    
    # 停止现有容器
    docker-compose -f docker-compose.prod.yml down || true
    
    # 构建镜像
    docker-compose -f docker-compose.prod.yml build
    
    # 启动服务
    docker-compose -f docker-compose.prod.yml up -d
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 30
    
    # 检查服务状态
    docker-compose -f docker-compose.prod.yml ps
    
    log_success "应用启动完成"
}

# 配置Nginx
setup_nginx() {
    log_info "配置Nginx..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    
    # 复制Nginx配置
    sudo cp "$PROJECT_DIR/nginx.conf" /etc/nginx/sites-available/ltdkh-bot
    
    # 启用站点
    sudo ln -sf /etc/nginx/sites-available/ltdkh-bot /etc/nginx/sites-enabled/
    
    # 测试配置
    sudo nginx -t
    
    # 重启Nginx
    sudo systemctl restart nginx
    
    log_success "Nginx配置完成"
}

# 配置SSL证书
setup_ssl() {
    log_info "配置SSL证书..."
    
    read -p "请输入域名 (例: 7577.bet): " DOMAIN
    
    if [[ -z "$DOMAIN" ]]; then
        log_warning "跳过SSL配置"
        return
    fi
    
    # 获取SSL证书
    sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@"$DOMAIN"
    
    # 设置自动续期
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
    
    log_success "SSL证书配置完成"
}

# 配置系统服务
setup_systemd_service() {
    log_info "配置系统服务..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    
    # 创建systemd服务文件
    sudo tee /etc/systemd/system/ltdkh-bot.service > /dev/null <<EOF
[Unit]
Description=LTDKH Bot Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/docker-compose -f docker-compose.prod.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.prod.yml down
TimeoutStartSec=0
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd
    sudo systemctl daemon-reload
    
    # 启用服务
    sudo systemctl enable ltdkh-bot
    
    log_success "系统服务配置完成"
}

# 显示部署状态
show_status() {
    log_info "部署状态检查..."
    
    PROJECT_DIR="/opt/ltdkh-bot"
    cd "$PROJECT_DIR"
    
    echo "=== Docker 容器状态 ==="
    docker-compose -f docker-compose.prod.yml ps
    
    echo "\n=== 系统服务状态 ==="
    sudo systemctl status ltdkh-bot --no-pager
    
    echo "\n=== Nginx 状态 ==="
    sudo systemctl status nginx --no-pager
    
    echo "\n=== 端口监听状态 ==="
    sudo netstat -tlnp | grep -E ":(80|443|8012)\s"
    
    echo "\n=== 应用健康检查 ==="
    curl -f http://localhost:8012/health || echo "健康检查失败"
    
    log_success "状态检查完成"
}

# 主函数
main() {
    log_info "开始LTDKH Bot VPS独立部署..."
    
    check_root
    check_system
    update_system
    install_dependencies
    setup_firewall
    setup_project_directory
    clone_repository
    setup_environment
    start_application
    setup_nginx
    setup_ssl
    setup_systemd_service
    show_status
    
    log_success "部署完成！"
    
    echo "\n=== 部署信息 ==="
    echo "项目目录: /opt/ltdkh-bot"
    echo "应用端口: 8012 (本地访问)"
    echo "Web端口: 80, 443 (公网访问)"
    echo "\n=== 管理命令 ==="
    echo "启动服务: sudo systemctl start ltdkh-bot"
    echo "停止服务: sudo systemctl stop ltdkh-bot"
    echo "重启服务: sudo systemctl restart ltdkh-bot"
    echo "查看日志: cd /opt/ltdkh-bot && docker-compose -f docker-compose.prod.yml logs -f"
    echo "\n=== 注意事项 ==="
    echo "1. 请确保已正确配置 /opt/ltdkh-bot/.env 文件"
    echo "2. 如需域名访问，请配置DNS解析到此服务器IP"
    echo "3. 防火墙已配置，仅允许必要端口访问"
}

# 执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi