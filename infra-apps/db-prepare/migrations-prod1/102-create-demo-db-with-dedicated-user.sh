#!/bin/sh
set -e

# Source the functions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

# ==========================================
# Configuration - Modify these variables
# ==========================================
DB_NAME="demo"
USER_NAME="demo"
USER_PASSWORD_ENV="DEMO_POSTGRES_USER_PASSWORD"
READONLY_PASSWORD_ENV="DEMO_POSTGRES_READONLY_PASSWORD"

# ==========================================
# Create Dedicated Database with Users
# ==========================================
# Creates separate user and database for better isolation
# ==========================================

# Validate required environment variables
require_env_var "$USER_PASSWORD_ENV"
require_env_var "$READONLY_PASSWORD_ENV"

# Get passwords from environment
eval USER_PASSWORD="\$$USER_PASSWORD_ENV"
eval READONLY_PASSWORD="\$$READONLY_PASSWORD_ENV"

# Create database with dedicated users
create_database_with_dedicated_users "$DB_NAME" "$USER_NAME" "$USER_PASSWORD" "$READONLY_PASSWORD"
