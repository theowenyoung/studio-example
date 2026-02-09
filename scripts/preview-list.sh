#!/bin/bash
set -e

# Preview environment listing script
# Uses double separator (-- for DNS, __ for DB) to parse branch names
# Displays projects grouped by branch with delete commands

SERVER="preview"
INVENTORY="ansible/inventory.yml"

echo "🔍 Fetching preview environments..."
echo ""

# Get containers (use -- separator)
# Container format: {project}--{branch}-{project}--{branch}-1
containers=$(ansible $SERVER -i $INVENTORY -m shell -a 'docker ps --format "{{"{{"}}.Names{{"}}"}}" | grep -E -- "--" || true' 2>/dev/null | grep -v "|" | grep -v ">>" | grep -v "^$" || true)

# Get databases (use __ separator)
# Database format: {project}__{branch}
databases=$(ansible $SERVER -i $INVENTORY -m shell -a 'cd /srv/postgres && docker compose exec -T postgres psql -U postgres -t -A -c "SELECT datname FROM pg_database WHERE datname LIKE '"'"'%__%'"'"'" || true' 2>/dev/null | grep -v "|" | grep -v ">>" | grep -v "^$" || true)

# Get app directories (use -- separator)
# Directory format: {project}--{branch}
app_dirs=$(ansible $SERVER -i $INVENTORY -m shell -a 'ls -1 /srv/ 2>/dev/null | grep -E -- "--" || true' 2>/dev/null | grep -v "|" | grep -v ">>" | grep -v "^$" || true)

# Get caddy route snippets (use --- separator)
# Snippet format: {domain}---{service_name}.snippet where service_name is {project}--{branch}
# Extract the service_name part after ---
caddy_configs=$(ansible $SERVER -i $INVENTORY -m shell -a 'ls -1 /srv/caddy/config/preview/routes/*.snippet 2>/dev/null | xargs -r -n1 basename | sed "s/\\.snippet$//" || true' 2>/dev/null | grep -v "|" | grep -v ">>" | grep -v "^$" | grep -v "basename:" || true)

# Store branch -> projects mapping
# Format: branch_projects["branch"]="project1 project2 project3"
declare -A branch_projects

# Helper to add project to branch
add_project() {
  local branch="$1"
  local project="$2"
  if [ -z "${branch_projects[$branch]}" ]; then
    branch_projects[$branch]="$project"
  elif [[ " ${branch_projects[$branch]} " != *" $project "* ]]; then
    branch_projects[$branch]="${branch_projects[$branch]} $project"
  fi
}

# From containers: pattern {project}--{branch}-{project}--{branch}-1
# Example: hono-demo--feat-pr-test-hono-demo--feat-pr-test-1
# We extract by taking the first {project}--{branch} part
while IFS= read -r name; do
  [ -z "$name" ] && continue
  if [[ "$name" == *"--"* ]]; then
    # Extract first part before the repeated pattern
    # Container name format: {project}--{branch}-{project}--{branch}-1
    # First extract {project}
    project="${name%%--*}"
    # Then extract {branch} - it's between first -- and the next occurrence of -{project}
    after_first_sep="${name#*--}"
    # Branch ends where we see -{project}- again
    branch="${after_first_sep%%-${project}--*}"
    [ -n "$branch" ] && [ -n "$project" ] && add_project "$branch" "$project"
  fi
done <<< "$containers"

# From databases: pattern {project}__{branch}
# Example: hono_demo__feat_deploy_preview
while IFS= read -r db; do
  [ -z "$db" ] && continue
  if [[ "$db" == *"__"* ]]; then
    project="${db%%__*}"
    project="${project//_/-}"  # Convert to hyphen format
    branch="${db#*__}"
    branch="${branch//_/-}"  # Convert to hyphen format
    [ -n "$branch" ] && [ -n "$project" ] && add_project "$branch" "$project"
  fi
done <<< "$databases"

# From app dirs: pattern {project}--{branch}
# Example: hono-demo--feat-pr-test
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  if [[ "$dir" == *"--"* ]]; then
    project="${dir%%--*}"
    branch="${dir#*--}"
    [ -n "$branch" ] && [ -n "$project" ] && add_project "$branch" "$project"
  fi
done <<< "$app_dirs"

# From caddy snippets: pattern {domain}---{service_name}.snippet (without .snippet extension now)
# service_name format: {project}--{branch}
# Example: hono-demo--feat-pr-test.preview.owenyoung.com---blog--feat-pr-test
# We need to extract the service_name part (after ---)
while IFS= read -r conf; do
  [ -z "$conf" ] && continue
  # conf is like: domain---service_name (service_name = project--branch)
  # Extract service_name: everything after ---
  if [[ "$conf" == *"---"* ]]; then
    service_name="${conf#*---}"
    # service_name is like: project--branch
    # Extract project and branch from service_name
    if [[ "$service_name" == *"--"* ]]; then
      project="${service_name%%--*}"
      branch="${service_name#*--}"
      [ -n "$branch" ] && [ -n "$project" ] && add_project "$branch" "$project"
    fi
  fi
done <<< "$caddy_configs"

# Display
if [ ${#branch_projects[@]} -eq 0 ]; then
  echo "📭 No preview environments found"
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Preview Environments"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Sort branches and display with projects
for branch in $(printf '%s\n' "${!branch_projects[@]}" | sort); do
  echo ""
  echo "📦 $branch  →  mr preview-delete $branch"
  # Sort and display projects
  projects_arr=($(echo "${branch_projects[$branch]}" | tr ' ' '\n' | sort))
  total_projects=${#projects_arr[@]}
  for i in "${!projects_arr[@]}"; do
    project="${projects_arr[$i]}"
    if [ $i -eq $((total_projects - 1)) ]; then
      echo "   └── $project  →  mr preview-delete $branch $project"
    else
      echo "   ├── $project  →  mr preview-delete $branch $project"
    fi
  done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary: ${#branch_projects[@]} preview environment(s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🗑️  Delete all preview environments:"
echo "   mr preview-delete-all"
