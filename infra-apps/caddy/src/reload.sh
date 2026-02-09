#!/usr/bin/env bash
# 重载 Caddy 配置（无需重启容器）
# 使用方式：
#   服务器： cd /srv/caddy && ./reload.sh

set -euo pipefail

echo "🔄 Reloading Caddy configuration..."

# 使用 caddy reload 命令优雅重载配置
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile

if [ $? -eq 0 ]; then
  echo "✅ Caddy configuration reloaded successfully!"
else
  echo "❌ Failed to reload Caddy configuration"
  echo "Try checking the logs: docker compose logs caddy --tail=50"
  exit 1
fi
