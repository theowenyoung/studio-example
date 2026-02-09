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
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_NAME (version: $VERSION)"

IMAGE="$ECR_REGISTRY/$SERVICE_NAME"

# ===== 1. 构建并推送镜像 =====
build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "docker/nodejs-ssg/Dockerfile" \
  --build-arg APP_NAME="${SERVICE_NAME}"

# ===== 2. 准备部署目录 =====
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# ===== 3. 生成环境变量（用于 PUBLIC_URL） =====
if [ -f "$SCRIPT_DIR/.env.example" ]; then
  echo "🔐 Generating environment variables..."
  psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"
fi

# ===== 4. 生成 docker-compose.yml（使用模板 + envsubst） =====
export IMAGE_TAG="$IMAGE_TAG_VERSIONED"
# DOCKER_SERVICE_NAME 已由 detect_environment 导出

envsubst < "$SCRIPT_DIR/../../docker/nodejs-ssg/docker-compose.template.yml" > "$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

# ===== 5. 写入版本号 =====
echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

# ===== 6. 生成部署摘要 =====
generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
