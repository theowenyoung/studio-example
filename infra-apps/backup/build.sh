#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境（必须在开头调用）
detect_environment

SERVICE_NAME="backup"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_NAME (version: $VERSION)"

IMAGE="$ECR_REGISTRY/studio/$SERVICE_NAME"

# ===== 1. 构建并推送镜像 =====
build_and_push_image \
  "$IMAGE" \
  "$VERSION" \
  "infra-apps/backup/Dockerfile"

# ===== 2. 准备部署目录 =====
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# ===== 3. 获取运行时环境变量 =====
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

# ===== 4. 生成 docker-compose.yml =====
export IMAGE_TAG="$IMAGE_TAG_VERSIONED"
envsubst <"$SCRIPT_DIR/docker-compose.prod.yml" >"$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

# ===== 5. 写入版本号 =====
echo "$VERSION" >"$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
