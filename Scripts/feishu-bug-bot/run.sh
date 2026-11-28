#!/bin/zsh
# LaunchAgent/tmux 入口：加载 AAMP 应用凭据后启动机器人
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/../.."

if [[ -f "$DIR/.aamp.env" ]]; then
  set -a
  source "$DIR/.aamp.env"
  set +a
fi

exec /Users/a138/.local/node/bin/node "$DIR/bug-bot.mjs"
