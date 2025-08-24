# LTDKH Bot - Telegram 群组监控机器人

一个功能强大的 Telegram 群组监控和统计机器人，支持多账户管理、实时数据统计和 Web 界面展示。

## 🌟 主要功能

- 📊 **群组统计**: 实时监控群组消息数量、用户活跃度
- 👥 **用户排行**: 统计用户发言次数和活跃度排名
- 🔄 **多账户支持**: 支持多个 Telegram 账户同时监控
- 🌐 **Web 界面**: 美观的 Web 界面展示统计数据
- 🐳 **Docker 部署**: 支持 Docker 和 Docker Compose 一键部署
- 🔒 **安全可靠**: 支持 HTTPS、SSL 证书自动续期
- 📱 **响应式设计**: 支持移动端和桌面端访问

## 🚀 快速开始

### 本地开发

1. **克隆项目**
   ```bash
   git clone https://github.com/PengC8899/LTDKH.git
   cd LTDKH
   ```

2. **安装依赖**
   ```bash
   pip install -r requirements.txt
   ```

3. **配置环境变量**
   ```bash
   cp .env.example .env
   # 编辑 .env 文件，填入您的配置
   ```

4. **启动服务**
   ```bash
   # 使用 Docker Compose
   docker-compose up -d
   
   # 或直接运行
   python main.py
   ```

5. **访问应用**
   - 主页: http://localhost:8012
   - 群组统计: http://localhost:8012/ui/groups
   - 用户排行: http://localhost:8012/ui/top_users

### VPS 生产部署

#### 方法一：一键部署脚本

```bash
# 在您的 VPS 上运行
wget https://raw.githubusercontent.com/PengC8899/LTDKH/main/quick-deploy.sh
chmod +x quick-deploy.sh
sudo ./quick-deploy.sh
```

#### 方法二：手动部署

详细部署指南请参考 [DEPLOYMENT.md](DEPLOYMENT.md)

## 📋 环境要求

- Python 3.11+
- Redis 6.0+
- PostgreSQL 12+
- Docker & Docker Compose (推荐)

## 🔧 配置说明

### 必需配置

```env
# Telegram API 配置
API_ID=your_api_id
API_HASH=your_api_hash
BOT_TOKEN=your_bot_token

# 账户配置
ACCOUNT1_PHONE=+1234567890
ACCOUNT1_PASSWORD=your_password

# 数据库配置
DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/dbname
REDIS_URL=redis://localhost:6379/0
```

### 可选配置

```env
# 应用配置
DOMAIN=your-domain.com
ENVIRONMENT=production
DEBUG=false
LOG_LEVEL=INFO
```

## 🌐 域名配置

### DNS 设置

将您的域名（如 `7577.bet`）解析到 VPS IP 地址：

```
类型    名称    值              TTL
A       @       YOUR_VPS_IP    300
A       www     YOUR_VPS_IP    300
```

### SSL 证书

部署脚本会自动申请和配置 Let's Encrypt SSL 证书，支持自动续期。

## 📊 API 接口

### 健康检查
```
GET /health
```

### 群组统计
```
GET /api/groups
```

### 用户排行
```
GET /api/top_users
```

## 🛠️ 开发指南

### 项目结构

```
LTDKH/
├── main.py                 # 主应用入口
├── services/               # 业务逻辑
│   ├── db.py              # 数据库操作
│   ├── redis_client.py    # Redis 客户端
│   ├── scheduler.py       # 任务调度
│   └── filters.py         # 消息过滤
├── templates/             # HTML 模板
├── static/               # 静态文件
├── docker-compose.yml    # 开发环境
├── docker-compose.prod.yml # 生产环境
├── deploy.sh            # 部署脚本
└── requirements.txt     # Python 依赖
```

### 本地开发

```bash
# 启动开发环境
docker-compose up -d

# 查看日志
docker-compose logs -f app

# 重启服务
docker-compose restart app
```

## 🔍 监控和维护

### 服务状态检查

```bash
# 检查系统服务
sudo systemctl status ltdkh-bot

# 检查 Docker 容器
docker-compose -f docker-compose.prod.yml ps

# 查看应用日志
docker-compose -f docker-compose.prod.yml logs -f app
```

### 数据备份

```bash
# 备份数据库
docker exec ltdkh_postgres pg_dump -U postgres tg_watchdog > backup.sql

# 备份 Redis
docker exec ltdkh_redis redis-cli BGSAVE
```

### 应用更新

```bash
# 更新代码
cd /opt/ltdkh-bot
sudo ./deploy.sh --update
```

## 🐛 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   sudo lsof -i :8012
   sudo kill -9 <PID>
   ```

2. **SSL 证书问题**
   ```bash
   sudo certbot renew
   sudo systemctl reload nginx
   ```

3. **数据库连接失败**
   - 检查 `.env.prod` 配置
   - 确认数据库服务运行正常
   - 检查网络连接

4. **Telegram API 错误**
   - 验证 API_ID 和 API_HASH
   - 检查 Bot Token 有效性
   - 确认账户登录状态

## 📈 性能优化

- 使用 Redis 缓存热点数据
- 数据库连接池优化
- Nginx 反向代理和负载均衡
- Docker 资源限制配置
- 定期清理日志文件

## 🔐 安全建议

- 使用强密码和密钥
- 定期更新系统和依赖
- 配置防火墙规则
- 启用 HTTPS 和安全头
- 定期备份重要数据
- 监控异常访问日志

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📞 支持

如果您在使用过程中遇到问题：

1. 查看 [DEPLOYMENT.md](DEPLOYMENT.md) 部署指南
2. 检查 [Issues](https://github.com/PengC8899/LTDKH/issues) 页面
3. 提交新的 Issue 描述问题

---

⭐ 如果这个项目对您有帮助，请给个 Star 支持一下！