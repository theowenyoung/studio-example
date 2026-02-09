#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/build-lib.sh"

# Parse arguments
SERVICE_BASE="${1:-}"

if [ -z "$SERVICE_BASE" ]; then
    echo "❌ Error: Service name is required"
    echo "Usage: $0 <service-name>"
    exit 1
fi

# Detect environment
detect_environment

# Generate service name (with branch suffix for preview)
if [ "$DEPLOY_ENV" = "preview" ]; then
    SERVICE_NAME="${SERVICE_BASE}--${BRANCH_CLEAN}"
else
    SERVICE_NAME="${SERVICE_BASE}"
fi

# Build first (this generates deploy-dist/.env and DEPLOY_ROUTES.txt)
echo "📦 Building $SERVICE_BASE for $DEPLOY_ENV..."
bash "$REPO_ROOT/external-apps/$SERVICE_BASE/build.sh"

# Read config from deploy-dist/.env
ENV_FILE="$REPO_ROOT/external-apps/$SERVICE_BASE/deploy-dist/.env"
if [ -f "$ENV_FILE" ]; then
    # Check if deployment is disabled
    DEPLOY_ENABLED=$(grep -E "^DEPLOY_ENABLED=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true)
    if [ "$DEPLOY_ENABLED" = "false" ]; then
        echo "⏭️  Skipping deployment: DEPLOY_ENABLED=false in .env.example"
        exit 0
    fi

    # Read DEPLOY_SERVER for prod (optional, defaults to ANSIBLE_TARGET)
    if [ "$DEPLOY_ENV" = "prod" ]; then
        DEPLOY_SERVER=$(get_deploy_server "$ENV_FILE")
        if [ -n "$DEPLOY_SERVER" ]; then
            # Verify server exists in inventory
            if ! check_server_configured "$DEPLOY_SERVER"; then
                echo "❌ Error: DEPLOY_SERVER='$DEPLOY_SERVER' not found in ansible/inventory.yml"
                echo "   Available servers:"
                list_available_servers | while read -r srv; do echo "     - $srv"; done
                exit 1
            fi
            ANSIBLE_TARGET="$DEPLOY_SERVER"
        fi
    fi
fi

# Read routes from deploy-dist/DEPLOY_ROUTES.txt (single source of truth)
ROUTES_FILE="$REPO_ROOT/external-apps/$SERVICE_BASE/deploy-dist/DEPLOY_ROUTES.txt"
SUMMARY_FILE="$REPO_ROOT/external-apps/$SERVICE_BASE/deploy-dist/DEPLOY_SUMMARY.txt"

# Build routes JSON if file exists
# Format: domain|path|port per line
ROUTES_JSON="[]"
if [ -f "$ROUTES_FILE" ]; then
    ROUTES_JSON="["
    first=true
    while IFS='|' read -r domain path port; do
        [ -z "$domain" ] && continue
        if [ "$first" = true ]; then
            first=false
        else
            ROUTES_JSON+=","
        fi
        ROUTES_JSON+="{\"domain\":\"$domain\",\"path\":\"$path\",\"port\":\"$port\"}"
    done < "$ROUTES_FILE"
    ROUTES_JSON+="]"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Deploying External App: $SERVICE_BASE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Environment:  $DEPLOY_ENV"
echo "   Branch:       $CURRENT_BRANCH"
echo "   Service:      $SERVICE_NAME"
echo "   Target:       $ANSIBLE_TARGET"
if [ -f "$ROUTES_FILE" ]; then
    echo "   Routes:"
    while IFS='|' read -r domain path port; do
        [ -z "$domain" ] && continue
        echo "     - https://${domain}${path} -> :$port"
    done < "$ROUTES_FILE"
else
    echo "   Routes:       (internal service, no public URL)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Deploy
echo "🚀 Deploying $SERVICE_NAME to $ANSIBLE_TARGET..."
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-external-app.yml \
  -e service_base="$SERVICE_BASE" \
  -e service_name="$SERVICE_NAME" \
  -e "routes=$ROUTES_JSON" \
  -e target_env="$DEPLOY_ENV" \
  -l "$ANSIBLE_TARGET"

echo ""
echo "✅ $SERVICE_NAME deployed successfully to $DEPLOY_ENV environment"
# Display all URLs
if [ -f "$SUMMARY_FILE" ]; then
    echo "🌐 URLs:"
    while read -r url; do
        echo "   $url"
    done < "$SUMMARY_FILE"
fi
