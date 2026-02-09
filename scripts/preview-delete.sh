#!/bin/bash
set -e

# Preview environment deletion script
# Uses double separator (-- for DNS, __ for DB) to find resources

usage() {
  echo "Usage: $0 <branch-name> [project-name] [-y|--yes]"
  echo ""
  echo "Examples:"
  echo "  $0 feat-test              # Delete all projects in feat-test branch"
  echo "  $0 feat-test hono-demo    # Delete only hono-demo in feat-test branch"
  echo "  $0 feat-test -y           # Delete all without confirmation"
  exit 1
}

# Parse arguments
BRANCH=""
PROJECT=""
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--yes) SKIP_CONFIRM=true; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $1"; usage ;;
    *)
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      elif [ -z "$PROJECT" ]; then
        PROJECT="$1"
      else
        echo "Error: Too many arguments"; usage
      fi
      shift ;;
  esac
done

[ -z "$BRANCH" ] && { echo "Error: Branch name required"; usage; }

SERVER="preview"
INVENTORY="ansible/inventory.yml"

# Normalize branch name (ensure hyphen format)
BRANCH="${BRANCH//_/-}"
# Convert to underscore for database matching
BRANCH_UNDERSCORE="${BRANCH//-/_}"

# Normalize project name if provided
if [ -n "$PROJECT" ]; then
  PROJECT="${PROJECT//_/-}"
  PROJECT_UNDERSCORE="${PROJECT//-/_}"
fi

echo "🗑️  Preview Environment Deletion"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   Branch: $BRANCH"
[ -n "$PROJECT" ] && echo "   Project: $PROJECT"
echo ""
echo "🔍 Finding resources..."

# Build patterns based on whether project is specified
if [ -n "$PROJECT" ]; then
  # Single project patterns
  CONTAINER_PATTERN="${PROJECT}--${BRANCH}-"
  DB_PATTERN="${PROJECT_UNDERSCORE}__${BRANCH_UNDERSCORE}"
  # Caddy snippets are in routes/ with format: {domain}---{service_name}.snippet (三横线分隔)
  CADDY_SNIPPET_PATTERN="*---${PROJECT}--${BRANCH}.snippet"
  DIR_PATTERN="${PROJECT}--${BRANCH}"
else
  # All projects in branch patterns
  CONTAINER_PATTERN="--${BRANCH}-"
  DB_PATTERN="%__${BRANCH_UNDERSCORE}"
  CADDY_SNIPPET_PATTERN="*---*--${BRANCH}.snippet"
  DIR_PATTERN="*--${BRANCH}"
fi

# Find all resources on server using double separator patterns
if [ -n "$PROJECT" ]; then
  resources=$(ansible $SERVER -i $INVENTORY -m shell -a "
CONTAINER_PATTERN='$CONTAINER_PATTERN'
DB_PATTERN='$DB_PATTERN'
CADDY_SNIPPET_PATTERN='$CADDY_SNIPPET_PATTERN'
DIR_PATTERN='$DIR_PATTERN'

echo '=== CONTAINERS ==='
docker ps -a --format '{{\"{{\"}}.Names{{\"}}\"}}' | grep -F -- \"\${CONTAINER_PATTERN}\" || true

echo '=== DATABASES ==='
cd /srv/postgres && docker compose exec -T postgres psql -U postgres -t -A -c \"SELECT datname FROM pg_database WHERE datname = '\${DB_PATTERN}'\" || true

echo '=== CADDY_CONFIGS ==='
for f in /srv/caddy/config/preview/routes/\${CADDY_SNIPPET_PATTERN}; do [ -f \"\$f\" ] && basename \"\$f\"; done 2>/dev/null || true

echo '=== APP_DIRS ==='
for d in /srv/\${DIR_PATTERN}; do [ -d \"\$d\" ] && basename \"\$d\"; done 2>/dev/null || true
" 2>/dev/null | grep -v "^$SERVER |" || true)
else
  resources=$(ansible $SERVER -i $INVENTORY -m shell -a "
BRANCH='$BRANCH'
BRANCH_UNDERSCORE='$BRANCH_UNDERSCORE'
CADDY_SNIPPET_PATTERN='$CADDY_SNIPPET_PATTERN'

echo '=== CONTAINERS ==='
docker ps -a --format '{{\"{{\"}}.Names{{\"}}\"}}' | grep -E -- \"--\${BRANCH}-\" || true

echo '=== DATABASES ==='
cd /srv/postgres && docker compose exec -T postgres psql -U postgres -t -A -c \"SELECT datname FROM pg_database WHERE datname LIKE '%__\${BRANCH_UNDERSCORE}'\" || true

echo '=== CADDY_CONFIGS ==='
for f in /srv/caddy/config/preview/routes/\${CADDY_SNIPPET_PATTERN}; do [ -f \"\$f\" ] && basename \"\$f\"; done 2>/dev/null || true

echo '=== APP_DIRS ==='
for d in /srv/*--\${BRANCH}; do [ -d \"\$d\" ] && basename \"\$d\"; done 2>/dev/null || true
" 2>/dev/null | grep -v "^$SERVER |" || true)
fi

# Parse resources
containers=$(echo "$resources" | sed -n '/=== CONTAINERS ===/,/=== DATABASES ===/p' | grep -v "===" | grep -v "^$" || true)
databases=$(echo "$resources" | sed -n '/=== DATABASES ===/,/=== CADDY_CONFIGS ===/p' | grep -v "===" | grep -v "^$" || true)
caddy_configs=$(echo "$resources" | sed -n '/=== CADDY_CONFIGS ===/,/=== APP_DIRS ===/p' | grep -v "===" | grep -v "^$" || true)
app_dirs=$(echo "$resources" | sed -n '/=== APP_DIRS ===/,$p' | grep -v "===" | grep -v "^$" || true)

# Display
echo ""
echo "📦 Containers:"
[ -n "$containers" ] && echo "$containers" | sed 's/^/   • /' || echo "   (none)"

echo ""
echo "💾 Databases:"
[ -n "$databases" ] && echo "$databases" | sed 's/^/   • /' || echo "   (none)"

echo ""
echo "🌐 Caddy route snippets:"
[ -n "$caddy_configs" ] && echo "$caddy_configs" | sed 's/^/   • /' || echo "   (none)"

echo ""
echo "📁 App directories:"
[ -n "$app_dirs" ] && echo "$app_dirs" | sed 's/^/   • /' || echo "   (none)"

# Check if anything to delete
if [ -z "$containers" ] && [ -z "$databases" ] && [ -z "$caddy_configs" ] && [ -z "$app_dirs" ]; then
  echo ""
  echo "📭 No resources found for branch: $BRANCH"
  exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Confirm
if [ "$SKIP_CONFIRM" = false ]; then
  read -p "⚠️  Delete all these resources? (yes/no): " confirm
  [ "$confirm" != "yes" ] && { echo "Aborted."; exit 0; }
fi

echo ""
echo "🗑️  Deleting..."

# Execute deletion on server
if [ -n "$PROJECT" ]; then
  # Delete single project
  ansible $SERVER -i $INVENTORY -m shell -a "
PROJECT='$PROJECT'
PROJECT_UNDERSCORE='$PROJECT_UNDERSCORE'
BRANCH='$BRANCH'
BRANCH_UNDERSCORE='$BRANCH_UNDERSCORE'

# 1. Stop and remove container
echo '>>> Removing container...'
docker ps -a --format '{{\"{{\"}}.Names{{\"}}\"}}' | grep -F -- \"\${PROJECT}--\${BRANCH}-\" | xargs -r docker rm -f || true

# 2. Drop database
echo '>>> Dropping database...'
cd /srv/postgres
docker compose exec -T postgres psql -U postgres -c \"DROP DATABASE IF EXISTS \\\"\${PROJECT_UNDERSCORE}__\${BRANCH_UNDERSCORE}\\\"\" || true

# 3. Remove Caddy route snippets and reassemble
echo '>>> Removing Caddy route snippets...'
cd /srv/caddy/config/preview
rm -fv routes/*---\${PROJECT}--\${BRANCH}.snippet || true

# Reassemble caddy configs from remaining snippets
echo '>>> Reassembling Caddy configs...'
if [ -d routes ] && ls routes/*.snippet 1>/dev/null 2>&1; then
  # Get all unique domains (use --- as separator)
  domains=\$(ls routes/*.snippet 2>/dev/null | xargs -n1 basename | sed 's/\\.snippet\$//' | sed 's/---.*//' | sort -u)
  for domain in \$domains; do
    {
      echo \"# Domain: \$domain\"
      echo \"# Auto-assembled from route snippets\"
      echo \"\$domain {\"
      # Sub-paths first (handle /path*)
      for snippet in routes/\${domain}---*.snippet; do
        [ -f \"\$snippet\" ] || continue
        if grep -q '^handle /' \"\$snippet\"; then
          grep -v '^#' \"\$snippet\"
        fi
      done
      # Root paths last (handle {)
      for snippet in routes/\${domain}---*.snippet; do
        [ -f \"\$snippet\" ] || continue
        if grep -q '^handle {' \"\$snippet\"; then
          grep -v '^#' \"\$snippet\"
        fi
      done
      echo \"}\"
    } > \"\${domain}.caddy\"
  done
  # Remove .caddy files for domains with no remaining snippets
  for caddy_file in *.caddy; do
    [ -f \"\$caddy_file\" ] || continue
    domain=\"\${caddy_file%.caddy}\"
    if ! ls routes/\${domain}---*.snippet 1>/dev/null 2>&1; then
      rm -fv \"\$caddy_file\"
    fi
  done
else
  # No snippets left, remove all .caddy files
  rm -fv *.caddy 2>/dev/null || true
fi

# 4. Remove app directory
echo '>>> Removing app directory...'
rm -rfv /srv/\${PROJECT}--\${BRANCH} || true

# 5. Reload Caddy
echo '>>> Reloading Caddy...'
cd /srv/caddy && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile || true

# 6. Prune images
echo '>>> Pruning unused images...'
docker image prune -f || true

echo '>>> Done'
" 2>/dev/null | grep -v "^$SERVER |" || true
else
  # Delete all projects in branch
  ansible $SERVER -i $INVENTORY -m shell -a "
BRANCH='$BRANCH'
BRANCH_UNDERSCORE='$BRANCH_UNDERSCORE'

# 1. Stop and remove containers
echo '>>> Removing containers...'
docker ps -a --format '{{\"{{\"}}.Names{{\"}}\"}}' | grep -E -- \"--\${BRANCH}-\" | xargs -r docker rm -f || true

# 2. Drop databases
echo '>>> Dropping databases...'
cd /srv/postgres
for db in \$(docker compose exec -T postgres psql -U postgres -t -A -c \"SELECT datname FROM pg_database WHERE datname LIKE '%__\${BRANCH_UNDERSCORE}'\"); do
  echo \"   Dropping: \$db\"
  docker compose exec -T postgres psql -U postgres -c \"DROP DATABASE IF EXISTS \\\"\$db\\\"\" || true
done

# 3. Remove Caddy route snippets and reassemble
echo '>>> Removing Caddy route snippets...'
cd /srv/caddy/config/preview
rm -fv routes/*---*--\${BRANCH}.snippet || true

# Reassemble caddy configs from remaining snippets
echo '>>> Reassembling Caddy configs...'
if [ -d routes ] && ls routes/*.snippet 1>/dev/null 2>&1; then
  # Get all unique domains (use --- as separator)
  domains=\$(ls routes/*.snippet 2>/dev/null | xargs -n1 basename | sed 's/\\.snippet\$//' | sed 's/---.*//' | sort -u)
  for domain in \$domains; do
    {
      echo \"# Domain: \$domain\"
      echo \"# Auto-assembled from route snippets\"
      echo \"\$domain {\"
      # Sub-paths first (handle /path*)
      for snippet in routes/\${domain}---*.snippet; do
        [ -f \"\$snippet\" ] || continue
        if grep -q '^handle /' \"\$snippet\"; then
          grep -v '^#' \"\$snippet\"
        fi
      done
      # Root paths last (handle {)
      for snippet in routes/\${domain}---*.snippet; do
        [ -f \"\$snippet\" ] || continue
        if grep -q '^handle {' \"\$snippet\"; then
          grep -v '^#' \"\$snippet\"
        fi
      done
      echo \"}\"
    } > \"\${domain}.caddy\"
  done
  # Remove .caddy files for domains with no remaining snippets
  for caddy_file in *.caddy; do
    [ -f \"\$caddy_file\" ] || continue
    domain=\"\${caddy_file%.caddy}\"
    if ! ls routes/\${domain}---*.snippet 1>/dev/null 2>&1; then
      rm -fv \"\$caddy_file\"
    fi
  done
else
  # No snippets left, remove all .caddy files
  rm -fv *.caddy 2>/dev/null || true
fi

# 4. Remove app directories
echo '>>> Removing app directories...'
rm -rfv /srv/*--\${BRANCH} || true

# 5. Reload Caddy
echo '>>> Reloading Caddy...'
cd /srv/caddy && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile || true

# 6. Prune images
echo '>>> Pruning unused images...'
docker image prune -f || true

echo '>>> Done'
" 2>/dev/null | grep -v "^$SERVER |" || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -n "$PROJECT" ]; then
  echo "✅ Preview project deleted: $PROJECT (branch: $BRANCH)"
else
  echo "✅ Preview environment deleted: $BRANCH"
fi
echo ""
echo "💡 Verify with: mise run preview-list"
