#!/bin/bash
# 零停机部署测试脚本
# 用法: ./test-zero-downtime.sh <service-url>
# 示例: ./test-zero-downtime.sh https://hono-demo.yourdomain.com

set -e

URL="${1}"
if [ -z "$URL" ]; then
  echo "错误：请提供服务 URL"
  echo "用法: $0 <service-url>"
  echo "示例: $0 https://hono-demo.yourdomain.com"
  exit 1
fi

echo "🚀 开始零停机部署测试"
echo "📍 目标服务: $URL"
echo "⏱️  测试开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "请在另一个终端运行部署命令："
echo "  mr deploy-hono-demo"
echo ""
echo "按 Ctrl+C 停止测试"
echo "================================================================"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
TIMEOUT_COUNT=0
START_TIME=$(date +%s)

# 创建临时日志文件
LOG_FILE="/tmp/zero-downtime-test-$(date +%s).log"
echo "详细日志: $LOG_FILE"
echo ""

while true; do
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

  # 使用 curl 发送请求，5 秒超时
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" --max-time 5 "$URL" 2>&1 || echo "timeout|0")
  HTTP_CODE=$(echo "$RESPONSE" | cut -d'|' -f1)
  TIME_TOTAL=$(echo "$RESPONSE" | cut -d'|' -f2)

  if [ "$HTTP_CODE" = "200" ]; then
    echo -e "[$TIMESTAMP] ✅ 成功 - HTTP $HTTP_CODE - 响应时间: ${TIME_TOTAL}s" | tee -a "$LOG_FILE"
    ((SUCCESS_COUNT++))
  elif [ "$HTTP_CODE" = "timeout" ]; then
    echo -e "[$TIMESTAMP] ⏱️  超时 - 请求超过 5 秒" | tee -a "$LOG_FILE"
    ((TIMEOUT_COUNT++))
  else
    echo -e "[$TIMESTAMP] ❌ 失败 - HTTP $HTTP_CODE" | tee -a "$LOG_FILE"
    ((FAIL_COUNT++))
  fi

  # 每 10 次请求显示统计信息
  TOTAL=$((SUCCESS_COUNT + FAIL_COUNT + TIMEOUT_COUNT))
  if [ $((TOTAL % 10)) -eq 0 ] && [ $TOTAL -gt 0 ]; then
    ELAPSED=$(($(date +%s) - START_TIME))
    SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS_COUNT/$TOTAL)*100}")
    echo ""
    echo "📊 统计 (运行时间: ${ELAPSED}s)"
    echo "  成功: $SUCCESS_COUNT | 失败: $FAIL_COUNT | 超时: $TIMEOUT_COUNT | 总计: $TOTAL"
    echo "  成功率: ${SUCCESS_RATE}%"
    echo ""
  fi

  sleep 0.5
done
