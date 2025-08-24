#!/bin/bash

# LTDKH Bot SSH连接诊断脚本
# 用于排查VPS连接问题

echo "🔍 LTDKH Bot SSH连接诊断工具"
echo "================================="
echo

# 服务器信息
SERVER_IP="18.142.231.74"
KEY_PATH="/Users/pccc/LTDKH_BOT/DIDI.pem"
ALT_KEY_PATH="/Users/pccc/LTDKH_BOT/LightsailDefaultKey-ap-southeast-1.pem"

echo "📋 服务器信息:"
echo "   IP地址: $SERVER_IP"
echo "   主密钥: $KEY_PATH"
echo "   备用密钥: $ALT_KEY_PATH"
echo

# 检查密钥文件
echo "🔑 检查密钥文件..."
for key in "$KEY_PATH" "$ALT_KEY_PATH"; do
    if [ -f "$key" ]; then
        echo "   ✅ 找到密钥: $key"
        echo "   📄 权限: $(ls -l "$key" | awk '{print $1}')"
        echo "   📝 格式: $(head -1 "$key")"
        echo "   🔒 建议权限: 400"
        
        # 检查权限
        perm=$(stat -f "%A" "$key" 2>/dev/null || stat -c "%a" "$key" 2>/dev/null)
        if [ "$perm" != "400" ]; then
            echo "   ⚠️  权限不正确，正在修复..."
            chmod 400 "$key"
            echo "   ✅ 权限已修复为400"
        fi
    else
        echo "   ❌ 密钥不存在: $key"
    fi
    echo
done

# 测试网络连接
echo "🌐 测试网络连接..."
if ping -c 1 "$SERVER_IP" > /dev/null 2>&1; then
    echo "   ✅ 网络连接正常"
else
    echo "   ❌ 网络连接失败"
    echo "   💡 请检查网络设置或防火墙"
fi
echo

# 测试SSH端口
echo "🔌 测试SSH端口..."
if nc -z "$SERVER_IP" 22 2>/dev/null; then
    echo "   ✅ SSH端口22开放"
else
    echo "   ❌ SSH端口22无法访问"
    echo "   💡 可能的原因:"
    echo "      - 服务器防火墙阻止"
    echo "      - SSH服务未运行"
    echo "      - 使用非标准端口"
fi
echo

# 测试不同用户名和密钥组合
echo "🧪 测试SSH连接..."
users=("ubuntu" "ec2-user" "admin" "root")
keys=("$KEY_PATH" "$ALT_KEY_PATH")

for key in "${keys[@]}"; do
    if [ ! -f "$key" ]; then
        continue
    fi
    
    echo "   🔑 使用密钥: $(basename "$key")"
    
    for user in "${users[@]}"; do
        echo -n "      测试 $user@$SERVER_IP ... "
        
        # 设置超时并测试连接
        if timeout 10 ssh -i "$key" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "$user@$SERVER_IP" "echo 'SUCCESS'" 2>/dev/null | grep -q "SUCCESS"; then
            echo "✅ 成功!"
            echo "   🎉 找到有效连接: $user@$SERVER_IP (密钥: $(basename "$key"))"
            echo
            echo "📋 使用此配置上传文件:"
            echo "   scp -i \"$key\" ltdkh-bot-deployment.tar.gz $user@$SERVER_IP:~/"
            echo
            echo "📋 SSH连接命令:"
            echo "   ssh -i \"$key\" $user@$SERVER_IP"
            echo
            exit 0
        else
            echo "❌ 失败"
        fi
    done
    echo
done

# 如果所有测试都失败
echo "❌ 所有SSH连接测试都失败"
echo
echo "🔧 建议的解决方案:"
echo
echo "1. 📞 联系VPS提供商:"
echo "   - 确认服务器状态和SSH配置"
echo "   - 获取正确的SSH密钥"
echo "   - 确认默认用户名"
echo
echo "2. 🌐 使用VPS控制面板:"
echo "   - 通过Web终端访问服务器"
echo "   - 上传部署包到服务器"
echo "   - 直接在服务器上执行部署"
echo
echo "3. 🔄 重新配置SSH密钥:"
echo "   - 生成新的SSH密钥对"
echo "   - 通过控制面板添加公钥到服务器"
echo "   - 使用新密钥重新连接"
echo
echo "4. 📦 使用替代上传方法:"
echo "   - GitHub Release下载"
echo "   - SFTP客户端 (FileZilla, Cyberduck)"
echo "   - 云存储中转"
echo
echo "详细说明请查看: ALTERNATIVE-UPLOAD-METHODS.md"
echo