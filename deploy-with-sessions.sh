#!/bin/bash

# LTDKH Bot 完整部署脚本（包含 Session 文件）
# 自动化部署流程：代码同步 -> 文件上传 -> 服务启动

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 配置变量（请根据实际情况修改）
VPS_IP="54.254.221.99"  # VPS 公网 IP
VPS_USER="ubuntu"
KEY_FILE="PC999.pem"
REMOTE_PATH="~/LTDKH_BOT"
GIT_REPO="https://github.com/PengC8899/LTDKH.git"

# 函数：打印带颜色的消息
print_step() {
    echo -e "${PURPLE}📋 步骤 $1: $2${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 函数：检查本地环境
check_local_environment() {
    print_step "1" "检查本地环境"
    
    # 检查必要文件
    local required_files=(".env.prod" "$KEY_FILE" "docker-compose.vps.yml")
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "必要文件 $file 不存在"
            return 1
        fi
    done
    
    # 检查 sessions 目录
    if [ ! -d "sessions" ]; then
        print_error "sessions 目录不存在"
        echo "请先运行: python generate_sessions.py"
        return 1
    fi
    
    # 检查 session 文件
    local session_count=$(ls sessions/*.session 2>/dev/null | wc -l)
    if [ $session_count -eq 0 ]; then
        print_error "未找到 session 文件"
        echo "请先运行: python generate_sessions.py"
        return 1
    fi
    
    # 检查 Git 状态
    if [ -d ".git" ]; then
        local git_status=$(git status --porcelain)
        if [ -n "$git_status" ]; then
            print_warning "检测到未提交的更改"
            echo "$git_status"
        fi
    fi
    
    print_success "本地环境检查通过 (找到 $session_count 个 session 文件)"
}

# 函数：同步代码到 GitHub
sync_code_to_github() {
    print_step "2" "同步代码到 GitHub"
    
    if [ ! -d ".git" ]; then
        print_warning "不是 Git 仓库，跳过代码同步"
        return 0
    fi
    
    # 添加所有更改（排除敏感文件）
    git add .
    
    # 检查是否有更改需要提交
    if git diff --cached --quiet; then
        print_info "没有新的更改需要提交"
    else
        # 提交更改
        local commit_msg="Deploy: Update configuration and deployment files $(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "$commit_msg"
        print_success "代码已提交: $commit_msg"
    fi
    
    # 推送到远程仓库
    print_info "推送代码到 GitHub..."
    if git push origin main; then
        print_success "代码推送成功"
    else
        print_error "代码推送失败"
        return 1
    fi
}

# 函数：测试 VPS 连接
test_vps_connection() {
    print_step "3" "测试 VPS 连接"
    
    if [ "$VPS_IP" = "your_vps_ip" ]; then
        print_error "请先修改脚本中的 VPS_IP 配置"
        return 1
    fi
    
    print_info "连接到 $VPS_USER@$VPS_IP..."
    if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o BatchMode=yes "$VPS_USER@$VPS_IP" "echo 'VPS 连接成功'" >/dev/null 2>&1; then
        print_success "VPS 连接测试通过"
    else
        print_error "无法连接到 VPS"
        echo "请检查 VPS IP、SSH 密钥和网络连接"
        return 1
    fi
}

# 函数：在 VPS 上更新代码
update_vps_code() {
    print_step "4" "在 VPS 上更新代码"
    
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
set -e
echo "检查项目目录..."
if [ ! -d "$REMOTE_PATH" ]; then
    echo "克隆项目仓库..."
    git clone $GIT_REPO $REMOTE_PATH
else
    echo "更新项目代码..."
    cd $REMOTE_PATH
    git fetch origin
    git reset --hard origin/main
fi
echo "代码更新完成"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "VPS 代码更新成功"
    else
        print_error "VPS 代码更新失败"
        return 1
    fi
}

# 函数：上传配置文件和 Session 文件
upload_files() {
    print_step "5" "上传配置文件和 Session 文件"
    
    # 创建远程目录
    print_info "创建远程目录结构..."
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" "mkdir -p $REMOTE_PATH/sessions"
    
    # 上传环境配置文件
    print_info "上传环境配置文件..."
    if scp -i "$KEY_FILE" .env.prod "$VPS_USER@$VPS_IP:$REMOTE_PATH/.env"; then
        print_success "环境配置文件上传成功"
    else
        print_error "环境配置文件上传失败"
        return 1
    fi
    
    # 上传 Session 文件
    print_info "上传 Session 文件..."
    if rsync -avz --progress -e "ssh -i $KEY_FILE" sessions/ "$VPS_USER@$VPS_IP:$REMOTE_PATH/sessions/"; then
        print_success "Session 文件上传成功"
    else
        print_error "Session 文件上传失败"
        return 1
    fi
    
    # 设置文件权限
    print_info "设置文件权限..."
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
cd $REMOTE_PATH
chmod 600 .env
chmod 600 sessions/*.session
echo "文件权限设置完成"
EOF
}

# 函数：停止现有服务
stop_existing_services() {
    print_step "6" "停止现有服务"
    
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
cd $REMOTE_PATH
echo "停止 systemd 服务..."
sudo systemctl stop ltdkh-bot || true
echo "停止 Docker 容器..."
sudo docker-compose -f docker-compose.vps.yml down || true
echo "清理旧容器和镜像..."
sudo docker system prune -f || true
echo "服务停止完成"
EOF
    
    print_success "现有服务已停止"
}

# 函数：启动服务
start_services() {
    print_step "7" "启动服务"
    
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
set -e
cd $REMOTE_PATH
echo "构建并启动 Docker 容器..."
sudo docker-compose -f docker-compose.vps.yml up -d --build
echo "等待容器启动..."
sleep 10
echo "启动 systemd 服务..."
sudo systemctl start ltdkh-bot
echo "启用开机自启..."
sudo systemctl enable ltdkh-bot
echo "服务启动完成"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        return 1
    fi
}

# 函数：验证部署
verify_deployment() {
    print_step "8" "验证部署状态"
    
    print_info "检查服务状态..."
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << 'EOF'
echo "=== Systemd 服务状态 ==="
sudo systemctl status ltdkh-bot --no-pager || true
echo ""
echo "=== Docker 容器状态 ==="
sudo docker-compose -f ~/LTDKH_BOT/docker-compose.vps.yml ps
echo ""
echo "=== 最近日志 ==="
sudo journalctl -u ltdkh-bot --no-pager -n 5 || true
echo ""
echo "=== 端口监听状态 ==="
sudo netstat -tlnp | grep -E ":(80|443|8012)" || echo "未找到监听端口"
EOF
    
    print_success "部署验证完成"
}

# 函数：显示部署结果
show_deployment_result() {
    echo ""
    echo "🎉 LTDKH Bot 部署完成！"
    echo "=" * 60
    echo ""
    echo "📊 部署信息："
    echo "   VPS IP: $VPS_IP"
    echo "   项目路径: $REMOTE_PATH"
    echo "   服务名称: ltdkh-bot"
    echo ""
    echo "🌐 访问地址："
    echo "   主站: https://7575.PRO"
    echo "   管理面板: https://7575.PRO/admin"
    echo ""
    echo "📋 常用管理命令："
    echo "   查看服务状态: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'sudo systemctl status ltdkh-bot'"
    echo "   查看实时日志: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'sudo journalctl -u ltdkh-bot -f'"
    echo "   重启服务: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'sudo systemctl restart ltdkh-bot'"
    echo "   停止服务: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'sudo systemctl stop ltdkh-bot'"
    echo ""
    echo "🔧 Docker 管理命令："
    echo "   查看容器: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'cd $REMOTE_PATH && sudo docker-compose -f docker-compose.vps.yml ps'"
    echo "   查看日志: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'cd $REMOTE_PATH && sudo docker-compose -f docker-compose.vps.yml logs -f'"
    echo "   重启容器: ssh -i $KEY_FILE $VPS_USER@$VPS_IP 'cd $REMOTE_PATH && sudo docker-compose -f docker-compose.vps.yml restart'"
    echo ""
}

# 函数：错误处理
handle_error() {
    local exit_code=$?
    print_error "部署过程中发生错误 (退出码: $exit_code)"
    echo ""
    echo "🔍 故障排除建议："
    echo "   1. 检查网络连接"
    echo "   2. 验证 VPS 配置和 SSH 密钥"
    echo "   3. 查看详细错误信息"
    echo "   4. 检查 VPS 磁盘空间和内存"
    echo ""
    echo "📞 获取帮助："
    echo "   - 查看部署文档: cat VPS-DEPLOYMENT-GUIDE.md"
    echo "   - 查看快速指南: cat VPS-QUICK-START.md"
    echo ""
    exit $exit_code
}

# 主函数
main() {
    # 设置错误处理
    trap 'handle_error' ERR
    
    echo "🚀 LTDKH Bot 完整部署流程"
    echo "=" * 60
    echo ""
    
    # 显示配置信息
    echo "📋 部署配置："
    echo "   VPS IP: $VPS_IP"
    echo "   用户: $VPS_USER"
    echo "   SSH 密钥: $KEY_FILE"
    echo "   远程路径: $REMOTE_PATH"
    echo "   Git 仓库: $GIT_REPO"
    echo ""
    
    # 确认部署
    read -p "确认开始部署？(Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        print_warning "部署已取消"
        exit 0
    fi
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行部署步骤
    check_local_environment
    sync_code_to_github
    test_vps_connection
    update_vps_code
    upload_files
    stop_existing_services
    start_services
    verify_deployment
    
    # 计算部署时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 显示结果
    show_deployment_result
    echo "⏱️  部署耗时: ${duration} 秒"
    echo ""
}

# 脚本入口
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "LTDKH Bot 完整部署脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --check-only   仅检查环境，不执行部署"
    echo "  --no-git       跳过 Git 操作"
    echo ""
    echo "部署流程:"
    echo "  1. 检查本地环境"
    echo "  2. 同步代码到 GitHub"
    echo "  3. 测试 VPS 连接"
    echo "  4. 在 VPS 上更新代码"
    echo "  5. 上传配置文件和 Session 文件"
    echo "  6. 停止现有服务"
    echo "  7. 启动服务"
    echo "  8. 验证部署状态"
    echo ""
    echo "使用前请确保:"
    echo "  - 修改脚本中的 VPS_IP 配置"
    echo "  - 本地存在 .env.prod 和 session 文件"
    echo "  - SSH 密钥文件可用"
    echo ""
    exit 0
elif [ "$1" = "--check-only" ]; then
    echo "🔍 环境检查模式"
    echo "=" * 30
    check_local_environment
    test_vps_connection
    print_success "环境检查通过，可以执行部署"
    exit 0
else
    main
fi