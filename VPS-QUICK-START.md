# LTDKH Bot VPS 快速部署指南

## 🚀 一键部署（推荐）

在你的Ubuntu 22.04.5 LTS VPS上执行以下命令：

```bash
# 下载并运行一键部署脚本
wget -O deploy.sh https://raw.githubusercontent.com/PengC8899/LTDKH/main/vps-complete-deploy.sh && chmod +x deploy.sh && sudo ./deploy.sh
```

## 📋 部署前准备

### 1. 系统要求
- ✅ Ubuntu 22.04.5 LTS (已满足)
- ✅ 至少2GB内存 (当前使用26%，充足)
- ✅ 至少10GB磁盘空间 (当前使用9%，充足)
- ✅ 域名解析到服务器IP (7577.bet → 你的公网IP)

### 2. 需要准备的信息
在部署过程中，你需要提供以下信息：

```bash
# Telegram API配置
API_ID=你的API_ID
API_HASH=你的API_HASH
BOT_TOKEN=你的机器人TOKEN

# Telegram账户配置
ACCOUNT1_PHONE=+1234567890  # 你的手机号
ACCOUNT1_PASSWORD=账户密码   # Telegram账户密码

# 数据库密码（自定义）
POSTGRES_PASSWORD=设置一个强密码
```

## 🔧 手动部署步骤

如果一键部署失败，可以按以下步骤手动部署：

### 步骤1：克隆代码
```bash
git clone https://github.com/PengC8899/LTDKH.git
cd LTDKH
```

### 步骤2：配置环境变量
```bash
cp .env.vps.template .env.prod
nano .env.prod  # 编辑配置文件
```

### 步骤3：运行部署脚本
```bash
sudo ./vps-complete-deploy.sh
```

## 🎮 服务管理命令

### 启动服务
```bash
sudo systemctl start ltdkh-bot
```

### 停止服务
```bash
sudo systemctl stop ltdkh-bot
```

### 重启服务
```bash
sudo systemctl restart ltdkh-bot
```

### 查看服务状态
```bash
sudo systemctl status ltdkh-bot
```

### 查看服务日志
```bash
# 查看系统服务日志
sudo journalctl -u ltdkh-bot -f

# 查看Docker容器日志
cd /opt/ltdkh-bot
docker-compose -f docker-compose.vps.yml logs -f
```

## 🔍 部署验证

### 检查服务是否正常运行
```bash
# 检查Docker容器状态
docker ps

# 检查应用健康状态
curl http://localhost:8012/health

# 检查域名访问
curl https://7577.bet
```

### 预期结果
- ✅ Docker容器全部运行中
- ✅ 健康检查返回200状态码
- ✅ 域名可以正常访问
- ✅ HTTPS证书有效

## 🌐 访问地址

部署成功后，你可以通过以下地址访问：

- **主页**: https://7577.bet
- **API**: https://7577.bet/api
- **健康检查**: https://7577.bet/health

## 🛠️ 常用维护命令

### 更新代码
```bash
cd /opt/ltdkh-bot
git pull origin main
docker-compose -f docker-compose.vps.yml pull
docker-compose -f docker-compose.vps.yml up -d
```

### 备份数据
```bash
# 备份数据库
docker exec ltdkh_postgres_1 pg_dump -U postgres tg_watchdog > backup_$(date +%Y%m%d).sql

# 备份配置文件
cp /opt/ltdkh-bot/.env.prod ~/env_backup_$(date +%Y%m%d).txt
```

### 查看资源使用
```bash
# 查看系统资源
htop

# 查看磁盘使用
df -h

# 查看内存使用
free -h

# 查看Docker资源使用
docker stats
```

## 🚨 故障排除

### 问题1：服务无法启动
```bash
# 查看详细错误信息
sudo journalctl -u ltdkh-bot -n 50

# 检查配置文件
cat /opt/ltdkh-bot/.env.prod

# 检查端口占用
ss -tulpn | grep 8012
```

### 问题2：域名无法访问
```bash
# 检查Nginx状态
sudo systemctl status nginx

# 检查Nginx配置
sudo nginx -t

# 查看Nginx日志
sudo tail -f /var/log/nginx/error.log
```

### 问题3：SSL证书问题
```bash
# 检查证书状态
sudo certbot certificates

# 重新申请证书
sudo certbot --nginx -d 7577.bet

# 测试证书自动更新
sudo certbot renew --dry-run
```

### 问题4：数据库连接失败
```bash
# 检查数据库容器
docker logs ltdkh_postgres_1

# 测试数据库连接
docker exec -it ltdkh_postgres_1 psql -U postgres -d tg_watchdog
```

## 📞 获取帮助

如果遇到问题，可以：

1. **查看完整文档**: [VPS-DEPLOYMENT-GUIDE.md](./VPS-DEPLOYMENT-GUIDE.md)
2. **GitHub Issues**: https://github.com/PengC8899/LTDKH/issues
3. **检查日志**: 使用上面的日志查看命令

## 🔐 安全提醒

- ✅ 使用强密码（至少16位，包含大小写字母、数字、特殊字符）
- ✅ 定期更新系统：`sudo apt update && sudo apt upgrade -y`
- ✅ 定期备份数据
- ✅ 监控服务状态
- ✅ 不要在公共场所暴露配置文件内容

---

**🎉 部署完成后，你的LTDKH Bot将24小时不间断运行！**