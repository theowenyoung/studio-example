#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境（必须在开头调用）
detect_environment

# 从目录名自动推断服务名，复制目录时无需修改
SERVICE_NAME=$(basename "$SCRIPT_DIR")
set_docker_service_name "$SERVICE_NAME"
APP_PATH="js-apps/$SERVICE_NAME"
START_CMD="node dist/index.cjs"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_NAME (version: $VERSION)"

IMAGE="$ECR_REGISTRY/studio/$SERVICE_NAME"

# ===== 1. 构建并推送镜像 =====
build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "docker/nodejs/Dockerfile" \
  --build-arg APP_PATH="$APP_PATH" \
  --build-arg START_CMD="$START_CMD"

# ===== 2. 准备部署目录 =====
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# ===== 3. 获取运行时环境变量 =====
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

# ===== 4. 生成 docker-compose.yml =====
export IMAGE_TAG="$IMAGE_TAG_VERSIONED"
# DOCKER_SERVICE_NAME 已由 detect_environment 导出
envsubst <"$SCRIPT_DIR/docker-compose.prod.yml" >"$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

# ===== 5. 写入版本号 =====
echo "$VERSION" >"$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

# ===== 6. 生成部署摘要 =====
generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
