#!/bin/bash

# Telegram Session 文件上传脚本
# 用于将本地生成的 session 文件上传到 VPS

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量（请根据实际情况修改）
VPS_IP="your_vps_ip"  # 请替换为你的 VPS IP
VPS_USER="ubuntu"
KEY_FILE="PC999.pem"
REMOTE_PATH="~/LTDKH_BOT"

# 函数：打印带颜色的消息
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

# 函数：检查配置
check_config() {
    print_info "检查配置..."
    
    if [ "$VPS_IP" = "your_vps_ip" ]; then
        print_error "请先修改脚本中的 VPS_IP 配置"
        echo "编辑此文件并将 VPS_IP 设置为你的实际 VPS IP 地址"
        exit 1
    fi
    
    if [ ! -f "$KEY_FILE" ]; then
        print_error "SSH 密钥文件 $KEY_FILE 不存在"
        echo "请确保 SSH 密钥文件路径正确"
        exit 1
    fi
    
    print_success "配置检查通过"
}

# 函数：检查本地 session 文件
check_local_sessions() {
    print_info "检查本地 session 文件..."
    
    if [ ! -d "sessions" ]; then
        print_error "本地 sessions 目录不存在"
        echo "请先运行 python generate_sessions.py 生成 session 文件"
        exit 1
    fi
    
    # 检查 session 文件
    local session_files=()
    for file in sessions/*.session; do
        if [ -f "$file" ]; then
            session_files+=("$file")
        fi
    done
    
    if [ ${#session_files[@]} -eq 0 ]; then
        print_error "未找到任何 .session 文件"
        echo "请先运行 python generate_sessions.py 生成 session 文件"
        exit 1
    fi
    
    print_success "找到 ${#session_files[@]} 个 session 文件："
    for file in "${session_files[@]}"; do
        local size=$(ls -lh "$file" | awk '{print $5}')
        echo "   - $(basename "$file") ($size)"
    done
}

# 函数：测试 VPS 连接
test_vps_connection() {
    print_info "测试 VPS 连接..."
    
    if ssh -i "$KEY_FILE" -o ConnectTimeout=10 -o BatchMode=yes "$VPS_USER@$VPS_IP" "echo 'Connection test successful'" >/dev/null 2>&1; then
        print_success "VPS 连接测试成功"
    else
        print_error "无法连接到 VPS"
        echo "请检查："
        echo "  - VPS IP 地址是否正确: $VPS_IP"
        echo "  - SSH 密钥文件是否正确: $KEY_FILE"
        echo "  - VPS 是否正在运行"
        echo "  - 网络连接是否正常"
        exit 1
    fi
}

# 函数：创建远程目录
create_remote_directories() {
    print_info "创建远程目录结构..."
    
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
set -e
echo "创建项目目录..."
mkdir -p $REMOTE_PATH
cd $REMOTE_PATH
echo "创建 sessions 目录..."
mkdir -p sessions
echo "设置目录权限..."
chmod 755 sessions
echo "远程目录创建完成"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "远程目录创建成功"
    else
        print_error "远程目录创建失败"
        exit 1
    fi
}

# 函数：上传 session 文件
upload_sessions() {
    print_info "开始上传 session 文件..."
    
    # 使用 rsync 同步 sessions 目录
    if rsync -avz --progress -e "ssh -i $KEY_FILE" sessions/ "$VPS_USER@$VPS_IP:$REMOTE_PATH/sessions/"; then
        print_success "Session 文件上传成功"
    else
        print_error "Session 文件上传失败"
        exit 1
    fi
}

# 函数：验证上传结果
verify_upload() {
    print_info "验证上传结果..."
    
    echo "远程 sessions 目录内容："
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
cd $REMOTE_PATH/sessions
echo "文件列表："
ls -la *.session 2>/dev/null || echo "未找到 .session 文件"
echo ""
echo "文件权限和大小："
for file in *.session; do
    if [ -f "\$file" ]; then
        echo "  \$file: \$(ls -lh "\$file" | awk '{print \$1, \$5}')"
    fi
done
EOF
    
    print_success "上传验证完成"
}

# 函数：设置文件权限
set_permissions() {
    print_info "设置 session 文件权限..."
    
    ssh -i "$KEY_FILE" "$VPS_USER@$VPS_IP" << EOF
cd $REMOTE_PATH/sessions
echo "设置 session 文件权限为 600 (仅所有者可读写)..."
chmod 600 *.session 2>/dev/null || true
echo "权限设置完成"
EOF
    
    print_success "文件权限设置完成"
}

# 函数：显示后续步骤
show_next_steps() {
    echo ""
    echo "🎉 Session 文件上传完成！"
    echo "=" * 50
    echo ""
    echo "📋 后续步骤："
    echo "   1. 上传环境配置文件："
    echo "      scp -i $KEY_FILE .env.prod $VPS_USER@$VPS_IP:$REMOTE_PATH/.env"
    echo ""
    echo "   2. 启动服务："
    echo "      ssh -i $KEY_FILE $VPS_USER@$VPS_IP"
    echo "      cd $REMOTE_PATH"
    echo "      sudo systemctl start ltdkh-bot"
    echo ""
    echo "   3. 查看服务状态："
    echo "      sudo systemctl status ltdkh-bot"
    echo ""
    echo "   4. 查看日志："
    echo "      sudo journalctl -u ltdkh-bot -f"
    echo ""
    echo "🌐 部署完成后访问地址："
    echo "   - 主站：https://7575.PRO"
    echo "   - 管理面板：https://7575.PRO/admin"
    echo ""
}

# 主函数
main() {
    echo "🚀 Telegram Session 文件上传工具"
    echo "=" * 50
    echo ""
    
    # 检查配置
    check_config
    
    # 检查本地文件
    check_local_sessions
    
    # 测试连接
    test_vps_connection
    
    # 确认上传
    echo ""
    echo "📋 上传信息："
    echo "   VPS IP: $VPS_IP"
    echo "   用户: $VPS_USER"
    echo "   远程路径: $REMOTE_PATH/sessions/"
    echo ""
    
    read -p "确认上传 session 文件到 VPS？(Y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        print_warning "操作已取消"
        exit 0
    fi
    
    # 执行上传流程
    create_remote_directories
    upload_sessions
    set_permissions
    verify_upload
    
    # 显示后续步骤
    show_next_steps
}

# 脚本入口
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Telegram Session 文件上传工具"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --check-only   仅检查配置和文件，不执行上传"
    echo ""
    echo "使用前请确保："
    echo "  1. 修改脚本中的 VPS_IP 配置"
    echo "  2. 确保 SSH 密钥文件存在"
    echo "  3. 本地已生成 session 文件"
    echo ""
    exit 0
elif [ "$1" = "--check-only" ]; then
    echo "🔍 配置检查模式"
    echo "=" * 30
    check_config
    check_local_sessions
    test_vps_connection
    print_success "所有检查通过，可以执行上传"
    exit 0
else
    main
fi