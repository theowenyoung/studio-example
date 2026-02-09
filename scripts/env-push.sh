#!/usr/bin/env bash
set -euo pipefail

# Upload environment variables to AWS Parameter Store
# File format:
#   # PREFIX=/studio-dev/umami/
#   DATABASE_URL=xxx
#   APP_SECRET=yyy
#   # PREFIX=/studio-prod/umami/
#   OTHER_VAR=zzz

ENV_FILE="${1:-.env.parameter}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: File not found: $ENV_FILE"
    exit 1
fi

echo "📤 Uploading parameters from: $ENV_FILE"

current_prefix=""
count=0
errors=0

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Check for PREFIX directive
    if [[ "$line" =~ ^#[[:space:]]*PREFIX[[:space:]]*=[[:space:]]*(.+)$ ]]; then
        current_prefix="${BASH_REMATCH[1]}"
        # Trim whitespace
        current_prefix="${current_prefix%% }"
        current_prefix="${current_prefix## }"
        # Ensure trailing slash
        [[ "$current_prefix" != */ ]] && current_prefix="${current_prefix}/"
        echo ""
        echo "📁 Prefix: $current_prefix"
        continue
    fi

    # Skip other comments
    [[ "$line" =~ ^# ]] && continue

    # Parse KEY=VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        if [[ -z "$current_prefix" ]]; then
            echo "⚠️  Skipping $key: no PREFIX defined yet"
            continue
        fi

        param_name="${current_prefix}${key}"

        # Upload to Parameter Store
        if aws ssm put-parameter \
            --name "$param_name" \
            --value "$value" \
            --type "SecureString" \
            --overwrite \
            --no-cli-pager > /dev/null 2>&1; then
            echo "  ✓ $key"
            ((++count))
        else
            echo "  ✗ $key (failed)"
            ((++errors))
        fi
    fi
done < "$ENV_FILE"

echo ""
echo "✅ Uploaded $count parameters"
[[ $errors -gt 0 ]] && echo "⚠️  $errors errors occurred"

exit $errors
