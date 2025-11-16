#!/bin/bash
# Weekly health check for observability stack (detailed analysis)
# Usage: ./health_check_weekly.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Weekly Observability Stack Health Check ==="
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Expected resource usage (from OBSERVABILITY.md)
EXPECTED_RAM_MB=695
EXPECTED_DISK_GB_MONTH=8

# Check Docker volume disk usage
check_volume_usage() {
    echo -e "\n${BLUE}=== Volume Disk Usage ===${NC}"

    for volume in prometheus-data grafana-data loki-data; do
        if docker volume inspect "$volume" &>/dev/null; then
            mountpoint=$(docker volume inspect "$volume" | jq -r '.[0].Mountpoint' 2>/dev/null)
            if [ -n "$mountpoint" ] && [ -d "$mountpoint" ]; then
                size=$(sudo du -sh "$mountpoint" 2>/dev/null | awk '{print $1}')
                echo -e "  ${GREEN}✓${NC} $volume: $size"

                # Parse size for warnings
                size_mb=$(sudo du -sm "$mountpoint" 2>/dev/null | awk '{print $1}')
                if [ "$volume" = "prometheus-data" ] && [ "$size_mb" -gt 10240 ]; then
                    echo -e "    ${YELLOW}⚠${NC} Prometheus data >10GB - consider retention adjustment"
                fi
                if [ "$volume" = "loki-data" ] && [ "$size_mb" -gt 10240 ]; then
                    echo -e "    ${YELLOW}⚠${NC} Loki data >10GB - consider retention adjustment"
                fi
            else
                echo -e "  ${YELLOW}⚠${NC} $volume: Cannot access mountpoint"
            fi
        else
            echo -e "  ${RED}✗${NC} $volume: Volume not found"
        fi
    done

    echo ""
    echo "Expected disk usage: ~${EXPECTED_DISK_GB_MONTH}GB/month"
}

# Check container memory usage
check_memory_usage() {
    echo -e "\n${BLUE}=== Container Memory Usage ===${NC}"

    local total_mem=0
    for container in prometheus-staging grafana-staging loki-staging promtail-staging \
                     node-exporter-staging cadvisor-staging dcgm-exporter-staging; do
        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            mem=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" | awk '{print $1}')
            echo -e "  ${GREEN}✓${NC} $container: $mem"

            # Extract numeric value (handle MiB/GiB)
            mem_mb=$(echo "$mem" | sed 's/MiB//' | sed 's/GiB/*1024/' | bc 2>/dev/null || echo "0")
            total_mem=$(echo "$total_mem + $mem_mb" | bc)
        else
            echo -e "  ${RED}✗${NC} $container: Not running"
        fi
    done

    echo ""
    echo -e "Total observability stack memory: ${total_mem} MiB"
    echo -e "Expected memory usage: ~${EXPECTED_RAM_MB} MiB"

    if [ "$(echo "$total_mem > $EXPECTED_RAM_MB * 1.5" | bc)" -eq 1 ]; then
        echo -e "${YELLOW}⚠${NC} Memory usage is >50% higher than expected"
    fi
}

# Check alert frequency (alert fatigue detection)
check_alert_frequency() {
    echo -e "\n${BLUE}=== Alert Frequency Analysis ===${NC}"

    PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"

    # Query alerts fired in last 7 days
    query='ALERTS{alertstate="firing"}'
    end_time=$(date +%s)
    start_time=$((end_time - 604800))  # 7 days ago

    echo "Checking alert frequency for past 7 days..."

    if result=$(curl -s -G "$PROMETHEUS_URL/api/v1/query_range" \
        --data-urlencode "query=$query" \
        --data-urlencode "start=$start_time" \
        --data-urlencode "end=$end_time" \
        --data-urlencode "step=3600" 2>&1); then

        # Count unique alert names
        alert_count=$(echo "$result" | jq -r '[.data.result[].metric.alertname] | unique | length' 2>/dev/null || echo "0")

        if [ "$alert_count" -eq 0 ]; then
            echo -e "${GREEN}✓${NC} No alerts fired in the past 7 days"
        elif [ "$alert_count" -lt 5 ]; then
            echo -e "${GREEN}✓${NC} Low alert frequency: $alert_count unique alerts"
        elif [ "$alert_count" -lt 10 ]; then
            echo -e "${YELLOW}⚠${NC} Moderate alert frequency: $alert_count unique alerts"
        else
            echo -e "${RED}✗${NC} High alert frequency: $alert_count unique alerts (risk of alert fatigue)"
            echo "  Review alert thresholds and adjust as needed"
        fi

        # Show top firing alerts
        top_alerts=$(echo "$result" | jq -r '[.data.result[].metric.alertname] | group_by(.) | map({alert: .[0], count: length}) | sort_by(.count) | reverse | .[0:3]' 2>/dev/null)
        if [ -n "$top_alerts" ] && [ "$top_alerts" != "null" ]; then
            echo ""
            echo "Top firing alerts:"
            echo "$top_alerts" | jq -r '.[] | "  - \(.alert): \(.count) occurrences"'
        fi
    else
        echo -e "${RED}✗${NC} Failed to query alert history"
    fi
}

# Check Prometheus retention and TSDB health
check_prometheus_health() {
    echo -e "\n${BLUE}=== Prometheus TSDB Health ===${NC}"

    PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"

    if tsdb=$(curl -s "$PROMETHEUS_URL/api/v1/status/tsdb" 2>&1); then
        head_stats=$(echo "$tsdb" | jq -r '.data.headStats' 2>/dev/null)

        if [ -n "$head_stats" ] && [ "$head_stats" != "null" ]; then
            num_series=$(echo "$head_stats" | jq -r '.numSeries' 2>/dev/null)
            chunks_created=$(echo "$head_stats" | jq -r '.chunksCreated' 2>/dev/null)

            echo -e "  Time series: $num_series"
            echo -e "  Chunks created: $chunks_created"

            if [ "$num_series" -gt 100000 ]; then
                echo -e "  ${YELLOW}⚠${NC} High number of time series - consider label reduction"
            fi
        fi
    fi

    # Check configuration
    if config=$(curl -s "$PROMETHEUS_URL/api/v1/status/config" 2>&1); then
        retention=$(echo "$config" | jq -r '.data.yaml' | grep "retention.time" | awk '{print $2}' || echo "unknown")
        echo -e "  Retention: ${retention:-30d (default)}"
    fi
}

# Check Loki retention
check_loki_retention() {
    echo -e "\n${BLUE}=== Loki Configuration ===${NC}"

    if docker exec loki-staging cat /etc/loki/config.yml 2>/dev/null | grep -A 5 "retention_period"; then
        echo -e "${GREEN}✓${NC} Loki retention configuration found"
    else
        echo -e "${YELLOW}⚠${NC} Could not verify Loki retention configuration"
    fi
}

# Check for container restarts
check_container_restarts() {
    echo -e "\n${BLUE}=== Container Restart History ===${NC}"

    for container in prometheus-staging grafana-staging loki-staging promtail-staging \
                     node-exporter-staging cadvisor-staging dcgm-exporter-staging; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            restarts=$(docker inspect "$container" | jq -r '.[0].RestartCount' 2>/dev/null || echo "unknown")
            status=$(docker inspect "$container" | jq -r '.[0].State.Status' 2>/dev/null || echo "unknown")

            if [ "$restarts" != "0" ] && [ "$restarts" != "unknown" ]; then
                echo -e "  ${YELLOW}⚠${NC} $container: $restarts restarts (status: $status)"
            elif [ "$status" = "running" ]; then
                echo -e "  ${GREEN}✓${NC} $container: No restarts"
            else
                echo -e "  ${RED}✗${NC} $container: Status $status"
            fi
        fi
    done
}

# Version check
check_versions() {
    echo -e "\n${BLUE}=== Component Versions ===${NC}"

    echo "Prometheus: $(docker exec prometheus-staging prometheus --version 2>&1 | head -1 || echo 'unknown')"
    echo "Grafana: $(docker exec grafana-staging grafana-cli --version 2>&1 || echo 'unknown')"
    echo "Loki: $(docker exec loki-staging /usr/bin/loki --version 2>&1 | head -1 || echo 'unknown')"
    echo ""
    echo "Tip: Check for updates at:"
    echo "  - https://github.com/prometheus/prometheus/releases"
    echo "  - https://github.com/grafana/grafana/releases"
    echo "  - https://github.com/grafana/loki/releases"
}

# Main execution
main() {
    check_volume_usage
    check_memory_usage
    check_alert_frequency
    check_prometheus_health
    check_loki_retention
    check_container_restarts
    check_versions

    echo ""
    echo -e "${BLUE}=== Weekly Review Checklist ===${NC}"
    echo "  [ ] Review Grafana dashboards for anomalies"
    echo "  [ ] Check for frequent alerts (risk of alert fatigue)"
    echo "  [ ] Verify disk usage is within expected bounds"
    echo "  [ ] Review container restart history"
    echo "  [ ] Check for component updates"
    echo ""
}

main "$@"
