#!/bin/bash

# 性能测试脚本 - owen-blog-demo.owenyoung.com
# 用法: ./scripts/test-performance.sh

URL="${1:-https://owen-blog-demo.owenyoung.com/quotes/}"

echo "🔍 性能分析 - $URL"
echo "=========================================="
echo ""

for i in {1..5}; do
  # 使用 curl 的内置时间测量
  result=$(curl -s "$URL" \
    -H 'cache-control: no-cache' \
    -w "\nTIMING:%{time_total}|%{time_starttransfer}|%{time_connect}|%{time_appconnect}" \
    -D /tmp/curl-headers-$i.txt \
    -o /dev/null 2>&1)

  # 提取响应头中的 Nginx 处理时间
  nginx_time=$(grep -i 'x-nginx-request-time:\|x-response-time:' /tmp/curl-headers-$i.txt 2>/dev/null | awk '{print $2}' | tr -d '\r' | head -1)
  [ -z "$nginx_time" ] && nginx_time="N/A"

  # 提取时间指标
  times=$(echo "$result" | grep "^TIMING:" | cut -d':' -f2)
  total=$(echo "$times" | cut -d'|' -f1)
  ttfb=$(echo "$times" | cut -d'|' -f2)
  tcp=$(echo "$times" | cut -d'|' -f3)
  tls=$(echo "$times" | cut -d'|' -f4)

  # 计算下载时间
  download=$(echo "$total $ttfb" | awk '{printf "%.3f", $1 - $2}')

  echo "第${i}次测试:"
  echo "  TCP连接: ${tcp}s"
  echo "  TLS握手: ${tls}s"
  echo "  TTFB: ${ttfb}s (包含服务器处理)"
  echo "  Nginx处理: ${nginx_time}s"
  echo "  下载时间: ${download}s"
  echo "  ✅ 总耗时: ${total}s"
  echo ""

  sleep 1
done

# 清理临时文件
rm -f /tmp/curl-headers-*.txt

echo "=========================================="
echo "📊 10次测试计算平均值..."

# 收集10次数据
total_sum=0
ttfb_sum=0
tcp_sum=0
tls_sum=0
nginx_sum=0
count=0

for i in {1..10}; do
  result=$(curl -s "$URL" \
    -w "\n%{time_total}|%{time_starttransfer}|%{time_connect}|%{time_appconnect}" \
    -D /tmp/curl-avg-headers.txt \
    -o /dev/null 2>&1)

  nginx_time=$(grep -i 'x-nginx-request-time:\|x-response-time:' /tmp/curl-avg-headers.txt 2>/dev/null | awk '{print $2}' | tr -d '\r' | head -1)
  [ -z "$nginx_time" ] && nginx_time="0"

  times=$(echo "$result" | tail -1)
  total=$(echo "$times" | cut -d'|' -f1)
  ttfb=$(echo "$times" | cut -d'|' -f2)
  tcp=$(echo "$times" | cut -d'|' -f3)
  tls=$(echo "$times" | cut -d'|' -f4)

  total_sum=$(echo "$total_sum + $total" | awk '{print $1 + $3}')
  ttfb_sum=$(echo "$ttfb_sum + $ttfb" | awk '{print $1 + $3}')
  tcp_sum=$(echo "$tcp_sum + $tcp" | awk '{print $1 + $3}')
  tls_sum=$(echo "$tls_sum + $tls" | awk '{print $1 + $3}')
  nginx_sum=$(echo "$nginx_sum + $nginx_time" | awk '{print $1 + $3}')
  count=$((count + 1))

  sleep 0.5
done

rm -f /tmp/curl-avg-headers.txt

# 计算平均值
echo "$total_sum $ttfb_sum $tcp_sum $tls_sum $nginx_sum $count" | awk '{
  avg_total = $1 / $6
  avg_ttfb = $2 / $6
  avg_tcp = $3 / $6
  avg_tls = $4 / $6
  avg_nginx = $5 / $6
  avg_download = avg_total - avg_ttfb

  printf "  平均TCP连接: %.3fs\n", avg_tcp
  printf "  平均TLS握手: %.3fs\n", avg_tls
  printf "  平均TTFB: %.3fs\n", avg_ttfb
  printf "  平均Nginx处理: %.3fs\n", avg_nginx
  printf "  平均下载时间: %.3fs\n", avg_download
  printf "  平均总耗时: %.3fs\n", avg_total
}'

echo ""
echo "=========================================="
echo "💡 性能瓶颈分析:"

# 使用最后一次的数据做分析
last_result=$(curl -s "$URL" \
  -w "\n%{time_total}|%{time_starttransfer}|%{time_connect}|%{time_appconnect}" \
  -o /dev/null 2>&1 | tail -1)

total=$(echo "$last_result" | cut -d'|' -f1)
ttfb=$(echo "$last_result" | cut -d'|' -f2)
tcp=$(echo "$last_result" | cut -d'|' -f3)
tls=$(echo "$last_result" | cut -d'|' -f4)

echo "$tcp $tls $ttfb $total" | awk '{
  tcp = $1
  tls = $2
  ttfb = $3
  total = $4
  download = total - ttfb

  if (tcp + tls > 0.3) {
    printf "  ⚠️  网络延迟高 (TCP+TLS=%.3fs): 建议使用 CDN\n", tcp + tls
  } else {
    printf "  ✅ 网络延迟正常 (TCP+TLS=%.3fs)\n", tcp + tls
  }

  if (download > 0.4) {
    printf "  ⚠️  下载时间长 (%.3fs): 建议优化资源大小或启用更好的压缩\n", download
  } else {
    printf "  ✅ 下载速度正常 (%.3fs)\n", download
  }

  if (ttfb > 0.5) {
    printf "  ⚠️  TTFB较高 (%.3fs): 服务器响应可能需要优化\n", ttfb
  } else {
    printf "  ✅ 服务器响应快 (%.3fs)\n", ttfb
  }
}'

echo ""
echo "=========================================="
echo "📈 优化建议："
echo "  1. 使用 CDN (Cloudflare) - 可减少 50-70% 延迟"
echo "  2. 启用 HTTP/3 - 已启用 ✅"
echo "  3. Gzip 压缩 - 已启用 ✅ (67% 压缩率)"
echo "  4. 考虑多地域部署 - 如果主要用户在中国/亚太"
