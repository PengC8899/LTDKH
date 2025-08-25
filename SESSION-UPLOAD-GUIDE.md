# Telegram Session 文件上传指南

## 概述

使用现有的 `.session` 文件可以避免在 VPS 上重复输入验证码，实现无人值守部署。

## 🔹 完整流程

### 1. 本地生成 Session 文件

#### 方法一：使用项目代码生成
```bash
# 在本地项目目录下
cd /Users/pccc/LTDKH_BOT

# 激活虚拟环境
source .venv/bin/activate

# 运行一次主程序（会提示输入验证码）
python main.py
```

#### 方法二：使用独立脚本生成
创建 `generate_sessions.py`：
```python
import asyncio
from telethon import TelegramClient
import os
from dotenv import load_dotenv

load_dotenv('.env.prod')

async def generate_sessions():
    # 账户1
    client1 = TelegramClient(
        "sessions/account1",
        os.getenv('ACCOUNT1_API_ID'),
        os.getenv('ACCOUNT1_API_HASH')
    )
    
    # 账户2
    client2 = TelegramClient(
        "sessions/account2",
        os.getenv('ACCOUNT2_API_ID'),
        os.getenv('ACCOUNT2_API_HASH')
    )
    
    # 账户3
    client3 = TelegramClient(
        "sessions/account3",
        os.getenv('ACCOUNT3_API_ID'),
        os.getenv('ACCOUNT3_API_HASH')
    )
    
    print("正在连接账户1...")
    await client1.start(phone=os.getenv('ACCOUNT1_PHONE'))
    print("账户1 连接成功！")
    
    print("正在连接账户2...")
    await client2.start(phone=os.getenv('ACCOUNT2_PHONE'))
    print("账户2 连接成功！")
    
    print("正在连接账户3...")
    await client3.start(phone=os.getenv('ACCOUNT3_PHONE'))
    print("账户3 连接成功！")
    
    await client1.disconnect()
    await client2.disconnect()
    await client3.disconnect()
    
    print("\n✅ 所有 session 文件已生成完成！")
    print("生成的文件：")
    print("- sessions/account1.session")
    print("- sessions/account2.session")
    print("- sessions/account3.session")

if __name__ == "__main__":
    # 确保 sessions 目录存在
    os.makedirs("sessions", exist_ok=True)
    asyncio.run(generate_sessions())
```

运行生成脚本：
```bash
python generate_sessions.py
```

### 2. 上传 Session 文件到 VPS

#### 使用 SCP 命令上传
```bash
# 上传单个文件
scp -i PC999.pem sessions/account1.session ubuntu@your_vps_ip:~/LTDKH_BOT/sessions/
scp -i PC999.pem sessions/account2.session ubuntu@your_vps_ip:~/LTDKH_BOT/sessions/
scp -i PC999.pem sessions/account3.session ubuntu@your_vps_ip:~/LTDKH_BOT/sessions/

# 或者批量上传整个 sessions 目录
scp -i PC999.pem -r sessions/ ubuntu@your_vps_ip:~/LTDKH_BOT/
```

#### 使用 rsync 同步（推荐）
```bash
# 同步 sessions 目录
rsync -avz -e "ssh -i PC999.pem" sessions/ ubuntu@your_vps_ip:~/LTDKH_BOT/sessions/
```

### 3. 一键上传脚本

创建 `upload-sessions.sh`：
```bash
#!/bin/bash

# VPS 配置
VPS_IP="your_vps_ip"
VPS_USER="ubuntu"
KEY_FILE="PC999.pem"
REMOTE_PATH="~/LTDKH_BOT"

echo "🚀 开始上传 Session 文件到 VPS..."

# 检查本地 sessions 目录
if [ ! -d "sessions" ]; then
    echo "❌ 本地 sessions 目录不存在，请先生成 session 文件"
    exit 1
fi

# 检查 session 文件
if [ ! -f "sessions/account1.session" ] || [ ! -f "sessions/account2.session" ] || [ ! -f "sessions/account3.session" ]; then
    echo "❌ Session 文件不完整，请检查以下文件是否存在："
    echo "   - sessions/account1.session"
    echo "   - sessions/account2.session"
    echo "   - sessions/account3.session"
    exit 1
fi

echo "📁 检查到以下 session 文件："
ls -la sessions/*.session

# 创建远程 sessions 目录
echo "📂 创建远程 sessions 目录..."
ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" "mkdir -p $REMOTE_PATH/sessions"

# 上传 session 文件
echo "📤 上传 session 文件..."
rsync -avz -e "ssh -i $KEY_FILE" sessions/ "$VPS_USER@$VPS_IP:$REMOTE_PATH/sessions/"

if [ $? -eq 0 ]; then
    echo "✅ Session 文件上传成功！"
    echo "📋 验证远程文件："
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" "ls -la $REMOTE_PATH/sessions/"
else
    echo "❌ Session 文件上传失败！"
    exit 1
fi

echo "🎉 上传完成！现在可以在 VPS 上启动服务了。"
```

使用上传脚本：
```bash
# 给脚本执行权限
chmod +x upload-sessions.sh

# 修改脚本中的 VPS_IP
vim upload-sessions.sh

# 执行上传
./upload-sessions.sh
```

### 4. VPS 上启动服务

```bash
# SSH 连接到 VPS
ssh -i PC999.pem ubuntu@your_vps_ip

# 进入项目目录
cd ~/LTDKH_BOT

# 检查 session 文件
ls -la sessions/

# 启动服务
sudo systemctl start ltdkh-bot

# 查看服务状态
sudo systemctl status ltdkh-bot

# 查看日志
sudo journalctl -u ltdkh-bot -f
```

## 🔹 完整自动化脚本

创建 `deploy-with-sessions.sh`：
```bash
#!/bin/bash

# 配置变量
VPS_IP="your_vps_ip"
VPS_USER="ubuntu"
KEY_FILE="PC999.pem"
REMOTE_PATH="~/LTDKH_BOT"

echo "🚀 LTDKH Bot 完整部署流程（包含 Session 文件）"
echo "================================================"

# 步骤1：检查本地环境
echo "📋 步骤1：检查本地环境..."
if [ ! -f ".env.prod" ]; then
    echo "❌ .env.prod 文件不存在"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "❌ SSH 密钥文件 $KEY_FILE 不存在"
    exit 1
fi

# 步骤2：生成 Session 文件（如果不存在）
echo "📋 步骤2：检查/生成 Session 文件..."
if [ ! -d "sessions" ] || [ ! -f "sessions/account1.session" ]; then
    echo "⚠️  Session 文件不存在，需要先生成"
    echo "请运行以下命令生成 session 文件："
    echo "python generate_sessions.py"
    echo "然后重新运行此脚本"
    exit 1
fi

# 步骤3：推送代码到 GitHub
echo "📋 步骤3：推送最新代码到 GitHub..."
git add .
git commit -m "Update deployment files with session support" || true
git push origin main

# 步骤4：在 VPS 上拉取最新代码
echo "📋 步骤4：在 VPS 上更新代码..."
ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << 'EOF'
cd ~/LTDKH_BOT
git pull origin main
EOF

# 步骤5：上传环境配置和 Session 文件
echo "📋 步骤5：上传配置文件..."
scp -i "$KEY_FILE" .env.prod "$VPS_USER@$VPS_IP:$REMOTE_PATH/.env"
rsync -avz -e "ssh -i $KEY_FILE" sessions/ "$VPS_USER@$VPS_IP:$REMOTE_PATH/sessions/"

# 步骤6：在 VPS 上重启服务
echo "📋 步骤6：重启服务..."
ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << 'EOF'
cd ~/LTDKH_BOT
sudo systemctl stop ltdkh-bot || true
sudo docker-compose -f docker-compose.vps.yml down || true
sudo docker-compose -f docker-compose.vps.yml up -d
sudo systemctl start ltdkh-bot
EOF

# 步骤7：验证部署
echo "📋 步骤7：验证部署状态..."
ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << 'EOF'
echo "🔍 服务状态："
sudo systemctl status ltdkh-bot --no-pager
echo ""
echo "🔍 Docker 容器状态："
sudo docker-compose -f ~/LTDKH_BOT/docker-compose.vps.yml ps
echo ""
echo "🔍 最近日志："
sudo journalctl -u ltdkh-bot --no-pager -n 10
EOF

echo "✅ 部署完成！"
echo "🌐 访问地址：https://7575.PRO"
echo "📊 监控面板：https://7575.PRO/admin"
```

## 🔹 注意事项

### 安全提醒
- **⚠️ Session 文件包含账号登录凭证，等同于账号密码**
- 不要将 `.session` 文件提交到 Git 仓库
- 定期备份 session 文件
- 如果账号被风控或修改密码，需要重新生成 session 文件

### 文件权限
```bash
# 设置 session 文件权限（仅所有者可读写）
chmod 600 sessions/*.session
```

### Docker Compose 配置
确保 `docker-compose.vps.yml` 中正确挂载了 sessions 目录：
```yaml
volumes:
  - ./sessions:/app/sessions:ro  # 只读挂载
```

### 故障排除

#### Session 文件失效
```bash
# 删除失效的 session 文件
rm sessions/account*.session

# 重新生成
python generate_sessions.py

# 重新上传
./upload-sessions.sh
```

#### 权限问题
```bash
# 在 VPS 上修复权限
sudo chown -R ubuntu:ubuntu ~/LTDKH_BOT/sessions/
chmod 600 ~/LTDKH_BOT/sessions/*.session
```

## 🔹 快速命令参考

```bash
# 本地生成 sessions
python generate_sessions.py

# 上传到 VPS
./upload-sessions.sh

# 完整部署
./deploy-with-sessions.sh

# VPS 上重启服务
ssh -i PC999.pem ubuntu@your_vps_ip "sudo systemctl restart ltdkh-bot"

# 查看服务状态
ssh -i PC999.pem ubuntu@your_vps_ip "sudo systemctl status ltdkh-bot"
```

通过这个流程，你可以实现完全无人值守的部署，不需要在 VPS 上手动输入验证码。