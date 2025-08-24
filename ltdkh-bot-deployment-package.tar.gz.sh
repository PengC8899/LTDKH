#!/bin/bash

# LTDKH Bot 独立部署包创建脚本
# 此脚本将创建一个包含所有必要文件的部署包

echo "正在创建 LTDKH Bot 独立部署包..."

# 创建临时目录
TEMP_DIR="ltdkh-bot-deployment"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 复制必要的部署文件
cp vps-independent-deploy.sh "$TEMP_DIR/"
cp docker-compose.independent.yml "$TEMP_DIR/"
cp .env.independent "$TEMP_DIR/"
cp nginx.independent.conf "$TEMP_DIR/"
cp VPS-DEPLOYMENT-GUIDE.md "$TEMP_DIR/"
cp Dockerfile "$TEMP_DIR/"
cp requirements.txt "$TEMP_DIR/"
cp main.py "$TEMP_DIR/"

# 复制应用目录
cp -r services "$TEMP_DIR/"
cp -r templates "$TEMP_DIR/"
cp -r static "$TEMP_DIR/"
cp -r sessions "$TEMP_DIR/"
cp -r scripts "$TEMP_DIR/"

# 创建部署说明文件
cat > "$TEMP_DIR/DEPLOY-INSTRUCTIONS.md" << 'EOF'
# LTDKH Bot VPS 部署说明

## 快速部署步骤

1. 将此部署包上传到VPS服务器：
   ```bash
   scp -i "your-key.pem" ltdkh-bot-deployment.tar.gz ubuntu@18.142.231.74:~/
   ```

2. 登录VPS并解压：
   ```bash
   ssh -i "your-key.pem" ubuntu@18.142.231.74
   tar -xzf ltdkh-bot-deployment.tar.gz
   cd ltdkh-bot-deployment
   ```

3. 执行部署脚本：
   ```bash
   chmod +x vps-independent-deploy.sh
   sudo ./vps-independent-deploy.sh
   ```

4. 配置环境变量（编辑 .env.independent 文件）：
   ```bash
   nano .env.independent
   # 设置你的 Telegram Bot Token 和其他配置
   ```

5. 重启服务：
   ```bash
   sudo systemctl restart ltdkh-bot
   sudo systemctl restart nginx
   ```

6. 验证部署：
   ```bash
   sudo systemctl status ltdkh-bot
   curl http://localhost:8013/health
   ```

## 访问应用

- HTTP: http://18.142.231.74:8080
- HTTPS: https://18.142.231.74:8443 (自签名证书)
- 直接访问: http://18.142.231.74:8013

## 管理命令

```bash
# 查看服务状态
sudo systemctl status ltdkh-bot

# 查看日志
sudo journalctl -u ltdkh-bot -f

# 重启服务
sudo systemctl restart ltdkh-bot

# 更新代码
cd /opt/ltdkh-bot
sudo git pull origin main
sudo docker-compose -f docker-compose.independent.yml build
sudo systemctl restart ltdkh-bot
```
EOF

# 创建压缩包
echo "正在创建压缩包..."
tar -czf ltdkh-bot-deployment.tar.gz "$TEMP_DIR"

# 清理临时目录
rm -rf "$TEMP_DIR"

echo "部署包已创建: ltdkh-bot-deployment.tar.gz"
echo "文件大小: $(du -h ltdkh-bot-deployment.tar.gz | cut -f1)"
echo ""
echo "请按照以下步骤部署："
echo "1. 将 ltdkh-bot-deployment.tar.gz 上传到VPS"
echo "2. 在VPS上解压并执行部署脚本"
echo "3. 配置环境变量"
echo "4. 启动服务"
echo ""
echo "详细说明请查看解压后的 DEPLOY-INSTRUCTIONS.md 文件"