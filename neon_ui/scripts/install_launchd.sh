#!/bin/zsh
# 用途：安装/卸载/查看 com.ltdkh.bot.watchdog 的 launchd 配置
# 使用：
#  1) 安装并加载：  scripts/install_launchd.sh install
#  2) 卸载并移除：  scripts/install_launchd.sh uninstall
#  3) 仅加载：      scripts/install_launchd.sh load
#  4) 仅卸载：      scripts/install_launchd.sh unload
#  5) 查看状态：    scripts/install_launchd.sh status

set -euo pipefail

PLIST_NAME="com.ltdkh.bot.watchdog.plist"
SRC_PLIST="$(pwd)/scripts/mac_launchd/${PLIST_NAME}"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
DEST_PLIST="$LAUNCHD_DIR/${PLIST_NAME}"

ensure_dirs() {
    mkdir -p "$LAUNCHD_DIR"
    mkdir -p "$(pwd)/data/logs"
}

install() {
    ensure_dirs
    local workdir
    workdir="$(pwd)"
    local python_bin
    if [[ -x "${workdir}/.venv/bin/python3.11" ]]; then
        python_bin="${workdir}/.venv/bin/python3.11"
    else
        python_bin="/usr/bin/python3"
    fi
    # 注入核心环境变量
    local BOT_TOKEN TARGET_CHAT_ID DATABASE_URL REDIS_URL
    BOT_TOKEN=$(grep -E '^BOT_TOKEN=' .env | tail -n1 | sed 's/^BOT_TOKEN=//')
    TARGET_CHAT_ID=$(grep -E '^TARGET_CHAT_ID=' .env | tail -n1 | sed 's/^TARGET_CHAT_ID=//')
    DATABASE_URL=$(grep -E '^DATABASE_URL=' .env | tail -n1 | sed 's/^DATABASE_URL=//')
    REDIS_URL=$(grep -E '^REDIS_URL=' .env | tail -n1 | sed 's/^REDIS_URL=//')

    sed "s|__WORKDIR__|${workdir}|g; s|__PYTHON_BIN__|${python_bin}|g; s|__BOT_TOKEN__|${BOT_TOKEN}|g; s|__TARGET_CHAT_ID__|${TARGET_CHAT_ID}|g; s|__DATABASE_URL__|${DATABASE_URL}|g; s|__REDIS_URL__|${REDIS_URL}|g" "$SRC_PLIST" > "$DEST_PLIST"
    launchctl load -w "$DEST_PLIST" || true
    echo "已安装并加载：$DEST_PLIST"
}

uninstall() {
    if [[ -f "$DEST_PLIST" ]]; then
        launchctl unload -w "$DEST_PLIST" || true
        rm -f "$DEST_PLIST"
        echo "已卸载并删除：$DEST_PLIST"
    else
        echo "未发现已安装的 plist：$DEST_PLIST"
    fi
}

load_only() {
    if [[ -f "$DEST_PLIST" ]]; then
        launchctl load -w "$DEST_PLIST" || true
        echo "已加载：$DEST_PLIST"
    else
        echo "未安装 plist，请先执行 install。"
    fi
}

unload_only() {
    if [[ -f "$DEST_PLIST" ]]; then
        launchctl unload -w "$DEST_PLIST" || true
        echo "已卸载：$DEST_PLIST"
    else
        echo "未安装 plist。"
    fi
}

status() {
    launchctl list | grep -i "com.ltdkh.bot.watchdog" || true
}

case "${1:-}" in
    install)
        install ;;
    uninstall)
        uninstall ;;
    load)
        load_only ;;
    unload)
        unload_only ;;
    status)
        status ;;
    *)
        echo "用法: $0 {install|uninstall|load|unload|status}"
        exit 1 ;;
esac


