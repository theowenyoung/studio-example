#!/bin/sh
set -e

# Source the functions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../scripts/common.sh"

# ==========================================
# Unified Database Initialization
# ==========================================
# Works for all environments: local, preview, production
# Password source: COMMON_POSTGRES_APP_USER_PASSWORD env var (required)
# ==========================================

log "🔧 Setting up database infrastructure..."

# Require password from environment variable
if [ -z "${COMMON_POSTGRES_APP_USER_PASSWORD}" ]; then
    echo "❌ Error: COMMON_POSTGRES_APP_USER_PASSWORD environment variable is required"
    echo "Please set it before running this script:"
    echo "  export COMMON_POSTGRES_APP_USER_PASSWORD='your-secure-password'"
    exit 1
fi

# Default to 'app_user' if not specified
APP_USER="${COMMON_POSTGRES_APP_USER:-app_user}"
APP_USER_PASSWORD="${COMMON_POSTGRES_APP_USER_PASSWORD}"

# ==========================================
# Create Shared Application User
# ==========================================

log "📦 Creating shared application user: $APP_USER"

psql -v ON_ERROR_STOP=1 <<-EOSQL
    -- Create user (no CREATEDB privilege)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$APP_USER') THEN
            CREATE USER $APP_USER WITH PASSWORD '$APP_USER_PASSWORD';
            RAISE NOTICE 'User $APP_USER created';
        ELSE
            RAISE NOTICE 'User $APP_USER already exists';
        END IF;
    END
    \$\$;

    -- Grant $APP_USER to postgres (allows postgres to create databases owned by $APP_USER)
    GRANT $APP_USER TO postgres;
EOSQL

log_success "Database infrastructure ready!"
log ""
log "📋 Summary:"
log "   User:     $APP_USER (no CREATEDB privilege)"
log "   Password: from COMMON_POSTGRES_APP_USER_PASSWORD"
log "   Note:     Databases created by postgres automatically"
log ""
log "💡 Usage:"
log "   DATABASE_URL=postgresql://$APP_USER:<password>@<host>:5432/<db_name>"
log ""
log "🚀 Databases created automatically during deployment"
log ""
