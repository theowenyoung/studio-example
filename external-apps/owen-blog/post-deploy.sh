#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境
detect_environment

CONFIG_FILE="$SCRIPT_DIR/$DEPLOY_DIST/meilisearch-docs-scraper-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "⚠️  Config file not found: $CONFIG_FILE"
  echo "   Run 'mise run build-owen-blog' first to generate it."
  exit 1
fi

# 获取环境变量
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/.env.temp"
source "$SCRIPT_DIR/.env.temp"
trap "rm -f $SCRIPT_DIR/.env.temp" EXIT

echo "⏳ Waiting for service to be ready..."

echo "🔍 Running docs-scraper to build search index..."
echo "   Host: $MEILISEARCH_HOST_URL"
echo "   Config: $CONFIG_FILE"

docker run -t --rm \
  -e MEILISEARCH_HOST_URL="$MEILISEARCH_HOST_URL" \
  -e MEILISEARCH_API_KEY="$MEILISEARCH_API_KEY" \
  -v "$CONFIG_FILE:/docs-scraper/config.json" \
  getmeili/docs-scraper:v0.12.11 pipenv run ./docs_scraper config.json

echo "✅ Search index updated successfully"
