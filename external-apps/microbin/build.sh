#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/build-lib.sh"

# Detect environment
detect_environment

SERVICE_BASE="microbin"
set_docker_service_name "$SERVICE_BASE"
REPO_URL="https://github.com/theowenyoung/microbin"
VERSION="$(get_version)"
REPO_ROOT="$SCRIPT_DIR/../.."

echo "Building $SERVICE_BASE (version: $VERSION)"
echo "Environment: $DEPLOY_ENV"

if [ "$DEPLOY_ENV" = "local" ]; then
  # Local dev: clone repo and build local image
  IMAGE="$SERVICE_BASE:dev"

  TEMP_DIR="$(mktemp -d)"
  trap "rm -rf $TEMP_DIR" EXIT

  echo "Cloning repository..."
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR"

  echo "Building Docker image..."
  cd "$TEMP_DIR"
  docker build \
    -f "Dockerfile.prod" \
    -t "$IMAGE" \
    .
  echo "$SERVICE_BASE built locally: $IMAGE"
else
  # Deploy mode: use pre-built image from Docker Hub
  IMAGE="owenyoung/microbin:latest"

  echo "Using pre-built image: $IMAGE"

  # Prepare deploy directory
  rm -rf "$SCRIPT_DIR/$DEPLOY_DIST"
  mkdir -p "$SCRIPT_DIR/$DEPLOY_DIST"

  # Generate environment variables
  echo "Generating environment variables..."
  psenv -t "$SCRIPT_DIR/.env.example" -p "$AWS_PARAM_PATH" -o "$SCRIPT_DIR/$DEPLOY_DIST/.env"

  # Generate docker-compose.yml
  export IMAGE_TAG="$IMAGE"
  envsubst < "$SCRIPT_DIR/docker-compose.prod.yml" > "$SCRIPT_DIR/$DEPLOY_DIST/docker-compose.yml"

  # Write version
  echo "$VERSION" > "$SCRIPT_DIR/$DEPLOY_DIST/version.txt"

  # Generate deploy summary
  generate_deploy_summary "$SCRIPT_DIR/$DEPLOY_DIST"

  echo "$SERVICE_BASE built: $SCRIPT_DIR/$DEPLOY_DIST"
  ls -lh "$SCRIPT_DIR/$DEPLOY_DIST"
fi
