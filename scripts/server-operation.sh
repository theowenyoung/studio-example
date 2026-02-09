#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-lib.sh"

# Parse arguments
OPERATION="${1:-}"
PLAYBOOK="${2:-}"
TARGET_SERVER="${3:-}"

if [ -z "$OPERATION" ] || [ -z "$PLAYBOOK" ]; then
    echo "❌ Error: Missing arguments"
    echo "Usage: $0 <operation-name> <playbook-name> [target-server]"
    exit 1
fi

# Detect environment
detect_environment

# Override target if specified
if [ -n "$TARGET_SERVER" ]; then
    if [ "$TARGET_SERVER" = "all" ]; then
        ANSIBLE_TARGET="prod_servers"
    else
        ANSIBLE_TARGET="$TARGET_SERVER"
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Server Operation: $OPERATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Environment:  $DEPLOY_ENV"
echo "   Branch:       $CURRENT_BRANCH"
echo "   Target:       $ANSIBLE_TARGET"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Warn if running prod-only operation from non-main branch (unless target explicitly specified)
if [ "$DEPLOY_ENV" != "prod" ] && [ -z "$TARGET_SERVER" ]; then
    echo "⚠️  Warning: This operation typically runs on production servers."
    echo "   Current branch '$CURRENT_BRANCH' targets preview environment."
    echo "   Options:"
    echo "   - Switch to 'main' branch: git checkout main"
    echo "   - Or specify target: mr server-backup all|prod1|prod2"
    echo ""
fi

# Build ansible command
ANSIBLE_CMD="ansible-playbook -i ansible/inventory.yml ansible/playbooks/$PLAYBOOK -l $ANSIBLE_TARGET"

# Run ansible playbook
$ANSIBLE_CMD

echo ""
echo "✅ Operation completed: $OPERATION"
