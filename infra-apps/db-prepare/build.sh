#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# 检测环境（必须在开头调用）
# 如果 DEPLOY_ENV 已经设置（例如从 Ansible 传入），则跳过检测
if [ -z "${DEPLOY_ENV:-}" ]; then
  detect_environment
fi

SERVICE_NAME="db-prepare"
VERSION="$(get_version)"

# 目标服务器（用于选择 migrations 目录）
# prod1/prod2 对应 migrations/ 和 migrations-prod2/
# preview 只用 migrations/
TARGET_SERVER="${TARGET_SERVER:-prod1}"

# 输出目录：本地开发用 dist，部署用 deploy-dist
# 可通过 BUILD_OUTPUT_DIR 环境变量覆盖
OUTPUT_DIR="${BUILD_OUTPUT_DIR:-$DEPLOY_DIST}"

echo "🔨 Building $SERVICE_NAME (version: $VERSION, server: $TARGET_SERVER, output: $OUTPUT_DIR)"

# ===== 1. 准备部署目录 =====
rm -rf "$SCRIPT_DIR/$OUTPUT_DIR"
mkdir -p "$SCRIPT_DIR/$OUTPUT_DIR"

# ===== 2. 获取运行时环境变量 =====
echo "🔐 Fetching environment variables from AWS Parameter Store..."
psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$OUTPUT_DIR/.env"

# ===== 3. 复制必要的文件 =====
cp "$SCRIPT_DIR/docker-compose.yml" "$SCRIPT_DIR/$OUTPUT_DIR/"
cp -r "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/$OUTPUT_DIR/"

# ===== 4. 复制 migrations =====
# 目录结构:
#   migrations/              - 通用脚本（001-099，所有服务器都运行）
#   migrations-prod1/        - prod1 专属（101-199）
#   migrations-prod2/        - prod2 专属（201-299）
#   migrations-prod3/        - prod3 专属（301-399）
#   ...
#
# 文件名编号规则（保证执行顺序）:
#   001-099: 通用脚本（如 init-app-user）
#   101-199: prod1 数据库
#   201-299: prod2 数据库
#   301-399: prod3 数据库
#
# Preview/local 环境运行所有 migrations（测试所有数据库）

mkdir -p "$SCRIPT_DIR/$OUTPUT_DIR/migrations"

# 1. 通用 migrations（所有服务器）
echo "📁 Including migrations/ (common: 001-099)"
cp "$SCRIPT_DIR/migrations"/*.sh "$SCRIPT_DIR/$OUTPUT_DIR/migrations/" 2>/dev/null || true

# 2. 服务器专属 migrations
if [ "$TARGET_SERVER" = "preview" ] || [ "$TARGET_SERVER" = "local" ]; then
  # Preview/local: 合并所有 migrations-prod*/ 目录（测试所有数据库）
  echo "📁 $TARGET_SERVER mode: including all server migrations"
  for dir in "$SCRIPT_DIR"/migrations-prod*/; do
    if [ -d "$dir" ]; then
      dir_name=$(basename "$dir")
      echo "   📁 Including ${dir_name}/"
      cp "$dir"/*.sh "$SCRIPT_DIR/$OUTPUT_DIR/migrations/" 2>/dev/null || true
    fi
  done
else
  # Prod: 只包含对应服务器的 migrations
  SERVER_MIGRATIONS_DIR="$SCRIPT_DIR/migrations-${TARGET_SERVER}"
  if [ -d "$SERVER_MIGRATIONS_DIR" ]; then
    echo "📁 Including migrations-${TARGET_SERVER}/"
    cp "$SERVER_MIGRATIONS_DIR"/*.sh "$SCRIPT_DIR/$OUTPUT_DIR/migrations/" 2>/dev/null || true
  else
    echo "⚠️  No server-specific migrations found: migrations-${TARGET_SERVER}/"
  fi
fi

# ===== 5. 写入版本号 =====
echo "$VERSION" > "$SCRIPT_DIR/$OUTPUT_DIR/version.txt"

echo "✅ $SERVICE_NAME built: $SCRIPT_DIR/$OUTPUT_DIR"
ls -lh "$SCRIPT_DIR/$OUTPUT_DIR"
echo "📋 Migrations included:"
ls -1 "$SCRIPT_DIR/$OUTPUT_DIR/migrations/"
