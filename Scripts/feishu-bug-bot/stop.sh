#!/bin/zsh
# 停止飞书 Bug 机器人
set -euo pipefail
SESSION="feishu-bug-bot"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
  echo "已停止（tmux 会话 $SESSION）"
else
  echo "未在运行"
fi
