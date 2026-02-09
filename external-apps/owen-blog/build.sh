#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境
detect_environment

SERVICE_BASE="owen-blog"
set_docker_service_name "$SERVICE_BASE"
REPO_URL="https://github.com/theowenyoung/blog"
VERSION="$(get_version)"
IMAGE="$ECR_REGISTRY/studio/$SERVICE_BASE"

echo "🔨 Building $SERVICE_BASE (version: $VERSION)"
echo "🐳 Docker service name: $DOCKER_SERVICE_NAME"

# 获取 GitHub token
echo "🔐 Fetching GitHub token from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/.env.temp"
source "$SCRIPT_DIR/.env.temp"

# 创建临时构建目录
TEMP_DIR="$(mktemp -d)"
trap "rm -rf $TEMP_DIR $SCRIPT_DIR/.env.temp" EXIT

echo "📦 Cloning repository..."
if [ -n "${COMMON_OWEN_GH_TOKEN:-}" ]; then
  # 使用 token clone（支持私有仓库）
  git clone --depth 1 "https://${COMMON_OWEN_GH_TOKEN}@github.com/theowenyoung/blog.git" "$TEMP_DIR"
else
  # 公开仓库直接 clone
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR"
fi

echo "🏗️  Building with Zola..."
cd "$TEMP_DIR"
zola build

echo "🐳 Building Docker image..."
# 切换回 repo 根目录进行构建
REPO_ROOT="$SCRIPT_DIR/../.."
cd "$REPO_ROOT"

build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "docker/static-site/Dockerfile" \
  --build-context "static=$TEMP_DIR/public"

# 准备部署目录
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# 生成环境变量（用于 PUBLIC_URL）
echo "🔐 Generating environment variables..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

# 生成 docker-compose.yml（复用 nodejs-ssg 模板）
# DOCKER_SERVICE_NAME 已由 set_docker_service_name 设置
export IMAGE_TAG="$IMAGE_TAG_VERSIONED"
envsubst < "$REPO_ROOT/docker/nodejs-ssg/docker-compose.template.yml" > "$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

# 复制 docs-scraper 配置文件（用于 post-deploy 构建搜索索引）
if [ -f "$TEMP_DIR/meilisearch-docs-scraper-config.json" ]; then
  cp "$TEMP_DIR/meilisearch-docs-scraper-config.json" "$SCRIPT_DIR/$DEPLOY_DIST/"
  echo "📋 Copied meilisearch-docs-scraper-config.json"
fi

# 写入版本号
echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

# 生成部署摘要
generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

echo "✅ $SERVICE_BASE built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
