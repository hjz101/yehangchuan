#!/bin/zsh
# 启动飞书 Bug 机器人（后台常驻）
set -euo pipefail
cd "$(dirname "$0")/../.."

PID_FILE="Scripts/feishu-bug-bot/.bot.pid"
mkdir -p Scripts/feishu-bug-bot/logs

if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "已在运行（pid $(cat "$PID_FILE")）"
  exit 0
fi

nohup node Scripts/feishu-bug-bot/bug-bot.mjs >> Scripts/feishu-bug-bot/logs/bot.log 2>&1 &
echo $! > "$PID_FILE"
echo "已启动（pid $(cat "$PID_FILE")），日志：Scripts/feishu-bug-bot/logs/bot.log"
