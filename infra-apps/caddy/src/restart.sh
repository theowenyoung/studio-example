#!/usr/bin/env bash
# 重启 Caddy 容器
# 使用方式：
#   服务器： cd /srv/caddy && ./restart.sh

set -euo pipefail

echo "🔄 Restarting Caddy container..."

docker compose restart caddy

if [ $? -eq 0 ]; then
  echo "✅ Caddy restarted successfully!"
  echo "Checking status..."
  docker compose ps caddy
else
  echo "❌ Failed to restart Caddy"
  exit 1
fi
