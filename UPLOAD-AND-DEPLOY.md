# LTDKH Bot VPS 上传和部署指令

## 服务器信息
- **IP地址**: 18.142.231.74
- **用户名**: ubuntu
- **SSH密钥**: `/Users/pccc/LTDKH_BOT/DIDI (1).pem`

## 快速部署命令

### 1. 上传部署包到VPS
```bash
scp -i "/Users/pccc/LTDKH_BOT/DIDI (1).pem" ltdkh-bot-deployment.tar.gz ubuntu@18.142.231.74:~/
```

### 2. 连接到VPS
```bash
ssh -i "/Users/pccc/LTDKH_BOT/DIDI (1).pem" ubuntu@18.142.231.74
```

### 3. 在VPS上执行部署
```bash
# 解压部署包
tar -xzf ltdkh-bot-deployment.tar.gz
cd ltdkh-bot-deployment

# 执行部署脚本
chmod +x vps-independent-deploy.sh
sudo ./vps-independent-deploy.sh
```

### 4. 配置环境变量
```bash
# 编辑环境变量文件
nano .env.independent

# 必须配置的变量：
# TELEGRAM_BOT_TOKEN=你的机器人Token
# TELEGRAM_ADMIN_ID=你的Telegram用户ID
# 其他变量可以保持默认值
```

### 5. 启动服务
```bash
# 重启服务
sudo systemctl restart ltdkh-bot
sudo systemctl restart nginx

# 检查服务状态
sudo systemctl status ltdkh-bot
sudo systemctl status nginx
```

### 6. 验证部署
```bash
# 检查应用健康状态
curl http://localhost:8013/health

# 查看服务日志
sudo journalctl -u ltdkh-bot -f
```

## 访问地址

部署成功后，可以通过以下地址访问应用：

- **HTTP**: http://18.142.231.74:8080
- **HTTPS**: https://18.142.231.74:8443 (自签名证书，浏览器会警告)
- **直接访问**: http://18.142.231.74:8013

## 常用管理命令

```bash
# 查看所有服务状态
sudo systemctl status ltdkh-bot nginx docker

# 重启所有服务
sudo systemctl restart ltdkh-bot nginx

# 查看应用日志
sudo journalctl -u ltdkh-bot -n 50

# 查看Docker容器状态
sudo docker ps

# 更新代码（如果需要）
cd /opt/ltdkh-bot
sudo git pull origin main
sudo docker-compose -f docker-compose.independent.yml build
sudo systemctl restart ltdkh-bot
```

## 故障排除

### 如果服务启动失败：
```bash
# 检查详细错误信息
sudo journalctl -u ltdkh-bot -n 20

# 检查Docker容器日志
sudo docker logs ltdkh-redis-independent
sudo docker logs ltdkh-postgres-independent
sudo docker logs ltdkh-app-independent
```

### 如果端口被占用：
```bash
# 检查端口占用情况
sudo netstat -tlnp | grep -E ':(8013|8080|8443|5433|6380)'

# 如果需要，可以修改 .env.independent 中的端口配置
```

### 如果Nginx配置有问题：
```bash
# 测试Nginx配置
sudo nginx -t

# 重新加载Nginx配置
sudo nginx -s reload
```

## 重要提醒

1. **环境变量配置**：部署后必须编辑 `.env.independent` 文件，设置正确的 Telegram Bot Token
2. **防火墙设置**：确保VPS防火墙允许访问端口 8080、8443、8013
3. **SSL证书**：当前使用自签名证书，生产环境建议配置Let's Encrypt证书
4. **数据备份**：重要数据会保存在 `/opt/ltdkh-bot/data/` 目录，建议定期备份
5. **监控日志**：定期检查应用日志，确保服务正常运行

## 联系支持

如果遇到问题，请检查：
1. VPS网络连接是否正常
2. Docker服务是否正常运行
3. 环境变量是否正确配置
4. 防火墙设置是否正确

详细的部署文档请参考解压后的 `DEPLOY-INSTRUCTIONS.md` 和 `VPS-DEPLOYMENT-GUIDE.md` 文件。