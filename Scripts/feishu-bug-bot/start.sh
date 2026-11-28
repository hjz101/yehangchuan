#!/bin/zsh
# 启动飞书 Bug 机器人（tmux 常驻会话，退出终端后仍运行）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/Scripts/feishu-bug-bot"
SESSION="feishu-bug-bot"

if [[ -z "${LARKSUITE_CLI_USER_ACCESS_TOKEN:-}" ]]; then
  echo "缺少 LARKSUITE_CLI_USER_ACCESS_TOKEN，请在 Trae 会话中运行本脚本（凭据由会话注入）。" >&2
  exit 1
fi
if ! command -v tmux >/dev/null 2>&1; then
  echo "未找到 tmux，请先安装：brew install tmux" >&2
  exit 1
fi

# 凭据只落在本机，已被 .gitignore 排除
umask 077
{
  echo "export LARKSUITE_CLI_APP_ID='${LARKSUITE_CLI_APP_ID}'"
  echo "export LARKSUITE_CLI_USER_ACCESS_TOKEN='${LARKSUITE_CLI_USER_ACCESS_TOKEN}'"
  echo "export LARKSUITE_CLI_BRAND='${LARKSUITE_CLI_BRAND:-feishu}'"
} > "$DIR/.env"

mkdir -p "$DIR/logs"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  tmux kill-session -t "$SESSION"
fi

tmux new-session -d -s "$SESSION" -c "$ROOT" "exec '$DIR/run.sh' >> '$DIR/logs/bot.log' 2>&1"
sleep 1

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "已启动（tmux 会话 $SESSION）"
  echo "日志：$DIR/logs/bot.log"
else
  echo "启动失败，请查看日志：$DIR/logs/bot.log" >&2
  exit 1
fi
