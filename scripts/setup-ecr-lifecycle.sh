#!/bin/bash
set -e

# ==========================================
# 批量设置 ECR 生命周期规则
# ==========================================
# 使用方式：
#   bash scripts/setup-ecr-lifecycle.sh
#
# 功能：
#   - 自动发现所有 studio/* 仓库
#   - 为每个仓库设置统一的生命周期规则
#   - 支持幂等操作（重复运行无副作用）
# ==========================================

ECR_REGION="${ECR_REGION:-us-west-2}"
REPO_PREFIX="studio/"

echo "🔧 Setting up ECR lifecycle policies for all repositories..."
echo "   Region: $ECR_REGION"
echo "   Prefix: $REPO_PREFIX"
echo ""

# 生命周期规则 JSON
read -r -d '' LIFECYCLE_POLICY << 'EOF' || true
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

# 获取所有匹配的仓库
echo "📋 Fetching repositories..."
REPOS=$(aws ecr describe-repositories \
  --region "$ECR_REGION" \
  --query "repositories[?starts_with(repositoryName, '$REPO_PREFIX')].repositoryName" \
  --output text)

if [ -z "$REPOS" ]; then
  echo "❌ No repositories found with prefix: $REPO_PREFIX"
  exit 1
fi

echo "✅ Found $(echo "$REPOS" | wc -w) repositories"
echo ""

# 为每个仓库设置生命周期规则
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for REPO in $REPOS; do
  echo "⚙️  Processing: $REPO"

  # 检查是否已有规则
  EXISTING_POLICY=$(aws ecr get-lifecycle-policy \
    --region "$ECR_REGION" \
    --repository-name "$REPO" \
    --query 'lifecyclePolicyText' \
    --output text 2>/dev/null || echo "")

  if [ -n "$EXISTING_POLICY" ]; then
    echo "   ⏭️  Skipping (already has lifecycle policy)"
    ((SKIP_COUNT++))
    continue
  fi

  # 设置生命周期规则
  if aws ecr put-lifecycle-policy \
    --region "$ECR_REGION" \
    --repository-name "$REPO" \
    --lifecycle-policy-text "$LIFECYCLE_POLICY" > /dev/null 2>&1; then
    echo "   ✅ Applied lifecycle policy"
    ((SUCCESS_COUNT++))
  else
    echo "   ❌ Failed to apply policy"
    ((FAIL_COUNT++))
  fi

  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary:"
echo "   Total repositories: $(echo "$REPOS" | wc -w)"
echo "   ✅ Applied: $SUCCESS_COUNT"
echo "   ⏭️  Skipped: $SKIP_COUNT"
echo "   ❌ Failed: $FAIL_COUNT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAIL_COUNT -gt 0 ]; then
  exit 1
fi

echo ""
echo "🎉 Done! All repositories now have lifecycle policies."
