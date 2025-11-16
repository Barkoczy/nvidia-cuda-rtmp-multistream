#!/bin/bash
# Daily health check for observability stack
# Usage: ./health_check_daily.sh

set -euo pipefail

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"
DCGM_URL="${DCGM_URL:-http://localhost:9400}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Daily Observability Stack Health Check ==="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Function to check HTTP endpoint
check_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"

    if response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>&1); then
        if [ "$response" = "$expected_status" ]; then
            echo -e "${GREEN}✓${NC} $name is healthy (HTTP $response)"
            return 0
        else
            echo -e "${RED}✗${NC} $name returned HTTP $response (expected $expected_status)"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} $name is unreachable"
        return 1
    fi
}

# Check Prometheus targets
check_prometheus_targets() {
    echo -e "\n--- Prometheus Targets ---"

    if targets=$(curl -s "$PROMETHEUS_URL/api/v1/targets" 2>&1); then
        active_targets=$(echo "$targets" | jq -r '.data.activeTargets | length' 2>/dev/null)
        up_targets=$(echo "$targets" | jq -r '[.data.activeTargets[] | select(.health=="up")] | length' 2>/dev/null)

        if [ "$active_targets" = "$up_targets" ]; then
            echo -e "${GREEN}✓${NC} All $active_targets targets are UP"
        else
            echo -e "${YELLOW}⚠${NC} $up_targets/$active_targets targets are UP"
            echo "$targets" | jq -r '.data.activeTargets[] | select(.health!="up") | "  - \(.scrapePool): \(.lastError)"' 2>/dev/null
        fi

        # Check specific critical targets
        for target in "node-exporter" "cadvisor" "dcgm-exporter"; do
            status=$(echo "$targets" | jq -r ".data.activeTargets[] | select(.labels.job==\"$target\") | .health" 2>/dev/null | head -1)
            if [ "$status" = "up" ]; then
                echo -e "  ${GREEN}✓${NC} $target"
            else
                echo -e "  ${RED}✗${NC} $target is DOWN"
            fi
        done
    else
        echo -e "${RED}✗${NC} Failed to query Prometheus targets"
        return 1
    fi
}

# Check Prometheus alerts
check_prometheus_alerts() {
    echo -e "\n--- Prometheus Alerts ---"

    if alerts=$(curl -s "$PROMETHEUS_URL/api/v1/alerts" 2>&1); then
        firing=$(echo "$alerts" | jq -r '[.data.alerts[] | select(.state=="firing")] | length' 2>/dev/null)
        pending=$(echo "$alerts" | jq -r '[.data.alerts[] | select(.state=="pending")] | length' 2>/dev/null)

        if [ "$firing" -eq 0 ]; then
            echo -e "${GREEN}✓${NC} No firing alerts"
        else
            echo -e "${RED}✗${NC} $firing alerts are FIRING:"
            echo "$alerts" | jq -r '.data.alerts[] | select(.state=="firing") | "  - \(.labels.alertname): \(.annotations.summary)"' 2>/dev/null
        fi

        if [ "$pending" -gt 0 ]; then
            echo -e "${YELLOW}⚠${NC} $pending alerts are PENDING"
        fi
    else
        echo -e "${RED}✗${NC} Failed to query Prometheus alerts"
        return 1
    fi
}

# Check GPU metrics
check_gpu_metrics() {
    echo -e "\n--- GPU Metrics (DCGM) ---"

    if metrics=$(curl -s "$DCGM_URL/metrics" 2>&1); then
        gpu_util=$(echo "$metrics" | grep "^DCGM_FI_DEV_GPU_UTIL{" | head -1 | awk '{print $2}')
        gpu_temp=$(echo "$metrics" | grep "^DCGM_FI_DEV_GPU_TEMP{" | head -1 | awk '{print $2}')

        if [ -n "$gpu_util" ]; then
            echo -e "  GPU Utilization: ${gpu_util}%"
            if [ "${gpu_util%.*}" -gt 85 ]; then
                echo -e "  ${YELLOW}⚠${NC} GPU utilization is high (>85%)"
            fi
        fi

        if [ -n "$gpu_temp" ]; then
            echo -e "  GPU Temperature: ${gpu_temp}°C"
            if [ "${gpu_temp%.*}" -gt 80 ]; then
                echo -e "  ${YELLOW}⚠${NC} GPU temperature is high (>80°C)"
            fi
        fi
    else
        echo -e "${RED}✗${NC} Failed to query GPU metrics"
        return 1
    fi
}

# Check Grafana datasources
check_grafana_datasources() {
    echo -e "\n--- Grafana Datasources ---"

    # Note: Requires Grafana API token for production use
    # For now, just check if Grafana is accessible
    if check_endpoint "Grafana UI" "$GRAFANA_URL/login" 200; then
        echo -e "  ${YELLOW}ℹ${NC} Login to Grafana and verify datasources manually:"
        echo "  - Prometheus: Test connection"
        echo "  - Loki: Test connection"
    fi
}

# Check Loki
check_loki() {
    echo -e "\n--- Loki Logs ---"

    if labels=$(curl -s "$LOKI_URL/loki/api/v1/label" 2>&1); then
        label_count=$(echo "$labels" | jq -r '.data | length' 2>/dev/null)
        echo -e "${GREEN}✓${NC} Loki is receiving logs ($label_count labels)"
    else
        echo -e "${RED}✗${NC} Failed to query Loki"
        return 1
    fi
}

# Check RTMP metrics
check_rtmp_metrics() {
    echo -e "\n--- RTMP Streaming Metrics ---"

    # Check active streams
    if streams=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=nginx_vts_server_connections{host=\"*\"}" 2>&1); then
        stream_count=$(echo "$streams" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
        echo -e "  Active Connections: ${stream_count}"

        if [ "$stream_count" = "0" ]; then
            echo -e "  ${YELLOW}ℹ${NC} No active RTMP connections"
        else
            echo -e "  ${GREEN}✓${NC} RTMP server is handling connections"
        fi
    else
        echo -e "${RED}✗${NC} Failed to query RTMP connection metrics"
        return 1
    fi

    # Check bandwidth
    if bandwidth=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=sum(rate(nginx_vts_server_bytes_total{direction=\"out\"}[1m]))" 2>&1); then
        bw_value=$(echo "$bandwidth" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
        bw_mbps=$(echo "$bw_value" | awk '{printf "%.2f", $1 * 8 / 1000000}')
        echo -e "  Outgoing Bandwidth: ${bw_mbps} Mbps"

        # Warning threshold: 50 Mbps (6250000 bytes/s)
        if [ "${bw_value%.*}" -gt 6250000 ]; then
            echo -e "  ${YELLOW}⚠${NC} Bandwidth is high (>50 Mbps)"
        fi

        # Critical threshold: 100 Mbps (12500000 bytes/s)
        if [ "${bw_value%.*}" -gt 12500000 ]; then
            echo -e "  ${RED}⚠${NC} Bandwidth is critical (>100 Mbps)"
        fi
    else
        echo -e "${RED}✗${NC} Failed to query RTMP bandwidth metrics"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0

    echo "=== Service Endpoints ==="
    check_endpoint "Prometheus" "$PROMETHEUS_URL/-/healthy" || exit_code=1
    check_endpoint "Grafana" "$GRAFANA_URL/api/health" || exit_code=1
    check_endpoint "Loki" "$LOKI_URL/ready" || exit_code=1
    check_endpoint "DCGM Exporter" "$DCGM_URL/metrics" || exit_code=1

    check_prometheus_targets || exit_code=1
    check_prometheus_alerts || exit_code=1
    check_gpu_metrics || exit_code=1
    check_rtmp_metrics || exit_code=1
    check_grafana_datasources || exit_code=1
    check_loki || exit_code=1

    echo ""
    echo "=== Summary ==="
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All checks passed"
    else
        echo -e "${RED}✗${NC} Some checks failed - review above output"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Open Grafana dashboard 'NVIDIA GPU Metrics' at $GRAFANA_URL"
    echo "  2. Open Grafana dashboard 'System Overview' at $GRAFANA_URL"
    echo "  3. Open Grafana dashboard 'Stream Health - RTMP Metrics' at $GRAFANA_URL"
    echo "  4. Check Prometheus alerts at $PROMETHEUS_URL/alerts"

    return $exit_code
}

main "$@"
