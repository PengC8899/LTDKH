#!/bin/bash

# LTDKH Bot 快速部署脚本
# 在 VPS 上运行此脚本进行一键部署

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
DOMAIN="7577.bet"
APP_DIR="/opt/ltdkh-bot"
REPO_URL="https://github.com/PengC8899/LTDKH.git"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
    log_error "请使用 root 权限运行此脚本: sudo $0"
    exit 1
fi

log_info "开始 LTDKH Bot 快速部署..."
log_info "域名: $DOMAIN"
log_info "安装目录: $APP_DIR"

# 1. 更新系统并安装依赖
log_info "更新系统并安装依赖..."
apt update && apt upgrade -y
apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx curl git ufw

# 启动 Docker
systemctl start docker
systemctl enable docker

# 2. 配置防火墙
log_info "配置防火墙..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# 3. 克隆代码
log_info "克隆代码仓库..."
mkdir -p $APP_DIR
cd $APP_DIR
git clone $REPO_URL .

# 4. 检查环境配置
if [[ ! -f ".env.prod" ]]; then
    log_warning "未找到 .env.prod 文件，请配置您的环境变量"
    log_info "复制模板文件..."
    cp .env.prod .env.prod.example
    log_error "请编辑 .env.prod 文件，填入您的实际配置，然后重新运行此脚本"
    log_info "编辑命令: nano $APP_DIR/.env.prod"
    exit 1
fi

# 5. 获取 SSL 证书
log_info "获取 SSL 证书..."
systemctl stop nginx 2>/dev/null || true
certbot certonly --standalone -d $DOMAIN -d www.$DOMAIN --agree-tos --no-eff-email --email admin@$DOMAIN --non-interactive

# 6. 配置 Nginx
log_info "配置 Nginx..."
cp nginx.conf /etc/nginx/sites-available/$DOMAIN
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl start nginx
systemctl enable nginx

# 7. 构建并启动应用
log_info "构建并启动应用..."
docker-compose -f docker-compose.prod.yml build
docker-compose -f docker-compose.prod.yml up -d

# 8. 创建 systemd 服务
log_info "创建系统服务..."
cat > /etc/systemd/system/ltdkh-bot.service << EOF
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

systemctl daemon-reload
systemctl enable ltdkh-bot
systemctl start ltdkh-bot

# 9. 设置 SSL 自动续期
log_info "设置 SSL 自动续期..."
cat > /usr/local/bin/renew-ssl.sh << 'EOF'
#!/bin/bash
certbot renew --quiet --nginx
systemctl reload nginx
EOF
chmod +x /usr/local/bin/renew-ssl.sh
echo "0 3 * * * root /usr/local/bin/renew-ssl.sh" > /etc/cron.d/ssl-renewal

# 10. 等待服务启动并测试
log_info "等待服务启动..."
sleep 15

# 显示部署结果
echo ""
echo "==========================================="
log_success "部署完成！"
echo "==========================================="
echo "域名: https://$DOMAIN"
echo "健康检查: https://$DOMAIN/health"
echo "群组统计: https://$DOMAIN/ui/groups"
echo "用户排行: https://$DOMAIN/ui/top_users"
echo ""
echo "服务状态:"
systemctl status ltdkh-bot --no-pager -l
echo ""
echo "Docker 容器:"
docker-compose -f docker-compose.prod.yml ps
echo "==========================================="

# 测试应用
log_info "测试应用健康状态..."
if curl -f -s https://$DOMAIN/health > /dev/null; then
    log_success "应用运行正常！"
    log_success "访问地址: https://$DOMAIN"
else
    log_warning "应用可能还未完全启动，请稍后检查"
    log_info "查看日志: docker-compose -f $APP_DIR/docker-compose.prod.yml logs -f"
fi

log_success "快速部署完成！"
log_info "如需更新应用，请运行: cd $APP_DIR && ./deploy.sh --update"