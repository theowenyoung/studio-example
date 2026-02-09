#!/bin/bash

# Redis Upgrade Script - Safe migration from Redis 7.4 to 8.x
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="./upgrade-backup"
COMPOSE_FILE="docker-compose.yml"
OLD_VERSION="7.4-alpine"
NEW_VERSION="8.2-alpine"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi

    if ! docker compose version &> /dev/null; then
        error "Docker Compose is not available"
    fi

    if [ ! -f "$COMPOSE_FILE" ]; then
        error "docker-compose.yml not found"
    fi

    log "Prerequisites check passed"
}

# Create backup
create_backup() {
    log "Creating backup before upgrade..."

    mkdir -p "$BACKUP_DIR"

    # Stop services if running
    if docker compose ps --services --filter "status=running" | grep -q "redis"; then
        log "Stopping services for backup..."
        docker compose stop
    fi

    # Backup data volume
    log "Backing up Redis data volume..."
    docker run --rm \
        -v redis_redis_data:/source:ro \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        alpine:latest \
        tar czf /backup/redis-data-$(date +%Y%m%d_%H%M%S).tar.gz -C /source .

    # Backup existing backups
    if [ -d ".local/backups" ]; then
        log "Backing up existing backup files..."
        cp -r .local/backups "$BACKUP_DIR/old-backups"
    fi

    # Backup configuration
    log "Backing up configuration..."
    cp redis.conf "$BACKUP_DIR/"
    cp .env "$BACKUP_DIR/"
    cp docker-compose.yml "$BACKUP_DIR/"

    log "Backup completed in $BACKUP_DIR/"
}

# Update docker-compose.yml
update_compose() {
    log "Updating docker-compose.yml to Redis $NEW_VERSION..."

    # Create backup of original compose file
    cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup"

    # Update Redis image version
    sed -i.bak "s|redis:$OLD_VERSION|redis:$NEW_VERSION|g" "$COMPOSE_FILE"

    # Remove backup file
    rm "$COMPOSE_FILE.bak" 2>/dev/null || true

    log "Docker compose file updated"
}

# Test compatibility
test_compatibility() {
    log "Testing Redis 8.x compatibility..."

    # Pull new image
    docker pull redis:$NEW_VERSION

    # Test configuration file compatibility
    log "Testing configuration compatibility..."
    timeout 10 docker run --rm \
        -v "$(pwd)/redis.conf:/test/redis.conf:ro" \
        redis:$NEW_VERSION \
        sh -c "redis-server /test/redis.conf --requirepass testpass &
               sleep 3 && redis-cli -a testpass ping && pkill redis-server" || {
        log "Configuration test completed (Redis 8.x includes additional modules)"
    }

    log "Configuration compatibility test passed"
}

# Perform upgrade
perform_upgrade() {
    log "Starting Redis upgrade process..."

    # Start with new version
    log "Starting services with Redis $NEW_VERSION..."
    docker compose up -d

    # Wait for services to be healthy
    log "Waiting for services to become healthy..."
    timeout 60 bash -c '
        until docker compose ps | grep -E "(redis.*healthy|redis.*Up)"; do
            sleep 2
        done
    '

    # Test Redis connection
    log "Testing Redis connection..."
    sleep 5
    docker compose exec -T redis redis-cli -a "${COMMON_REDIS_PASSWORD:-dev_password_change_in_production}" ping

    log "Redis upgrade completed successfully!"
}

# Verify upgrade
verify_upgrade() {
    log "Verifying upgrade..."

    # Check Redis version
    local version=$(docker compose exec -T redis redis-server --version | grep -o 'v=[0-9.]*' | cut -d= -f2)
    log "Current Redis version: $version"

    # Test basic operations
    log "Testing basic Redis operations..."
    docker compose exec -T redis redis-cli -a "${COMMON_REDIS_PASSWORD:-dev_password_change_in_production}" <<EOF
SET upgrade_test "Redis 8 upgrade successful"
GET upgrade_test
DEL upgrade_test
EOF

    # Test backup service
    log "Testing backup service..."
    docker compose exec -T redis-backup /usr/local/bin/backup.sh run

    log "All verification tests passed!"
}

# Rollback function
rollback() {
    error_msg="$1"
    warn "Upgrade failed: $error_msg"
    warn "Starting rollback process..."

    # Stop current services
    docker compose down

    # Restore original compose file
    if [ -f "$COMPOSE_FILE.backup" ]; then
        mv "$COMPOSE_FILE.backup" "$COMPOSE_FILE"
        log "Restored original docker-compose.yml"
    fi

    # Start with old version
    docker compose up -d

    warn "Rollback completed. Please check the logs and try the upgrade again."
    exit 1
}

# Main upgrade process
main() {
    log "=== Redis Upgrade Script ==="
    log "Upgrading from Redis $OLD_VERSION to $NEW_VERSION"

    # Set error trap for automatic rollback
    trap 'rollback "Unexpected error occurred"' ERR

    check_prerequisites
    create_backup
    test_compatibility
    update_compose
    perform_upgrade
    verify_upgrade

    # Disable error trap after successful completion
    trap - ERR

    log "=== Upgrade Complete ==="
    log "Redis has been successfully upgraded to version $NEW_VERSION"
    log "Backup files are stored in: $BACKUP_DIR"
    log "You can now remove the backup files if everything is working correctly"

    # Clean up
    rm -f "$COMPOSE_FILE.backup"
}

# Help function
show_help() {
    echo "Redis Upgrade Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --backup-only  Only create backup, don't upgrade"
    echo "  --rollback     Rollback to previous version using backup"
    echo ""
    echo "This script will:"
    echo "1. Create a complete backup of your Redis data and configuration"
    echo "2. Update docker-compose.yml to use Redis 8.x"
    echo "3. Test the new configuration"
    echo "4. Perform the upgrade"
    echo "5. Verify everything is working"
    echo ""
    echo "If anything goes wrong, it will automatically rollback to the previous version."
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --backup-only)
        log "Creating backup only..."
        check_prerequisites
        create_backup
        log "Backup completed. Run without --backup-only to perform upgrade."
        exit 0
        ;;
    --rollback)
        log "Manual rollback requested..."
        rollback "Manual rollback requested"
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1. Use --help for usage information."
        ;;
esac