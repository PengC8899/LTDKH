#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Telegram Session 文件生成脚本
用于生成 Telegram 客户端的 session 文件，避免在 VPS 上重复输入验证码
"""

import asyncio
import os
import sys
from pathlib import Path
from telethon import TelegramClient
from dotenv import load_dotenv

# 加载环境变量
load_dotenv('.env.prod')

async def generate_sessions():
    """生成所有账户的 session 文件"""
    
    # 确保 sessions 目录存在
    sessions_dir = Path("sessions")
    sessions_dir.mkdir(exist_ok=True)
    
    print("🚀 开始生成 Telegram Session 文件...")
    print("=" * 50)
    
    # 账户配置
    accounts = [
        {
            'name': 'account1',
            'api_id': os.getenv('ACCOUNT1_API_ID'),
            'api_hash': os.getenv('ACCOUNT1_API_HASH'),
            'phone': os.getenv('ACCOUNT1_PHONE')
        },
        {
            'name': 'account2',
            'api_id': os.getenv('ACCOUNT2_API_ID'),
            'api_hash': os.getenv('ACCOUNT2_API_HASH'),
            'phone': os.getenv('ACCOUNT2_PHONE')
        },
        {
            'name': 'account3',
            'api_id': os.getenv('ACCOUNT3_API_ID'),
            'api_hash': os.getenv('ACCOUNT3_API_HASH'),
            'phone': os.getenv('ACCOUNT3_PHONE')
        }
    ]
    
    # 检查环境变量
    missing_vars = []
    for account in accounts:
        if not account['api_id'] or not account['api_hash'] or not account['phone']:
            missing_vars.append(account['name'])
    
    if missing_vars:
        print(f"❌ 缺少以下账户的环境变量配置: {', '.join(missing_vars)}")
        print("请检查 .env.prod 文件中的配置")
        return False
    
    # 生成 session 文件
    success_count = 0
    
    for account in accounts:
        try:
            print(f"\n📱 正在处理 {account['name']}...")
            
            session_path = f"sessions/{account['name']}"
            
            # 检查是否已存在 session 文件
            if Path(f"{session_path}.session").exists():
                print(f"⚠️  {account['name']}.session 已存在")
                choice = input(f"是否重新生成 {account['name']} 的 session？(y/N): ").strip().lower()
                if choice not in ['y', 'yes']:
                    print(f"⏭️  跳过 {account['name']}")
                    success_count += 1
                    continue
                else:
                    # 删除现有文件
                    Path(f"{session_path}.session").unlink(missing_ok=True)
            
            # 创建客户端
            client = TelegramClient(
                session_path,
                int(account['api_id']),
                account['api_hash']
            )
            
            print(f"🔗 正在连接 {account['name']} ({account['phone']})...")
            
            # 启动客户端（会提示输入验证码）
            await client.start(phone=account['phone'])
            
            # 验证连接
            me = await client.get_me()
            print(f"✅ {account['name']} 连接成功！")
            print(f"   用户名: @{me.username or 'N/A'}")
            print(f"   姓名: {me.first_name} {me.last_name or ''}")
            print(f"   ID: {me.id}")
            
            # 断开连接
            await client.disconnect()
            
            success_count += 1
            
        except Exception as e:
            print(f"❌ {account['name']} 生成失败: {str(e)}")
            continue
    
    print("\n" + "=" * 50)
    print(f"🎉 Session 文件生成完成！成功: {success_count}/{len(accounts)}")
    
    if success_count > 0:
        print("\n📁 生成的文件：")
        for session_file in sessions_dir.glob("*.session"):
            file_size = session_file.stat().st_size
            print(f"   - {session_file.name} ({file_size} bytes)")
        
        print("\n📋 下一步操作：")
        print("   1. 运行 ./upload-sessions.sh 上传到 VPS")
        print("   2. 或运行 ./deploy-with-sessions.sh 完整部署")
    
    return success_count == len(accounts)

def check_requirements():
    """检查运行环境"""
    
    # 检查 .env.prod 文件
    if not Path('.env.prod').exists():
        print("❌ .env.prod 文件不存在")
        print("请先创建生产环境配置文件")
        return False
    
    # 检查必要的包
    try:
        import telethon
        import dotenv
    except ImportError as e:
        print(f"❌ 缺少必要的 Python 包: {e}")
        print("请运行: pip install telethon python-dotenv")
        return False
    
    return True

def main():
    """主函数"""
    
    print("📱 Telegram Session 文件生成器")
    print("=" * 50)
    
    # 检查运行环境
    if not check_requirements():
        sys.exit(1)
    
    # 显示说明
    print("\n📋 说明：")
    print("   - 此脚本将为每个账户生成 .session 文件")
    print("   - 生成过程中需要输入手机验证码")
    print("   - 生成的文件可直接上传到 VPS 使用")
    print("   - ⚠️  请确保网络连接稳定")
    
    # 确认继续
    print("\n" + "-" * 30)
    choice = input("是否继续生成 session 文件？(Y/n): ").strip().lower()
    if choice in ['n', 'no']:
        print("❌ 操作已取消")
        sys.exit(0)
    
    # 运行生成流程
    try:
        success = asyncio.run(generate_sessions())
        if success:
            print("\n🎉 所有 session 文件生成成功！")
            sys.exit(0)
        else:
            print("\n⚠️  部分 session 文件生成失败，请检查错误信息")
            sys.exit(1)
    except KeyboardInterrupt:
        print("\n❌ 操作被用户中断")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ 生成过程中发生错误: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()