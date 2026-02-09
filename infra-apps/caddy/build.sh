#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境（必须在开头调用）
detect_environment

# 解析参数
CONFIG_ONLY=false
TARGET_SERVER=""

for arg in "$@"; do
  case $arg in
    --config-only)
      CONFIG_ONLY=true
      ;;
    *)
      TARGET_SERVER="$arg"
      ;;
  esac
done

SERVICE_NAME="caddy"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_NAME (version: $VERSION)${CONFIG_ONLY:+ [config-only]}"

IMAGE="$ECR_REGISTRY/studio/$SERVICE_NAME"

# ===== 1. 构建并推送镜像（除非 --config-only）=====
if [ "$CONFIG_ONLY" = false ]; then
  build_and_push_image \
    "$IMAGE" \
    "$VERSION" \
    "infra-apps/caddy/Dockerfile"
fi

# ===== 2. 准备部署目录 =====
rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# ===== 3. 生成 docker-compose.yml（仅完整构建时需要）=====
if [ "$CONFIG_ONLY" = false ]; then
  export IMAGE_TAG="$IMAGE_TAG_VERSIONED"
  envsubst <"$SCRIPT_DIR/docker-compose.prod.yml" >"$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"
fi

# 复制辅助脚本
cp "$SCRIPT_DIR/src/reload.sh" "$SCRIPT_DIR/src/restart.sh" "$SCRIPT_DIR/$DEPLOY_DIST/"

# 复制配置（不包含 production-prod* 目录）
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST/config"
cp "$SCRIPT_DIR/src/config/Caddyfile" "$SCRIPT_DIR/$DEPLOY_DIST/config/"
cp -r "$SCRIPT_DIR/src/config/snippets" "$SCRIPT_DIR/$DEPLOY_DIST/config/"

# 创建 production 目录并根据环境/目标服务器复制配置
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST/config/production"

if [ "$DEPLOY_ENV" = "preview" ]; then
  # Preview 环境：清空 production 目录（避免为生产域名申请证书）
  # Preview 的应用域名配置由 deploy-app.yml 自动生成到 preview/ 目录
  echo "🔧 Preview environment: production configs cleared"
elif [ "$DEPLOY_ENV" = "prod" ]; then
  # Prod 环境：根据目标服务器选择配置
  if [ -z "$TARGET_SERVER" ]; then
    TARGET_SERVER="prod1"  # 默认 prod1
  fi

  if [ -d "$SCRIPT_DIR/src/config/production-${TARGET_SERVER}" ]; then
    echo "🔧 Prod environment: using production-${TARGET_SERVER} configs"
    cp "$SCRIPT_DIR/src/config/production-${TARGET_SERVER}/"*.caddy "$SCRIPT_DIR/$DEPLOY_DIST/config/production/" 2>/dev/null || true
  else
    echo "⚠️  Warning: No production-${TARGET_SERVER} directory found"
  fi
fi

# 获取环境变量（如果有）
if [ -f "$SCRIPT_DIR/.env.example" ]; then
  echo "🔐 Fetching environment variables from AWS Parameter Store..."
  psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"
fi

# 创建 preview 目录（用于动态生成的预览环境配置）
# rsync 会同步此空目录，但 --exclude=config/preview/* 会保留服务器上已有的配置
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST/config/preview"

# 复制 preview-fallback 配置
# 这个通配符配置为已删除的 preview 环境返回 404
# Prod 环境创建空目录（避免 import 报错），Preview 环境复制实际配置
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST/config/preview-fallback"
if [ "$DEPLOY_ENV" = "preview" ]; then
  cp "$SCRIPT_DIR/src/config/preview-fallback/"*.caddy "$SCRIPT_DIR/$DEPLOY_DIST/config/preview-fallback/" 2>/dev/null || true
fi

# 写入版本号
echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
