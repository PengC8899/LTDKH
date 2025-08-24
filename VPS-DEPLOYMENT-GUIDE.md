# LTDKH Bot VPS 独立部署指南

## 服务器信息
- **IP地址**: 18.142.231.74
- **IPv6地址**: 2406:da18:ee8:a00:6e14:5bc6:ebc6:154c
- **用户名**: ubuntu
- **SSH密钥**: LightsailDefaultKey-ap-southeast-1.pem

## 部署概述

本指南将帮助您在VPS上独立部署LTDKH Bot，避免与现有服务冲突。部署将使用以下独立配置：

- **项目目录**: `/opt/ltdkh-bot`
- **应用端口**: 8013 (外部访问)
- **数据库端口**: 5433 (PostgreSQL)
- **Redis端口**: 6380
- **Nginx端口**: 8080 (HTTP), 8443 (HTTPS)
- **容器前缀**: `ltdkh-`

## 前置要求

1. VPS服务器已启动并可访问
2. 具有sudo权限的用户账户
3. 服务器已连接到互联网

## 部署步骤

### 步骤1: 连接到VPS服务器

#### 方法1: 使用SSH密钥连接
```bash
# 在本地机器上执行
ssh -i /path/to/LightsailDefaultKey-ap-southeast-1.pem ubuntu@18.142.231.74
```

#### 方法2: 使用AWS Lightsail控制台
1. 登录AWS Lightsail控制台
2. 找到您的实例
3. 点击"连接"按钮使用浏览器SSH

#### 方法3: 配置密码登录（如果SSH密钥有问题）
```bash
# 在VPS上执行（通过控制台）
sudo passwd ubuntu
# 设置密码后编辑SSH配置
sudo nano /etc/ssh/sshd_config
# 修改以下行：
# PasswordAuthentication yes
# 重启SSH服务
sudo systemctl restart ssh
```

### 步骤2: 上传部署文件到VPS

#### 方法1: 使用SCP上传
```bash
# 在本地机器上执行
scp -i /path/to/LightsailDefaultKey-ap-southeast-1.pem vps-independent-deploy.sh ubuntu@18.142.231.74:~/
```

#### 方法2: 直接在VPS上下载
```bash
# 在VPS上执行
wget https://raw.githubusercontent.com/PengC8899/LTDKH/main/vps-independent-deploy.sh
chmod +x vps-independent-deploy.sh
```

### 步骤3: 执行自动部署脚本

```bash
# 在VPS上执行
./vps-independent-deploy.sh
```

脚本将自动执行以下操作：
1. 系统更新和依赖安装
2. Docker和Docker Compose安装
3. Nginx和Certbot安装
4. 防火墙配置
5. 项目目录创建
6. 代码克隆
7. 环境变量配置
8. 应用构建和启动
9. Nginx配置
10. SSL证书配置（可选）
11. 系统服务配置

### 步骤4: 手动配置环境变量

部署脚本完成后，需要手动配置环境变量：

```bash
# 编辑环境变量文件
sudo nano /opt/ltdkh-bot/.env
```

必须配置的参数：
```bash
# Telegram Bot Token（从@BotFather获取）
TELEGRAM_BOT_TOKEN=your_bot_token_here

# Telegram API配置（从https://my.telegram.org获取）
ACCOUNT_API_ID=your_api_id_here
ACCOUNT_API_HASH=your_api_hash_here
ACCOUNT_PHONE_NUMBER=your_phone_number_here

# 数据库密码（设置强密码）
POSTGRES_PASSWORD=your_secure_password_here

# 域名（如果使用域名访问）
DOMAIN=your_domain.com
```

### 步骤5: 重启服务

配置完环境变量后，重启服务：

```bash
cd /opt/ltdkh-bot
sudo docker-compose -f docker-compose.independent.yml down
sudo docker-compose -f docker-compose.independent.yml up -d
```

### 步骤6: 验证部署

```bash
# 检查容器状态
sudo docker-compose -f docker-compose.independent.yml ps

# 检查应用健康状态
curl http://localhost:8013/health

# 检查系统服务状态
sudo systemctl status ltdkh-bot

# 检查Nginx状态
sudo systemctl status nginx

# 检查端口监听
sudo netstat -tlnp | grep -E ":(8013|8080|8443|5433|6380)\s"
```

## 访问应用

### 本地访问
- HTTP: http://18.142.231.74:8080
- HTTPS: https://18.142.231.74:8443
- 直接应用: http://18.142.231.74:8013

### 域名访问（如果配置了域名）
- HTTP: http://your_domain.com:8080
- HTTPS: https://your_domain.com:8443

## 管理命令

### 服务管理
```bash
# 启动服务
sudo systemctl start ltdkh-bot

# 停止服务
sudo systemctl stop ltdkh-bot

# 重启服务
sudo systemctl restart ltdkh-bot

# 查看服务状态
sudo systemctl status ltdkh-bot
```

### Docker管理
```bash
cd /opt/ltdkh-bot

# 查看容器状态
sudo docker-compose -f docker-compose.independent.yml ps

# 查看日志
sudo docker-compose -f docker-compose.independent.yml logs -f

# 重启容器
sudo docker-compose -f docker-compose.independent.yml restart

# 重新构建并启动
sudo docker-compose -f docker-compose.independent.yml up -d --build
```

### 更新代码
```bash
cd /opt/ltdkh-bot
git pull origin main
sudo docker-compose -f docker-compose.independent.yml up -d --build
```

## 监控和维护

### 查看日志
```bash
# 应用日志
sudo docker-compose -f docker-compose.independent.yml logs -f ltdkh-app

# 数据库日志
sudo docker-compose -f docker-compose.independent.yml logs -f ltdkh-postgres

# Redis日志
sudo docker-compose -f docker-compose.independent.yml logs -f ltdkh-redis

# Nginx日志
sudo tail -f /var/log/nginx/ltdkh-bot-access.log
sudo tail -f /var/log/nginx/ltdkh-bot-error.log
```

### 数据备份
```bash
# 备份数据库
sudo docker exec ltdkh-postgres pg_dump -U ltdkh_user ltdkh_bot > backup_$(date +%Y%m%d_%H%M%S).sql

# 备份Redis数据
sudo docker exec ltdkh-redis redis-cli BGSAVE
sudo docker cp ltdkh-redis:/data/dump.rdb ./redis_backup_$(date +%Y%m%d_%H%M%S).rdb

# 备份会话文件
sudo tar -czf sessions_backup_$(date +%Y%m%d_%H%M%S).tar.gz /opt/ltdkh-bot/sessions/
```

### 性能监控
```bash
# 系统资源使用
top
htop
df -h
free -h

# Docker资源使用
sudo docker stats

# 网络连接
sudo netstat -tlnp
sudo ss -tlnp
```

## 故障排除

### 常见问题

1. **容器启动失败**
   ```bash
   # 查看详细错误信息
   sudo docker-compose -f docker-compose.independent.yml logs
   ```

2. **端口冲突**
   ```bash
   # 检查端口占用
   sudo netstat -tlnp | grep :8013
   # 修改docker-compose.independent.yml中的端口映射
   ```

3. **数据库连接失败**
   ```bash
   # 检查数据库容器状态
   sudo docker exec ltdkh-postgres pg_isready -U ltdkh_user
   ```

4. **SSL证书问题**
   ```bash
   # 重新生成自签名证书
   sudo mkdir -p /etc/nginx/ssl
   sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout /etc/nginx/ssl/ltdkh-bot-selfsigned.key \
     -out /etc/nginx/ssl/ltdkh-bot-selfsigned.crt
   ```

### 紧急恢复

如果服务完全无法启动：

```bash
# 停止所有服务
sudo docker-compose -f docker-compose.independent.yml down

# 清理Docker资源
sudo docker system prune -f

# 重新启动
sudo docker-compose -f docker-compose.independent.yml up -d --build
```

## 安全建议

1. **定期更新系统**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **配置防火墙**
   ```bash
   sudo ufw status
   sudo ufw allow 8080/tcp
   sudo ufw allow 8443/tcp
   ```

3. **使用强密码**
   - 数据库密码
   - 系统用户密码

4. **定期备份数据**
   - 设置自动备份脚本
   - 定期测试恢复流程

5. **监控日志**
   - 定期检查错误日志
   - 设置日志轮转

## 联系支持

如果遇到问题，请提供以下信息：
1. 错误日志
2. 系统信息 (`uname -a`)
3. Docker版本 (`docker --version`)
4. 容器状态 (`docker ps -a`)

---

**注意**: 此部署方案使用独立端口和服务名称，不会与现有服务冲突。请确保防火墙允许相应端口的访问。