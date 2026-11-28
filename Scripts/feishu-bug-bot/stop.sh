#!/bin/zsh
# 停止飞书 Bug 机器人
set -euo pipefail
cd "$(dirname "$0")/../.."

PID_FILE="Scripts/feishu-bug-bot/.bot.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "未运行"
  exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "已停止（pid $PID）"
else
  echo "进程已不存在，清理 pid 文件"
fi
rm -f "$PID_FILE"
