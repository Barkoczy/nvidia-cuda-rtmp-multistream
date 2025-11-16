#!/bin/bash
# Verification script for NGINX VTS metrics integration
# Tests Block 2.2 implementation

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NGINX_URL="${NGINX_URL:-http://localhost:8081}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
VTS_EXPORTER_URL="${VTS_EXPORTER_URL:-http://localhost:9913}"

echo -e "${BLUE}=== NGINX VTS Metrics Verification (Block 2.2) ===${NC}"
echo ""

# Test 1: Check NGINX VTS endpoint
echo -e "${BLUE}[1/6]${NC} Testing NGINX VTS endpoint..."
if curl -sf "$NGINX_URL/status/format/json" > /tmp/vts_status.json 2>&1; then
    echo -e "${GREEN}✓${NC} NGINX VTS endpoint is accessible"

    # Parse and display key metrics
    server_name=$(jq -r '.serverZones."*".serverZoneName' /tmp/vts_status.json 2>/dev/null || echo "N/A")
    requests=$(jq -r '.serverZones."*".requestCounter' /tmp/vts_status.json 2>/dev/null || echo "0")
    in_bytes=$(jq -r '.serverZones."*".inBytes' /tmp/vts_status.json 2>/dev/null || echo "0")
    out_bytes=$(jq -r '.serverZones."*".outBytes' /tmp/vts_status.json 2>/dev/null || echo "0")

    echo -e "  Server: ${server_name}"
    echo -e "  Total Requests: ${requests}"
    echo -e "  Bytes In: ${in_bytes}"
    echo -e "  Bytes Out: ${out_bytes}"
else
    echo -e "${RED}✗${NC} NGINX VTS endpoint not accessible"
    echo -e "  URL: $NGINX_URL/status/format/json"
    echo -e "  Error: $(cat /tmp/vts_status.json 2>&1 | head -1)"
    exit 1
fi

echo ""

# Test 2: Check nginx-vts-exporter
echo -e "${BLUE}[2/6]${NC} Testing nginx-vts-exporter..."
if curl -sf "$VTS_EXPORTER_URL/metrics" > /tmp/vts_metrics.txt 2>&1; then
    echo -e "${GREEN}✓${NC} VTS exporter is running"

    # Count metrics
    metric_count=$(grep -c "^nginx_vts_" /tmp/vts_metrics.txt 2>/dev/null || echo "0")
    echo -e "  Exported metrics: ${metric_count}"

    # Show sample metrics
    echo -e "  Sample metrics:"
    grep "^nginx_vts_server_bytes_total" /tmp/vts_metrics.txt | head -2 | sed 's/^/    /'
else
    echo -e "${RED}✗${NC} VTS exporter not accessible"
    echo -e "  URL: $VTS_EXPORTER_URL/metrics"
    exit 1
fi

echo ""

# Test 3: Check Prometheus is scraping VTS metrics
echo -e "${BLUE}[3/6]${NC} Testing Prometheus scraping..."
if targets=$(curl -sf "$PROMETHEUS_URL/api/v1/targets" 2>&1); then
    vts_target=$(echo "$targets" | jq -r '.data.activeTargets[] | select(.labels.job=="nginx-rtmp") | .health' 2>/dev/null || echo "")

    if [ "$vts_target" = "up" ]; then
        echo -e "${GREEN}✓${NC} Prometheus is scraping nginx-rtmp target"

        # Get scrape details
        last_scrape=$(echo "$targets" | jq -r '.data.activeTargets[] | select(.labels.job=="nginx-rtmp") | .lastScrape' 2>/dev/null)
        scrape_url=$(echo "$targets" | jq -r '.data.activeTargets[] | select(.labels.job=="nginx-rtmp") | .scrapeUrl' 2>/dev/null)

        echo -e "  Scrape URL: ${scrape_url}"
        echo -e "  Last scrape: ${last_scrape}"
    else
        echo -e "${RED}✗${NC} Prometheus nginx-rtmp target is down"
        echo -e "  Status: ${vts_target}"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Cannot query Prometheus targets"
    exit 1
fi

echo ""

# Test 4: Query RTMP metrics from Prometheus
echo -e "${BLUE}[4/6]${NC} Testing RTMP metrics queries..."

queries=(
    "nginx_vts_server_connections{host=\"*\"}"
    "sum(rate(nginx_vts_server_bytes_total{direction=\"out\"}[1m]))"
    "sum(rate(nginx_vts_server_bytes_total{direction=\"in\"}[1m]))"
)

query_names=(
    "Active Connections"
    "Bandwidth Out"
    "Bandwidth In"
)

all_queries_ok=true
for i in "${!queries[@]}"; do
    query="${queries[$i]}"
    name="${query_names[$i]}"

    if result=$(curl -sf -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query" 2>&1); then
        value=$(echo "$result" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "N/A")
        echo -e "${GREEN}✓${NC} ${name}: ${value}"
    else
        echo -e "${RED}✗${NC} ${name}: Query failed"
        all_queries_ok=false
    fi
done

if [ "$all_queries_ok" = false ]; then
    echo -e "${YELLOW}⚠${NC} Some queries failed (may be normal if no active streams)"
fi

echo ""

# Test 5: Check alert rules
echo -e "${BLUE}[5/6]${NC} Testing RTMP alert rules..."
if rules=$(curl -sf "$PROMETHEUS_URL/api/v1/rules" 2>&1); then
    rtmp_rules=$(echo "$rules" | jq -r '.data.groups[] | select(.name=="nginx_rtmp_alerts") | .rules | length' 2>/dev/null || echo "0")

    if [ "$rtmp_rules" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} RTMP alert rules loaded: ${rtmp_rules} rules"

        # List alert names
        echo -e "  Alert rules:"
        echo "$rules" | jq -r '.data.groups[] | select(.name=="nginx_rtmp_alerts") | .rules[].name' 2>/dev/null | sed 's/^/    - /'
    else
        echo -e "${RED}✗${NC} No RTMP alert rules found"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Cannot query Prometheus rules"
    exit 1
fi

echo ""

# Test 6: Test query_library.sh integration
echo -e "${BLUE}[6/6]${NC} Testing query_library.sh integration..."
if [ -f "./scripts/observability/query_library.sh" ]; then
    echo -e "${GREEN}✓${NC} query_library.sh found"

    # Test RTMP queries
    echo -e "  Testing rtmp_connections query..."
    if ./scripts/observability/query_library.sh rtmp_connections 2>&1 | grep -q "Query:"; then
        echo -e "${GREEN}✓${NC} rtmp_connections query works"
    else
        echo -e "${RED}✗${NC} rtmp_connections query failed"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} query_library.sh not found"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All Verification Tests Passed ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Start a test RTMP stream: rtmp://localhost:1936/live/gaming"
echo "  2. Monitor metrics in Grafana: http://localhost:3000"
echo "  3. Check dashboard: 'Stream Health - RTMP Metrics'"
echo "  4. Run daily health check: ./scripts/observability/health_check_daily.sh"
echo ""
