# LTDKH Bot VPS 部署指南

本指南将帮助您将 LTDKH Bot 部署到 VPS 服务器，并配置域名 `7577.bet`。

## 前置要求

- Ubuntu 20.04+ 或 Debian 11+ VPS 服务器
- 域名 `7577.bet` 已购买并可管理 DNS 记录
- 服务器至少 2GB RAM，20GB 存储空间
- 服务器具有公网 IP 地址

## 部署步骤

### 1. 域名 DNS 配置

在您的域名管理面板中，添加以下 DNS 记录：

```
类型    名称        值                TTL
A       @           YOUR_VPS_IP      300
A       www         YOUR_VPS_IP      300
```

将 `YOUR_VPS_IP` 替换为您的 VPS 服务器公网 IP 地址。

### 2. 服务器准备

连接到您的 VPS 服务器：

```bash
ssh root@YOUR_VPS_IP
```

### 3. 配置环境变量

在部署前，您需要配置生产环境变量。编辑 `.env.prod` 文件：

```bash
# 在服务器上克隆代码后
cd /opt/ltdkh-bot
cp .env.prod .env.prod.backup
vim .env.prod
```

**重要：** 请确保填写以下关键配置：

```env
# Telegram Bot Configuration
API_ID=your_actual_api_id
API_HASH=your_actual_api_hash
BOT_TOKEN=your_actual_bot_token

# Account Configuration
ACCOUNT1_PHONE=+1234567890
ACCOUNT1_PASSWORD=your_password
# ... 其他账户配置

# PostgreSQL Password (设置强密码)
POSTGRES_PASSWORD=your_very_secure_password
```

### 4. 一键部署

运行自动化部署脚本：

```bash
# 下载部署脚本
wget https://raw.githubusercontent.com/PengC8899/LTDKH/main/deploy.sh
chmod +x deploy.sh

# 执行完整部署
sudo ./deploy.sh
```

部署脚本将自动完成以下操作：

1. ✅ 安装系统依赖（Docker, Nginx, Certbot 等）
2. ✅ 配置防火墙规则
3. ✅ 克隆 GitHub 代码仓库
4. ✅ 获取 SSL 证书（Let's Encrypt）
5. ✅ 配置 Nginx 反向代理
6. ✅ 设置 systemd 服务
7. ✅ 启动应用程序
8. ✅ 配置 SSL 证书自动续期

### 5. 验证部署

部署完成后，访问以下地址验证：

- **主页**: https://7577.bet
- **健康检查**: https://7577.bet/health
- **群组统计**: https://7577.bet/ui/groups
- **用户排行**: https://7577.bet/ui/top_users

## 服务管理

### 查看服务状态

```bash
# 查看应用服务状态
sudo systemctl status ltdkh-bot

# 查看 Docker 容器状态
cd /opt/ltdkh-bot
sudo docker-compose -f docker-compose.prod.yml ps

# 查看应用日志
sudo docker-compose -f docker-compose.prod.yml logs -f app
```

### 重启服务

```bash
# 重启应用服务
sudo systemctl restart ltdkh-bot

# 或者直接重启容器
cd /opt/ltdkh-bot
sudo docker-compose -f docker-compose.prod.yml restart
```

### 更新应用

当您推送新代码到 GitHub 后，在服务器上运行：

```bash
cd /opt/ltdkh-bot
sudo ./deploy.sh --update
```

## 监控和维护

### 日志查看

```bash
# 应用日志
sudo docker-compose -f /opt/ltdkh-bot/docker-compose.prod.yml logs -f app

# Nginx 日志
sudo tail -f /var/log/nginx/7577.bet.access.log
sudo tail -f /var/log/nginx/7577.bet.error.log

# 系统日志
sudo journalctl -u ltdkh-bot -f
```

### 数据备份

```bash
# 备份数据库
sudo docker exec ltdkh_postgres pg_dump -U postgres tg_watchdog > backup_$(date +%Y%m%d).sql

# 备份 Redis 数据
sudo docker exec ltdkh_redis redis-cli BGSAVE
```

### SSL 证书管理

```bash
# 手动续期 SSL 证书
sudo certbot renew

# 查看证书状态
sudo certbot certificates
```

## 故障排除

### 常见问题

1. **域名无法访问**
   - 检查 DNS 记录是否正确配置
   - 确认防火墙端口 80, 443 已开放
   - 检查 Nginx 配置：`sudo nginx -t`

2. **SSL 证书获取失败**
   - 确保域名已正确解析到服务器 IP
   - 检查端口 80 是否被占用
   - 临时停止 Nginx：`sudo systemctl stop nginx`

3. **应用无法启动**
   - 检查环境变量配置：`.env.prod`
   - 查看容器日志：`sudo docker-compose -f docker-compose.prod.yml logs`
   - 检查数据库连接

4. **Telegram Bot 无响应**
   - 验证 Bot Token 是否正确
   - 检查 API_ID 和 API_HASH
   - 确认账户登录状态

### 性能优化

1. **服务器资源监控**
   ```bash
   # 安装监控工具
   sudo apt install htop iotop
   
   # 查看资源使用
   htop
   sudo iotop
   ```

2. **Docker 资源限制**
   在 `docker-compose.prod.yml` 中添加资源限制：
   ```yaml
   services:
     app:
       deploy:
         resources:
           limits:
             memory: 1G
             cpus: '0.5'
   ```

## 安全建议

1. **定期更新系统**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **配置 SSH 密钥认证**
   - 禁用密码登录
   - 使用 SSH 密钥认证
   - 更改默认 SSH 端口

3. **设置自动备份**
   - 配置定时任务备份数据库
   - 使用云存储保存备份文件

4. **监控异常访问**
   - 定期检查 Nginx 访问日志
   - 配置失败登录告警

## 联系支持

如果在部署过程中遇到问题，请：

1. 查看相关日志文件
2. 检查 GitHub Issues
3. 提供详细的错误信息和环境配置

---

**注意**: 请确保在生产环境中使用强密码，并定期更新系统和应用程序。