# LTDKH Bot 替代上传方案

由于SSH连接问题，以下是几种替代的文件上传方法：

## 方法1: 使用SFTP客户端（推荐）

### FileZilla (免费)
1. 下载并安装 FileZilla Client
2. 连接设置：
   - 协议: SFTP
   - 主机: 18.142.231.74
   - 端口: 22
   - 用户名: ubuntu
   - 密钥文件: `/Users/pccc/LTDKH_BOT/DIDI (1).pem`

### Cyberduck (免费)
1. 下载并安装 Cyberduck
2. 新建连接：
   - 协议: SFTP (SSH File Transfer Protocol)
   - 服务器: 18.142.231.74
   - 用户名: ubuntu
   - SSH Private Key: 选择 `DIDI (1).pem` 文件

## 方法2: 使用云存储中转

### 通过GitHub Release
```bash
# 1. 将部署包添加到Git并推送
git add ltdkh-bot-deployment.tar.gz
git commit -m "Add deployment package"
git push origin main

# 2. 在VPS上直接下载
ssh -i "DIDI (1).pem" ubuntu@18.142.231.74
wget https://github.com/PengC8899/LTDKH/raw/main/ltdkh-bot-deployment.tar.gz
```

### 通过临时文件分享服务
1. 上传 `ltdkh-bot-deployment.tar.gz` 到：
   - WeTransfer (wetransfer.com)
   - SendAnywhere (send-anywhere.com)
   - 或其他文件分享服务

2. 在VPS上下载：
```bash
ssh -i "DIDI (1).pem" ubuntu@18.142.231.74
wget "分享链接" -O ltdkh-bot-deployment.tar.gz
```

## 方法3: 使用VPS控制面板

如果您的VPS提供商有Web控制面板：
1. 登录VPS控制面板
2. 使用文件管理器上传 `ltdkh-bot-deployment.tar.gz`
3. 通过Web终端执行部署命令

## 方法4: 重新配置SSH密钥

### 检查密钥是否正确
```bash
# 查看密钥指纹
ssh-keygen -l -f "/Users/pccc/LTDKH_BOT/DIDI (1).pem"

# 查看公钥
ssh-keygen -y -f "/Users/pccc/LTDKH_BOT/DIDI (1).pem"
```

### 如果需要重新配置
1. 生成新的SSH密钥对：
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/vps_key
```

2. 将公钥添加到VPS（需要通过VPS控制面板或其他方式）

## 推荐流程

### 最简单的方法（GitHub）：
```bash
# 1. 本地添加部署包到Git
git add ltdkh-bot-deployment.tar.gz UPLOAD-AND-DEPLOY.md ALTERNATIVE-UPLOAD-METHODS.md
git commit -m "Add deployment package and upload guides"
git push origin main

# 2. 在VPS上克隆或拉取代码
# 如果VPS上还没有代码：
git clone https://github.com/PengC8899/LTDKH.git
cd LTDKH

# 如果已有代码：
cd LTDKH
git pull origin main

# 3. 解压并部署
tar -xzf ltdkh-bot-deployment.tar.gz
cd ltdkh-bot-deployment
sudo ./vps-independent-deploy.sh
```

### 使用SFTP客户端：
1. 使用FileZilla或Cyberduck连接VPS
2. 上传 `ltdkh-bot-deployment.tar.gz` 到用户主目录
3. 通过SSH执行部署命令

## 部署后的验证步骤

无论使用哪种上传方法，部署完成后都要执行：

```bash
# 1. 解压部署包
tar -xzf ltdkh-bot-deployment.tar.gz
cd ltdkh-bot-deployment

# 2. 执行部署
sudo ./vps-independent-deploy.sh

# 3. 配置环境变量
nano .env.independent
# 设置 TELEGRAM_BOT_TOKEN 等必要变量

# 4. 重启服务
sudo systemctl restart ltdkh-bot nginx

# 5. 验证部署
sudo systemctl status ltdkh-bot
curl http://localhost:8013/health
```

## 访问地址

部署成功后访问：
- HTTP: http://18.142.231.74:8080
- HTTPS: https://18.142.231.74:8443
- 直接: http://18.142.231.74:8013

## 故障排除

如果仍然无法连接VPS：
1. 检查VPS是否正在运行
2. 确认IP地址是否正确
3. 检查VPS防火墙设置
4. 联系VPS提供商确认SSH配置
5. 尝试使用VPS控制面板的Web终端

选择最适合您的方法进行部署！