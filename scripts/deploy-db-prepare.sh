#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/build-lib.sh"

# Parse arguments
# Usage: deploy-db-prepare.sh [prod|preview|auto] [--server=prod1|prod2]
FORCE_ENV="auto"
TARGET_SERVER=""

for arg in "$@"; do
  case $arg in
    --server=*)
      TARGET_SERVER="${arg#*=}"
      ;;
    prod|preview|auto)
      FORCE_ENV="$arg"
      ;;
  esac
done

# Determine environment
if [ "$FORCE_ENV" = "prod" ]; then
  # Force production environment
  export DEPLOY_ENV="prod"
  export AWS_PARAM_PATH="/studio-prod/"
  export CTX_DB_SUFFIX=""
  export CTX_DNS_SUFFIX=""
  export CTX_ROOT_DOMAIN="owenyoung.com"
  echo "🚀 Deploying db-prepare to PRODUCTION (forced)..."

elif [ "$FORCE_ENV" = "preview" ]; then
  # Force preview environment
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  BRANCH_CLEAN=$(echo "$CURRENT_BRANCH" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | cut -c1-30)

  export DEPLOY_ENV="preview"
  export AWS_PARAM_PATH="/studio-dev/"
  export CTX_DB_SUFFIX="__${BRANCH_CLEAN//-/_}"
  export CTX_DNS_SUFFIX="--${BRANCH_CLEAN}"
  export CTX_ROOT_DOMAIN="preview.owenyoung.com"

  echo "🚀 Deploying db-prepare to PREVIEW (forced)..."
  echo "   Branch: $CURRENT_BRANCH (clean: $BRANCH_CLEAN)"
  echo "   DB Suffix: $CTX_DB_SUFFIX"

else
  # Auto-detect from git branch
  detect_environment
  echo "🚀 Deploying db-prepare to $DEPLOY_ENV environment (auto-detected)..."
fi

# Determine target server
if [ "$DEPLOY_ENV" = "prod" ]; then
  # For prod: use specified server or default to prod1
  TARGET_SERVER="${TARGET_SERVER:-prod1}"
else
  # For preview: always use preview server
  TARGET_SERVER="preview"
fi

# Export for build.sh to use
export TARGET_SERVER

echo "🎯 Target server: $TARGET_SERVER"

# Build with environment context
echo "📦 Building db-prepare for $DEPLOY_ENV (server: $TARGET_SERVER)..."
bash "$REPO_ROOT/infra-apps/db-prepare/build.sh"

# Deploy to target server
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-db-prepare.yml \
  -l "$TARGET_SERVER" -e deploy_env="$DEPLOY_ENV"

echo "✅ Database migrations completed for $DEPLOY_ENV environment (server: $TARGET_SERVER)"
