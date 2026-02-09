#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/build-lib.sh"

# Parse arguments
# Usage: deploy-infra.sh [service] [--server=prod1|prod2|all]
SERVICE="all"
TARGET_SERVER=""

for arg in "$@"; do
  case $arg in
    --server=*)
      TARGET_SERVER="${arg#*=}"
      ;;
    *)
      SERVICE="$arg"
      ;;
  esac
done

# Detect environment
detect_environment

# Determine target servers for prod environment
# - preview: always single server
# - prod: can specify --server=prod1, --server=prod2, or --server=all (default)
if [ "$DEPLOY_ENV" = "prod" ]; then
  if [ -z "$TARGET_SERVER" ] || [ "$TARGET_SERVER" = "all" ]; then
    # Deploy to all prod servers (only active ones in inventory)
    # prod2 is commented out by default, so this only hits prod1
    DEPLOY_TARGETS="prod_servers"
  else
    DEPLOY_TARGETS="$TARGET_SERVER"
  fi
else
  DEPLOY_TARGETS="preview"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying Infrastructure"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Environment:  $DEPLOY_ENV"
echo "   Branch:       $CURRENT_BRANCH"
echo "   Target:       $DEPLOY_TARGETS"
echo "   Service:      $SERVICE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Build and deploy based on service
deploy_service() {
  local service_name=$1
  local target_server=${2:-}  # Optional: specific server for build
  local build_script="$REPO_ROOT/infra-apps/$service_name/build.sh"
  local playbook="ansible/playbooks/deploy-infra-${service_name}.yml"

  echo "📦 Building $service_name for $DEPLOY_ENV${target_server:+ (server: $target_server)}..."
  if [ -n "$target_server" ]; then
    bash "$build_script" "$target_server"
  else
    bash "$build_script"
  fi

  local deploy_target="${target_server:-$DEPLOY_TARGETS}"
  echo "🚀 Deploying $service_name to $deploy_target..."
  ansible-playbook -i ansible/inventory.yml "$playbook" -l "$deploy_target"
  echo ""
}

# Deploy caddy to specific server (needs per-server build)
deploy_caddy() {
  local target=$1
  deploy_service "caddy" "$target"
}

# Get active prod servers from inventory (not commented out)
get_active_prod_servers() {
  # Parse inventory.yml to find active hosts under prod_servers
  # Hosts that are commented out (starting with #) are excluded
  grep -A 100 "prod_servers:" "$REPO_ROOT/ansible/inventory.yml" | \
    grep -E "^\s+prod[0-9]+:" | \
    sed 's/://g' | \
    awk '{print $1}'
}

# Deploy caddy to all active prod servers or specific one
deploy_caddy_to_targets() {
  if [ -z "$TARGET_SERVER" ] || [ "$TARGET_SERVER" = "all" ]; then
    local servers
    servers=$(get_active_prod_servers)
    if [ -z "$servers" ]; then
      echo "⚠️  No active prod servers found in inventory"
      return
    fi
    for server in $servers; do
      deploy_caddy "$server"
    done
  else
    deploy_caddy "$TARGET_SERVER"
  fi
}

# Deploy services
if [ "$SERVICE" = "all" ]; then
  deploy_service "postgres"
  deploy_service "redis"

  # Caddy needs per-server build (different production configs)
  if [ "$DEPLOY_ENV" = "prod" ]; then
    deploy_caddy_to_targets
  else
    deploy_service "caddy"
  fi

  # Backup only for production
  if [ "$DEPLOY_ENV" = "prod" ]; then
    deploy_service "backup"
  else
    echo "⏭️  Skipping backup service (preview environment)"
  fi
elif [ "$SERVICE" = "caddy" ]; then
  # Caddy needs per-server build
  if [ "$DEPLOY_ENV" = "prod" ]; then
    deploy_caddy_to_targets
  else
    deploy_service "caddy"
  fi
else
  deploy_service "$SERVICE"
fi

echo "✅ Infrastructure deployment completed for $DEPLOY_ENV environment (targets: $DEPLOY_TARGETS)"
