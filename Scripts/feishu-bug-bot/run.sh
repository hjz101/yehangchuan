#!/bin/zsh
# LaunchAgent 入口：加载本地凭据后启动机器人
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/../.."

if [[ -f "$DIR/.env" ]]; then
  set -a
  source "$DIR/.env"
  set +a
fi

exec /Users/a138/.local/node/bin/node "$DIR/bug-bot.mjs"
