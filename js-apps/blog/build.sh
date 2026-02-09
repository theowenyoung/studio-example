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

# ===== 1. 准备部署目录并生成环境变量 =====
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

if [ -f "$SCRIPT_DIR/.env.example" ]; then
  echo "🔐 Generating environment variables..."
  psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"
fi

# ===== 2. 从 PUBLIC_URL 提取 BASE_PATH（用于子路径部署）=====
BASE_PATH="/"
if [ -f "$SCRIPT_DIR/$DEPLOY_DIST/.env" ]; then
  PUBLIC_URL=$(grep "^PUBLIC_URL=" "$SCRIPT_DIR/$DEPLOY_DIST/.env" | head -1 | cut -d'=' -f2- || true)
  if [ -n "$PUBLIC_URL" ]; then
    # 提取路径部分，例如 https://example.com/blog -> /blog
    URL_PATH=$(echo "$PUBLIC_URL" | sed 's|^https://[^/]*||' || true)
    if [ -n "$URL_PATH" ] && [ "$URL_PATH" != "/" ]; then
      BASE_PATH="$URL_PATH"
      echo "📂 Detected BASE_PATH: $BASE_PATH"
    fi
  fi
fi

# ===== 3. 构建并推送镜像 =====
build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "docker/nodejs-ssg/Dockerfile" \
  --build-arg APP_NAME="${SERVICE_NAME}" \
  --build-arg BASE_PATH="${BASE_PATH}"

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
