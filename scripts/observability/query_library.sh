#!/bin/bash
# PromQL and LogQL query library for observability stack
# Usage: ./query_library.sh <query_name> [time_range]
#
# Examples:
#   ./query_library.sh gpu_util
#   ./query_library.sh gpu_mem_percent
#   ./query_library.sh broadcaster_errors 1h

set -euo pipefail

QUERY_NAME="${1:-}"
TIME_RANGE="${2:-5m}"  # Default 5 minutes
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <query_name> [time_range]"
    echo ""
    echo "PromQL Queries (Prometheus):"
    echo "  GPU Metrics:"
    echo "    gpu_util              - GPU utilization %"
    echo "    gpu_mem_percent       - GPU memory usage %"
    echo "    gpu_mem_used          - GPU memory used (bytes)"
    echo "    gpu_mem_free          - GPU memory free (bytes)"
    echo "    gpu_temp              - GPU temperature (°C)"
    echo "    gpu_power             - GPU power consumption (W)"
    echo "    nvenc_util            - NVENC encoder utilization %"
    echo "    nvdec_util            - NVDEC decoder utilization %"
    echo ""
    echo "  System Metrics:"
    echo "    cpu_usage             - Host CPU usage %"
    echo "    mem_usage_percent     - Host memory usage %"
    echo "    mem_usage_bytes       - Host memory used (bytes)"
    echo "    disk_usage            - Disk usage %"
    echo "    network_rx            - Network receive rate (bytes/s)"
    echo "    network_tx            - Network transmit rate (bytes/s)"
    echo ""
    echo "  Container Metrics:"
    echo "    container_count       - Number of running containers"
    echo "    container_mem         - Container memory usage"
    echo "    container_cpu         - Container CPU usage"
    echo "    ffmpeg_count          - Number of FFmpeg processes"
    echo ""
    echo "LogQL Queries (Loki):"
    echo "    nginx_logs            - All NGINX logs"
    echo "    nginx_rtmp            - NGINX RTMP connections"
    echo "    broadcaster_all       - All broadcaster logs"
    echo "    broadcaster_errors    - Broadcaster errors only"
    echo "    broadcaster_profile   - Logs for specific profile (requires PROFILE env)"
    echo "    webhook_logs          - Webhook service logs"
    echo "    webhook_errors        - Webhook errors"
    echo "    stream_starts         - Stream start events"
    echo "    stream_stops          - Stream stop events"
    echo ""
    echo "Time range examples: 5m, 1h, 24h, 7d"
    exit 1
}

# Execute PromQL query
query_prometheus() {
    local query="$1"
    echo -e "${BLUE}Query:${NC} $query"
    echo ""

    result=$(curl -s -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query")

    # Check for errors
    if echo "$result" | jq -e '.status == "error"' &>/dev/null; then
        echo "Error: $(echo "$result" | jq -r '.error')"
        return 1
    fi

    # Pretty print results
    echo "$result" | jq -r '.data.result[] | "\(.metric | to_entries | map("\(.key)=\(.value)") | join(", ")): \(.value[1])"' || \
    echo "$result" | jq -r '.data.result'
}

# Execute PromQL range query
query_prometheus_range() {
    local query="$1"
    local range="$2"
    echo -e "${BLUE}Query:${NC} $query (range: $range)"
    echo ""

    # Calculate time range
    end_time=$(date +%s)
    start_time=$(date -d "$range ago" +%s 2>/dev/null || echo "$((end_time - 300))")

    result=$(curl -s -G "$PROMETHEUS_URL/api/v1/query_range" \
        --data-urlencode "query=$query" \
        --data-urlencode "start=$start_time" \
        --data-urlencode "end=$end_time" \
        --data-urlencode "step=30")

    # Check for errors
    if echo "$result" | jq -e '.status == "error"' &>/dev/null; then
        echo "Error: $(echo "$result" | jq -r '.error')"
        return 1
    fi

    # Pretty print results (show latest values)
    echo "$result" | jq -r '.data.result[] | "\(.metric | to_entries | map("\(.key)=\(.value)") | join(", "))"' || \
    echo "$result" | jq '.data.result'
}

# Execute LogQL query
query_loki() {
    local query="$1"
    local limit="${2:-100}"
    echo -e "${BLUE}Query:${NC} $query"
    echo ""

    result=$(curl -s -G "$LOKI_URL/loki/api/v1/query" \
        --data-urlencode "query=$query" \
        --data-urlencode "limit=$limit")

    # Pretty print logs
    echo "$result" | jq -r '.data.result[].values[][] | select(length > 0)' 2>/dev/null || \
    echo "No results found"
}

# Main query router
case "$QUERY_NAME" in
    # GPU Metrics
    gpu_util)
        query_prometheus "DCGM_FI_DEV_GPU_UTIL"
        ;;
    gpu_mem_percent)
        query_prometheus "(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100"
        ;;
    gpu_mem_used)
        query_prometheus "DCGM_FI_DEV_FB_USED"
        ;;
    gpu_mem_free)
        query_prometheus "DCGM_FI_DEV_FB_FREE"
        ;;
    gpu_temp)
        query_prometheus "DCGM_FI_DEV_GPU_TEMP"
        ;;
    gpu_power)
        query_prometheus "DCGM_FI_DEV_POWER_USAGE"
        ;;
    nvenc_util)
        query_prometheus "DCGM_FI_DEV_ENC_UTIL"
        ;;
    nvdec_util)
        query_prometheus "DCGM_FI_DEV_DEC_UTIL"
        ;;

    # System Metrics
    cpu_usage)
        query_prometheus '100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
        ;;
    mem_usage_percent)
        query_prometheus '(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100'
        ;;
    mem_usage_bytes)
        query_prometheus 'node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes'
        ;;
    disk_usage)
        query_prometheus 'node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100'
        ;;
    network_rx)
        query_prometheus 'rate(node_network_receive_bytes_total[5m])'
        ;;
    network_tx)
        query_prometheus 'rate(node_network_transmit_bytes_total[5m])'
        ;;

    # Container Metrics
    container_count)
        query_prometheus 'count(container_last_seen{name!=""})'
        ;;
    container_mem)
        query_prometheus 'container_memory_usage_bytes{name!=""}'
        ;;
    container_cpu)
        query_prometheus 'rate(container_cpu_usage_seconds_total{name!=""}[5m])'
        ;;
    ffmpeg_count)
        query_prometheus 'count(container_processes{name=~".*ffmpeg.*"})'
        ;;

    # Loki Queries
    nginx_logs)
        query_loki '{container="nginx-rtmp-staging"}'
        ;;
    nginx_rtmp)
        query_loki '{job="nginx"} |= "RTMP"'
        ;;
    broadcaster_all)
        query_loki '{job="broadcaster"}'
        ;;
    broadcaster_errors)
        query_loki '{job="broadcaster", level="ERROR"}'
        ;;
    broadcaster_profile)
        PROFILE="${PROFILE:-gaming}"
        echo "Profile: $PROFILE"
        query_loki "{job=\"broadcaster\", profile=\"$PROFILE\"}"
        ;;
    webhook_logs)
        query_loki '{container="webhook-staging"}'
        ;;
    webhook_errors)
        query_loki '{container="webhook-staging"} |= "ERROR"'
        ;;
    stream_starts)
        query_loki '{job="broadcaster"} |= "Starting stream"'
        ;;
    stream_stops)
        query_loki '{job="broadcaster"} |= "Stopping stream"'
        ;;

    "")
        usage
        ;;
    *)
        echo "Error: Unknown query name: $QUERY_NAME"
        usage
        ;;
esac
