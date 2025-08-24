# LTDKH Bot VPS 部署指南

## 系统信息
- **操作系统**: Ubuntu 22.04.5 LTS
- **架构**: x86_64 (AWS)
- **内存使用**: 26%
- **磁盘使用**: 9.0% of 57.97GB
- **IP地址**: 172.26.10.80 (内网)
- **域名**: 7577.bet

## 快速部署（推荐）

### 方法一：一键部署脚本

```bash
# 1. 下载部署脚本
wget -O vps-deploy.sh https://raw.githubusercontent.com/PengC8899/LTDKH/main/vps-complete-deploy.sh

# 2. 设置执行权限
chmod +x vps-deploy.sh

# 3. 运行部署脚本（需要root权限）
sudo ./vps-deploy.sh
```

### 方法二：Git克隆部署

```bash
# 1. 克隆仓库
git clone https://github.com/PengC8899/LTDKH.git
cd LTDKH

# 2. 运行部署脚本
sudo ./vps-complete-deploy.sh
```

## 手动部署步骤

### 1. 系统准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装必要工具
sudo apt install -y curl wget git unzip software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# 重启系统（如果需要）
sudo reboot
```

### 2. 安装Docker和Docker Compose

```bash
# 安装Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 启动Docker服务
sudo systemctl start docker
sudo systemctl enable docker

# 安装Docker Compose
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 验证安装
docker --version
docker-compose --version
```

### 3. 安装Nginx

```bash
# 安装Nginx
sudo apt install -y nginx

# 启动Nginx服务
sudo systemctl start nginx
sudo systemctl enable nginx

# 检查状态
sudo systemctl status nginx
```

### 4. 克隆项目代码

```bash
# 创建项目目录
sudo mkdir -p /opt/ltdkh-bot
sudo chown $USER:$USER /opt/ltdkh-bot

# 克隆代码
git clone https://github.com/PengC8899/LTDKH.git /opt/ltdkh-bot
cd /opt/ltdkh-bot
```

### 5. 配置环境变量

```bash
# 复制环境变量模板
cp .env.vps.template .env.prod

# 编辑配置文件
nano .env.prod
```

**重要配置项：**
```bash
# 数据库配置
POSTGRES_PASSWORD=your_secure_password_here
DATABASE_URL=postgresql+asyncpg://postgres:your_secure_password_here@postgres:5432/tg_watchdog

# Telegram API配置
API_ID=your_api_id_here
API_HASH=your_api_hash_here
BOT_TOKEN=your_bot_token_here

# 账户配置
ACCOUNT1_PHONE=+1234567890
ACCOUNT1_PASSWORD=account1_password

# 域名配置
DOMAIN=7577.bet
ALLOWED_HOSTS=7577.bet,www.7577.bet,localhost

# 安全配置
SECRET_KEY=your_very_long_and_secure_secret_key_here
JWT_SECRET=your_jwt_secret_key_here
```

### 6. 创建必要目录

```bash
cd /opt/ltdkh-bot

# 创建数据目录
mkdir -p data/logs
mkdir -p data/uploads
mkdir -p data/backups
mkdir -p data/postgres
mkdir -p data/redis
mkdir -p ssl/certs

# 设置权限
sudo chown -R 1000:1000 data/
sudo chmod -R 755 data/
```

### 7. 配置防火墙

```bash
# 安装并配置UFW防火墙
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 允许SSH、HTTP、HTTPS
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8012/tcp

# 启用防火墙
sudo ufw --force enable

# 检查状态
sudo ufw status
```

### 8. 配置SSL证书

```bash
# 运行SSL配置脚本
chmod +x ssl-setup.sh
sudo ./ssl-setup.sh
```

### 9. 配置Nginx

```bash
# 复制Nginx配置
sudo cp nginx/nginx.conf /etc/nginx/nginx.conf
sudo cp nginx/conf.d/7577.bet.conf /etc/nginx/sites-available/7577.bet

# 启用站点
sudo ln -sf /etc/nginx/sites-available/7577.bet /etc/nginx/sites-enabled/7577.bet
sudo rm -f /etc/nginx/sites-enabled/default

# 测试配置
sudo nginx -t

# 重载Nginx
sudo systemctl reload nginx
```

### 10. 安装系统服务

```bash
# 复制服务文件
sudo cp ltdkh-bot.service /etc/systemd/system/ltdkh-bot.service

# 重载systemd
sudo systemctl daemon-reload

# 启用服务
sudo systemctl enable ltdkh-bot
```

### 11. 启动服务

```bash
cd /opt/ltdkh-bot

# 拉取Docker镜像
docker-compose -f docker-compose.vps.yml pull

# 启动服务
docker-compose -f docker-compose.vps.yml up -d

# 检查服务状态
docker-compose -f docker-compose.vps.yml ps
```

## 部署验证

### 检查服务状态

```bash
# 检查Docker容器
docker ps

# 检查应用健康状态
curl http://localhost:8012/health

# 检查域名访问
curl http://7577.bet
curl https://7577.bet

# 检查系统服务
sudo systemctl status ltdkh-bot
```

### 查看日志

```bash
# Docker服务日志
docker-compose -f docker-compose.vps.yml logs -f

# 系统服务日志
sudo journalctl -u ltdkh-bot -f

# 应用日志
tail -f /opt/ltdkh-bot/data/logs/app.log
```

## 访问地址

- **HTTP**: http://7577.bet
- **HTTPS**: https://7577.bet
- **API**: https://7577.bet/api
- **健康检查**: https://7577.bet/health

## 服务管理

### 基本操作

```bash
# 启动服务
sudo systemctl start ltdkh-bot

# 停止服务
sudo systemctl stop ltdkh-bot

# 重启服务
sudo systemctl restart ltdkh-bot

# 查看状态
sudo systemctl status ltdkh-bot

# 查看日志
sudo journalctl -u ltdkh-bot -f
```

### Docker操作

```bash
cd /opt/ltdkh-bot

# 查看容器状态
docker-compose -f docker-compose.vps.yml ps

# 查看日志
docker-compose -f docker-compose.vps.yml logs -f

# 重启服务
docker-compose -f docker-compose.vps.yml restart

# 更新服务
docker-compose -f docker-compose.vps.yml pull
docker-compose -f docker-compose.vps.yml up -d

# 停止服务
docker-compose -f docker-compose.vps.yml down
```

## SSL证书管理

### 手动更新证书

```bash
# 更新证书
sudo certbot renew

# 重载Nginx
sudo systemctl reload nginx
```

### 检查证书状态

```bash
# 查看证书信息
sudo certbot certificates

# 测试自动更新
sudo certbot renew --dry-run
```

## 备份与恢复

### 数据备份

```bash
# 备份数据库
docker exec ltdkh_postgres_1 pg_dump -U postgres tg_watchdog > backup_$(date +%Y%m%d).sql

# 备份配置文件
tar -czf config_backup_$(date +%Y%m%d).tar.gz /opt/ltdkh-bot/.env.prod /etc/nginx/sites-available/7577.bet

# 备份应用数据
tar -czf data_backup_$(date +%Y%m%d).tar.gz /opt/ltdkh-bot/data/
```

### 数据恢复

```bash
# 恢复数据库
docker exec -i ltdkh_postgres_1 psql -U postgres tg_watchdog < backup_20240824.sql

# 恢复配置文件
tar -xzf config_backup_20240824.tar.gz -C /

# 恢复应用数据
tar -xzf data_backup_20240824.tar.gz -C /opt/ltdkh-bot/
```

## 监控与维护

### 系统监控

```bash
# 查看系统资源
htop
df -h
free -h

# 查看网络连接
ss -tulpn

# 查看进程
ps aux | grep ltdkh
```

### 日志轮转

```bash
# 配置logrotate
sudo nano /etc/logrotate.d/ltdkh-bot
```

添加以下内容：
```
/opt/ltdkh-bot/data/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
```

## 故障排除

### 常见问题

1. **服务无法启动**
   ```bash
   # 检查配置文件
   sudo systemctl status ltdkh-bot
   sudo journalctl -u ltdkh-bot -n 50
   ```

2. **域名无法访问**
   ```bash
   # 检查Nginx配置
   sudo nginx -t
   sudo systemctl status nginx
   ```

3. **SSL证书问题**
   ```bash
   # 检查证书状态
   sudo certbot certificates
   # 重新申请证书
   sudo certbot --nginx -d 7577.bet
   ```

4. **数据库连接问题**
   ```bash
   # 检查数据库容器
   docker logs ltdkh_postgres_1
   # 测试数据库连接
   docker exec -it ltdkh_postgres_1 psql -U postgres -d tg_watchdog
   ```

### 性能优化

1. **调整Docker资源限制**
   ```yaml
   # 在docker-compose.vps.yml中添加
   deploy:
     resources:
       limits:
         memory: 1G
         cpus: '0.5'
   ```

2. **优化Nginx配置**
   ```nginx
   # 在nginx.conf中调整
   worker_processes auto;
   worker_connections 1024;
   ```

3. **数据库优化**
   ```bash
   # 调整PostgreSQL配置
   docker exec -it ltdkh_postgres_1 nano /var/lib/postgresql/data/postgresql.conf
   ```

## 安全建议

1. **定期更新系统**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **配置fail2ban**
   ```bash
   sudo apt install fail2ban
   sudo systemctl enable fail2ban
   ```

3. **使用强密码**
   - 数据库密码至少16位
   - 包含大小写字母、数字和特殊字符

4. **限制SSH访问**
   ```bash
   # 编辑SSH配置
   sudo nano /etc/ssh/sshd_config
   # 禁用root登录
   PermitRootLogin no
   # 使用密钥认证
   PasswordAuthentication no
   ```

## 技术支持

- **GitHub仓库**: https://github.com/PengC8899/LTDKH
- **问题反馈**: 在GitHub上创建Issue
- **文档更新**: 查看仓库中的最新文档

## 相关文档

- [Docker官方文档](https://docs.docker.com/)
- [Nginx官方文档](https://nginx.org/en/docs/)
- [Let's Encrypt文档](https://letsencrypt.org/docs/)
- [Ubuntu服务器指南](https://ubuntu.com/server/docs)

---

**注意**: 请确保在生产环境中使用强密码和安全配置。定期备份数据和配置文件。