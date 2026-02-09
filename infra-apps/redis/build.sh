#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境（必须在开头调用）
detect_environment

SERVICE_NAME="redis"
VERSION="$(get_version)"

echo "🔨 Building $SERVICE_NAME (version: $VERSION)"

rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

# 获取环境变量
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

# 复制所有必要文件
cp "$SCRIPT_DIR/docker-compose.prod.yml" "$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"
cp -r "$SCRIPT_DIR/src/config" "$SCRIPT_DIR/$DEPLOY_DIST/"

# 写入版本号
echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$DEPLOY_DIST"
ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
