#!/bin/sh
set -e

# Source the functions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

# ==========================================
# Configuration - Modify these variables
# ==========================================
DB_NAME="${HONO_PROD2_DEMO_DB_NAME:-hono_prod2_demo}"

# ==========================================
# Create Database with Shared app_user
# ==========================================
# Uses shared app_user (created in 001-init-app-user.sh)
# ==========================================

create_database_with_app_user "$DB_NAME"
