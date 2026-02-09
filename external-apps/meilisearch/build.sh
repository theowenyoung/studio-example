#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境
detect_environment

SERVICE_BASE="meilisearch"
set_docker_service_name "$SERVICE_BASE"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_BASE (version: $VERSION)"
echo "🐳 Docker service name: $DOCKER_SERVICE_NAME"

rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# 获取环境变量
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

# 生成 docker-compose 配置（使用 envsubst 注入服务名）
export DOCKER_SERVICE_NAME
envsubst < "$SCRIPT_DIR/docker-compose.prod.yml" > "$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

# 写入版本号
echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

# 生成部署摘要
generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

echo "✅ $SERVICE_BASE built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
