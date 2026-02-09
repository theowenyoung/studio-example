#!/bin/bash
set -e

# ==========================================
# PostgreSQL Initialization (Local Development)
# ==========================================
# This script delegates to db-prepare for centralized management
# All database initialization logic is in infra-apps/db-prepare/migrations/
# ==========================================

echo "=============================================="
echo "🐘 PostgreSQL Initialization"
echo "=============================================="
echo ""

# Check if db-prepare migrations are available
DB_PREPARE_MIGRATIONS="/docker-entrypoint-initdb.d/db-prepare-migrations"

if [ -f "$DB_PREPARE_MIGRATIONS/001-init-app-user.sh" ]; then
    echo "📂 Running unified initialization from db-prepare..."
    echo ""

    # Run the unified initialization script
    bash "$DB_PREPARE_MIGRATIONS/001-init-app-user.sh"

    echo "✅ Initialization completed!"
else
    echo "⚠️  Warning: db-prepare migrations not found at $DB_PREPARE_MIGRATIONS"
    echo "   Make sure to mount db-prepare/migrations in docker-compose.yml"
    echo ""
    echo "   Expected volume mount:"
    echo "   - ../db-prepare/migrations:/docker-entrypoint-initdb.d/db-prepare-migrations:ro"
fi

echo ""
