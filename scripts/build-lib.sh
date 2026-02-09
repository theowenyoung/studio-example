#!/usr/bin/env bash
set -euo pipefail

export ECR_REGISTRY="YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com"
export ECR_REGION="us-west-2"
export DEPLOY_DIST="deploy-dist"

# ===== 生成统一版本号（YYYYMMDDHHmmss）=====
# 使用 UTC 时区避免不同机器时区差异
get_version() {
  date -u +%Y%m%d%H%M%S
}

# ===== ECR 登录 =====
ecr_login() {
  echo "🔐 Logging into ECR..."
  aws ecr get-login-password --region "$ECR_REGION" |
    docker login --username AWS --password-stdin "$ECR_REGISTRY"
}

# ===== 应用 ECR 生命周期规则 =====
apply_ecr_lifecycle_policy() {
  local repo_name="$1"

  local policy=$(
    cat <<'EOF'
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "删除1天前的未标记镜像",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "生产环境：保留最新5个 prod-* 镜像",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["prod-"],
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 3,
      "description": "预览环境：删除3天前的 preview-* 镜像",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["preview-"],
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 3
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
  )

  if aws ecr put-lifecycle-policy \
    --repository-name "$repo_name" \
    --region "$ECR_REGION" \
    --lifecycle-policy-text "$policy" >/dev/null 2>&1; then
    echo "✅ Lifecycle policy applied"
    return 0
  else
    echo "⚠️  Failed to apply lifecycle policy (non-critical)"
    return 1
  fi
}

# ===== 确保 ECR 仓库存在 =====
ensure_ecr_repo() {
  local repo_name="$1"

  echo "🔍 Checking if ECR repository exists: $repo_name"

  if aws ecr describe-repositories --repository-names "$repo_name" --region "$ECR_REGION" >/dev/null 2>&1; then
    echo "✅ Repository already exists: $repo_name"

    # 检查是否有生命周期规则
    if ! aws ecr get-lifecycle-policy --repository-name "$repo_name" --region "$ECR_REGION" >/dev/null 2>&1; then
      echo "⚙️  Setting up lifecycle policy..."
      apply_ecr_lifecycle_policy "$repo_name"
    fi
  else
    echo "📦 Creating ECR repository: $repo_name"
    aws ecr create-repository \
      --repository-name "$repo_name" \
      --region "$ECR_REGION" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256
    echo "✅ Repository created: $repo_name"

    # 新仓库立即设置生命周期规则
    echo "⚙️  Setting up lifecycle policy..."
    apply_ecr_lifecycle_policy "$repo_name"
  fi
}

# ===== 构建并推送 Docker 镜像 =====
build_and_push_image() {
  local image_name="$1"
  local version="$2"
  local dockerfile="$3"
  shift 3
  # 剩余参数 "$@" 是 build args

  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"

  cd "$repo_root"

  # 确保环境已检测
  detect_environment

  # 生成标签
  local tag_latest=$(get_image_tag "latest")
  local tag_versioned=$(get_image_tag "versioned")

  echo "📦 Building: $image_name"
  echo "   Tags: $tag_latest, $tag_versioned"
  docker build \
    --platform linux/amd64 \
    -f "$dockerfile" \
    "$@" \
    -t "$image_name:$tag_latest" \
    -t "$image_name:$tag_versioned" \
    .

  echo "📤 Pushing to ECR..."
  ecr_login

  # 从镜像名称中提取仓库名（去掉 registry 前缀）
  # 例如：YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/studio/hono-demo -> studio/hono-demo
  local repo_name="${image_name#$ECR_REGISTRY/}"
  ensure_ecr_repo "$repo_name"

  docker push "$image_name:$tag_latest"
  docker push "$image_name:$tag_versioned"

  # 导出镜像标签供调用者使用
  export IMAGE_TAG_VERSIONED="$image_name:$tag_versioned"
  export IMAGE_TAG_LATEST="$image_name:$tag_latest"
}

# ===== 环境检测 =====
# 注入基础设施上下文变量 (CTX_*) 供 psenv 模板渲染使用
#
# 环境类型:
#   - local: 本地开发 (LOCAL_DEV=true)，使用 /studio-dev/ 参数，忽略分支
#   - prod: 生产部署 (main 分支)，使用 /studio-prod/ 参数
#   - preview: 预览部署 (其他分支)，使用 /studio-dev/ 参数
#
# LOCAL_DEV=true 时强制使用本地开发配置，与分支无关
detect_environment() {
  # 如果已经检测过，直接返回（幂等性）
  if [ -n "${DEPLOY_ENV:-}" ]; then
    echo "ℹ️  Environment already detected: $DEPLOY_ENV"
    return 0
  fi

  # === 本地开发模式 ===
  # LOCAL_DEV=true 时，强制使用 dev 参数，忽略分支
  if [ "${LOCAL_DEV:-}" = "true" ]; then
    export DEPLOY_ENV="local"
    export CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    export BRANCH_CLEAN="local"
    export DEPLOY_TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
    export CTX_SERVICE_NAME=$(basename "$PWD")

    # 本地开发上下文
    export CTX_DB_SUFFIX=""
    export CTX_DNS_SUFFIX=""
    export CTX_ROOT_DOMAIN="local.owenyoung.com"
    export CTX_PG_HOST="postgres"
    export CTX_REDIS_HOST="redis"

    # 本地开发使用 dev 参数
    export AWS_PARAM_PATH="/studio-dev/"

    echo "🔧 Environment: $DEPLOY_ENV (local development)"
    echo "🌳 Branch: $CURRENT_BRANCH (ignored for local dev)"
    echo "📦 Service: $CTX_SERVICE_NAME"
    echo "🔐 AWS Param Path: $AWS_PARAM_PATH"
    return 0
  fi

  # === 部署模式：根据分支检测 ===
  # 检测分支名（支持 CI 环境）
  local current_branch
  if [ -n "${GITHUB_HEAD_REF:-}" ]; then
    # GitHub Actions PR: GITHUB_HEAD_REF 是源分支名
    current_branch="$GITHUB_HEAD_REF"
  elif [ -n "${GITHUB_REF_NAME:-}" ]; then
    # GitHub Actions push: GITHUB_REF_NAME 是分支名
    current_branch="$GITHUB_REF_NAME"
  else
    # 本地开发
    current_branch=$(git rev-parse --abbrev-ref HEAD)
  fi
  export CURRENT_BRANCH="$current_branch"

  # 清洗分支名，用于生成后缀
  export BRANCH_CLEAN=$(echo "$current_branch" | sed 's/[^a-zA-Z0-9-]/-/g' | tr '[:upper:]' '[:lower:]' | cut -c1-30)
  export DEPLOY_TIMESTAMP=$(date -u +%Y%m%d%H%M%S)

  # 服务名：从当前目录名推断（monorepo 约定）
  # 注意：这可能不准确，build.sh 应该在调用后设置正确的 SERVICE_BASE
  export CTX_SERVICE_NAME=$(basename "$PWD")

  if [ "$current_branch" = "main" ]; then
    # === Production Environment ===
    export DEPLOY_ENV="prod"
    export ANSIBLE_TARGET="prod1"  # 默认使用 prod1，可通过 DEPLOY_SERVER 覆盖

    # 生产环境上下文
    # 注意：不需要后缀，域名等配置通常在 AWS Parameter Store 中
    export CTX_DB_SUFFIX=""
    export CTX_DNS_SUFFIX=""
    export CTX_ROOT_DOMAIN="owenyoung.com"

    export CTX_PG_HOST="postgres"
    export CTX_REDIS_HOST="redis"

    # AWS Parameter Store 路径
    export AWS_PARAM_PATH="/studio-prod/"
  else
    # === Preview Environment ===
    export DEPLOY_ENV="preview"
    export ANSIBLE_TARGET="preview"

    # 预览环境上下文
    # 使用双分隔符便于解析：服务名--分支名 / 服务名__分支名
    # 1. 数据库后缀 (双下划线分隔): __feat_auth
    export CTX_DB_SUFFIX="__${BRANCH_CLEAN//-/_}"

    # 2. 域名后缀 (双中划线分隔): --feat-auth
    export CTX_DNS_SUFFIX="--${BRANCH_CLEAN}"

    # 3. 基础设施 Host (Docker Service Name)
    export CTX_PG_HOST="postgres"
    export CTX_REDIS_HOST="redis"

    # 4. 根域名
    export CTX_ROOT_DOMAIN="preview.owenyoung.com"

    # AWS Parameter Store 路径
    export AWS_PARAM_PATH="/studio-dev/"
  fi

  echo "🔧 Environment: $DEPLOY_ENV"
  echo "🌳 Branch: $current_branch (clean: $BRANCH_CLEAN)"
  echo "📦 Service: $CTX_SERVICE_NAME"
  echo "🔐 AWS Param Path: $AWS_PARAM_PATH"
  if [ "$DEPLOY_ENV" = "preview" ]; then
    echo "📊 Context: DB_SUFFIX=$CTX_DB_SUFFIX, DNS_SUFFIX=$CTX_DNS_SUFFIX"
  fi
}

# ===== 生成镜像标签 =====
get_image_tag() {
  local tag_type=$1 # "latest" or "versioned"

  if [ "$DEPLOY_ENV" = "preview" ]; then
    if [ "$tag_type" = "latest" ]; then
      echo "preview-${BRANCH_CLEAN}"
    else
      echo "preview-${BRANCH_CLEAN}-${DEPLOY_TIMESTAMP}"
    fi
  else
    # 生产环境加 prod- 前缀
    if [ "$tag_type" = "latest" ]; then
      echo "prod-latest"
    else
      echo "prod-${DEPLOY_TIMESTAMP}"
    fi
  fi
}

# ===== 设置 Docker 服务名 =====
# 必须在 detect_environment 之后调用，传入服务基础名
# 用法: set_docker_service_name "hono-demo"
set_docker_service_name() {
  local service_base="$1"

  if [ "$DEPLOY_ENV" = "preview" ]; then
    export DOCKER_SERVICE_NAME="${service_base}--${BRANCH_CLEAN}"
  else
    export DOCKER_SERVICE_NAME="$service_base"
  fi

  echo "🐳 Docker Service: $DOCKER_SERVICE_NAME"
}

# ===== 检查服务器是否在 inventory 中 =====
# 用法: check_server_configured "prod2"
# 返回: 0 存在, 1 不存在
check_server_configured() {
  local server="$1"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

  if grep -qE "^\\s+${server}:" "$repo_root/ansible/inventory.yml" 2>/dev/null; then
    return 0
  fi
  return 1
}

# ===== 获取 .env 文件中的 DEPLOY_SERVER =====
# 用法: get_deploy_server "/path/to/.env.example"
get_deploy_server() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    grep -E "^DEPLOY_SERVER=" "$env_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || true
  fi
}

# ===== 列出可用的 prod 服务器 =====
list_available_servers() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
  grep -E "^\\s+prod[0-9]+:" "$repo_root/ansible/inventory.yml" 2>/dev/null | sed 's/://g' | awk '{print $1}'
}

# ===== 生成部署摘要文件 =====
# 从 deploy-dist/.env 中提取 PUBLIC_URL* 和 PUBLIC_PORT* 变量
# 生成两个文件:
#   - DEPLOY_SUMMARY.txt: URL 列表（供 GitHub Actions 显示）
#   - DEPLOY_ROUTES.txt: domain|path|port 格式（供 Caddy 配置生成）
# 用法: generate_deploy_summary "/path/to/deploy-dist"
generate_deploy_summary() {
  local deploy_dist_dir="$1"
  local summary_file="$deploy_dist_dir/DEPLOY_SUMMARY.txt"
  local routes_file="$deploy_dist_dir/DEPLOY_ROUTES.txt"
  local env_file="$deploy_dist_dir/.env"

  # 如果没有 .env 文件，尝试从环境变量生成
  if [ ! -f "$env_file" ]; then
    if [ -n "${PUBLIC_URL:-}" ]; then
      echo "$PUBLIC_URL" > "$summary_file"
      # 提取 domain 和 path，默认端口 3000
      local url_without_scheme=$(echo "$PUBLIC_URL" | sed 's|^https://||')
      local domain=$(echo "$url_without_scheme" | cut -d'/' -f1)
      local path=$(echo "$url_without_scheme" | grep -o '/.*' || echo "/")
      [ -z "$path" ] && path="/"
      echo "${domain}|${path}|3000" > "$routes_file"
      echo "📝 Generated DEPLOY_SUMMARY.txt and DEPLOY_ROUTES.txt (from env var)"
      return 0
    fi
    echo "⚠️  No .env file found, skipping summary generation"
    return 0
  fi

  # 清空输出文件
  > "$summary_file"
  > "$routes_file"

  # 提取所有 PUBLIC_URL* 变量并生成 routes
  # 格式: PUBLIC_URL=xxx, PUBLIC_URL_ADMIN=xxx
  # 对应: PUBLIC_PORT (默认 3000), PUBLIC_PORT_ADMIN
  while IFS='=' read -r key value; do
    # 跳过空行
    [ -z "$key" ] && continue

    # 提取后缀 (PUBLIC_URL -> "", PUBLIC_URL_ADMIN -> "_ADMIN")
    local suffix="${key#PUBLIC_URL}"

    # 查找对应的端口，默认 3000
    local port_key="PUBLIC_PORT${suffix}"
    local port=$(grep "^${port_key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- || true)
    port="${port:-3000}"

    # 提取 domain 和 path (去掉 https://)
    local url_without_scheme=$(echo "$value" | sed 's|^https://||')
    local domain=$(echo "$url_without_scheme" | cut -d'/' -f1)
    local path=$(echo "$url_without_scheme" | grep -o '/.*' || echo "/")
    [ -z "$path" ] && path="/"

    # 写入文件
    echo "$value" >> "$summary_file"
    echo "${domain}|${path}|${port}" >> "$routes_file"

    echo "  📍 $value -> path=$path port=$port"
  done < <(grep "^PUBLIC_URL" "$env_file" 2>/dev/null || true)

  if [ -s "$summary_file" ]; then
    echo "📝 Generated DEPLOY_SUMMARY.txt and DEPLOY_ROUTES.txt"
  else
    echo "ℹ️  No PUBLIC_URL found in .env"
    rm -f "$summary_file" "$routes_file"
  fi
}
