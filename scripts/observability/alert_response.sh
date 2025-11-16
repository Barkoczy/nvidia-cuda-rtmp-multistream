#!/bin/bash
# Alert response automation for observability stack
# Usage: ./alert_response.sh <alert_type>
#
# Alert types:
#   gpu_high - High GPU utilization
#   gpu_critical - Critical GPU utilization
#   gpu_temp_high - High GPU temperature
#   gpu_temp_critical - Critical GPU temperature
#   nvenc_limit - NVENC session limit
#   ffmpeg_missing - FFmpeg process missing
#   webhook_unhealthy - Webhook unhealthy

set -euo pipefail

ALERT_TYPE="${1:-}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <alert_type>"
    echo ""
    echo "Alert types:"
    echo "  gpu_high           - High GPU utilization (>85%)"
    echo "  gpu_critical       - Critical GPU utilization (>95%)"
    echo "  gpu_temp_high      - High GPU temperature (>80°C)"
    echo "  gpu_temp_critical  - Critical GPU temperature (>85°C)"
    echo "  nvenc_limit        - NVENC session limit (>90%)"
    echo "  ffmpeg_missing     - FFmpeg process missing"
    echo "  webhook_unhealthy  - Webhook unhealthy"
    echo "  rtmp_dropped       - RTMP stream dropped"
    exit 1
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    curl -s -G "$PROMETHEUS_URL/api/v1/query" --data-urlencode "query=$query" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0"
}

# Function to query Loki
query_loki() {
    local query="$1"
    local limit="${2:-100}"
    curl -s -G "$LOKI_URL/loki/api/v1/query" \
        --data-urlencode "query=$query" \
        --data-urlencode "limit=$limit" | jq -r '.data.result[]' 2>/dev/null
}

# GPU High/Critical Utilization Response
handle_gpu_utilization() {
    local severity="$1"  # high or critical

    echo -e "${BLUE}=== GPU Utilization Alert Response ===${NC}"
    echo "Severity: $severity"
    echo ""

    # Get current GPU utilization
    gpu_util=$(query_prometheus 'DCGM_FI_DEV_GPU_UTIL')
    echo "Current GPU utilization: ${gpu_util}%"

    # Check active streams
    echo -e "\n${BLUE}Checking active streams:${NC}"
    streams=$(query_loki '{job="broadcaster"} |= "Starting stream"')
    stream_count=$(echo "$streams" | jq -r '.values | length' 2>/dev/null || echo "0")
    echo "Active stream count (from logs): $stream_count"

    # List FFmpeg processes
    echo -e "\n${BLUE}FFmpeg processes:${NC}"
    if docker compose ps nginx-rtmp-staging &>/dev/null; then
        docker compose exec -T nginx-rtmp-staging ps aux | grep ffmpeg | grep -v grep || echo "No FFmpeg processes found"
    fi

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    if [ "$severity" = "critical" ]; then
        echo -e "${RED}CRITICAL:${NC} GPU utilization is critically high (>95%)"
        echo "  1. IMMEDIATELY reduce number of concurrent streams"
        echo "  2. Stop non-critical streams:"
        echo "     docker compose exec nginx-rtmp-staging /usr/local/bin/broadcaster --profile PROFILE_NAME --stop"
        echo "  3. Consider lowering bitrate or resolution in profiles.yml"
    else
        echo -e "${YELLOW}WARNING:${NC} GPU utilization is high (>85%)"
        echo "  1. Monitor for next 5 minutes"
        echo "  2. If sustained, reduce concurrent streams"
        echo "  3. Review encoding profiles for optimization"
    fi

    # Show GPU metrics
    echo -e "\n${BLUE}Current GPU metrics:${NC}"
    curl -s http://localhost:9400/metrics | grep -E "DCGM_FI_DEV_GPU_UTIL|DCGM_FI_DEV_GPU_TEMP|DCGM_FI_DEV_FB_USED|DCGM_FI_DEV_ENC_UTIL" | head -10
}

# GPU Temperature Response
handle_gpu_temperature() {
    local severity="$1"  # high or critical

    echo -e "${BLUE}=== GPU Temperature Alert Response ===${NC}"
    echo "Severity: $severity"
    echo ""

    # Get current temperature
    gpu_temp=$(query_prometheus 'DCGM_FI_DEV_GPU_TEMP')
    echo "Current GPU temperature: ${gpu_temp}°C"

    # Get GPU utilization to correlate
    gpu_util=$(query_prometheus 'DCGM_FI_DEV_GPU_UTIL')
    echo "Current GPU utilization: ${gpu_util}%"

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    if [ "$severity" = "critical" ]; then
        echo -e "${RED}CRITICAL:${NC} GPU temperature is critically high (>85°C)"
        echo "  1. IMMEDIATELY reduce GPU load"
        echo "  2. Stop streams to reduce temperature:"
        echo "     docker compose exec nginx-rtmp-staging pkill -9 ffmpeg"
        echo "  3. Check physical cooling (fans, dust, airflow)"
        echo "  4. Consider thermal repaste if persistent"
    else
        echo -e "${YELLOW}WARNING:${NC} GPU temperature is high (>80°C)"
        echo "  1. Check cooling system (fans working?)"
        echo "  2. Verify case airflow and ventilation"
        echo "  3. Monitor for next 3 minutes"
        echo "  4. Reduce encoding load if temperature rises"
    fi

    # Physical checks reminder
    echo -e "\n${BLUE}Physical checks to perform:${NC}"
    echo "  - Clean dust from GPU fans and heatsink"
    echo "  - Verify case fans are operational"
    echo "  - Check ambient temperature of server room"
    echo "  - Inspect thermal paste (if >2 years old)"
}

# NVENC Session Limit Response
handle_nvenc_limit() {
    echo -e "${BLUE}=== NVENC Session Limit Alert Response ===${NC}"
    echo ""

    # Get NVENC utilization
    nvenc_util=$(query_prometheus 'DCGM_FI_DEV_ENC_UTIL')
    echo "Current NVENC utilization: ${nvenc_util}%"
    echo "Session limit warning: >90% (approaching max 8 concurrent on GTX 1060)"

    # Count active streams
    echo -e "\n${BLUE}Active streaming targets:${NC}"
    streams=$(query_loki '{job="broadcaster"} |= "Starting stream"')
    if [ -n "$streams" ]; then
        echo "$streams" | jq -r '.values[][] | select(. | contains("Starting stream")) | split(" ") | "  - Profile: \(.[4]), Service: \(.[6])"' 2>/dev/null || echo "Could not parse streams"
    fi

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    echo -e "${YELLOW}WARNING:${NC} Approaching NVENC concurrent session limit"
    echo "  1. Review which platforms are essential"
    echo "  2. Stop non-critical streams to free NVENC sessions"
    echo "  3. Consider implementing single-process FFmpeg pipeline (Block 2.4)"
    echo "     - Single FFmpeg can encode once and mux to multiple outputs"
    echo "     - Reduces NVENC session count from N to 1 per profile"
    echo ""
    echo "Current architecture: 1 FFmpeg process = 1 NVENC session per target"
    echo "Target architecture (Block 2.4): 1 FFmpeg process = 1 NVENC session for all targets"
}

# FFmpeg Process Missing Response
handle_ffmpeg_missing() {
    echo -e "${BLUE}=== FFmpeg Process Missing Alert Response ===${NC}"
    echo ""

    # Check FFmpeg process count
    echo "Checking FFmpeg processes in nginx-rtmp-staging container..."
    if docker compose ps nginx-rtmp-staging &>/dev/null; then
        ffmpeg_count=$(docker compose exec -T nginx-rtmp-staging ps aux | grep -c "[f]fmpeg" || echo "0")
        echo "FFmpeg process count: $ffmpeg_count"

        if [ "$ffmpeg_count" -eq 0 ]; then
            echo -e "${RED}✗${NC} No FFmpeg processes found"
        else
            echo -e "${GREEN}✓${NC} FFmpeg processes are running"
            docker compose exec -T nginx-rtmp-staging ps aux | grep "[f]fmpeg"
        fi
    else
        echo -e "${RED}✗${NC} nginx-rtmp-staging container is not running"
    fi

    # Check broadcaster logs for errors
    echo -e "\n${BLUE}Recent broadcaster errors:${NC}"
    query_loki '{job="broadcaster", level="ERROR"}' 10 | jq -r '.values[][] | select(. != null)' || echo "No recent errors"

    # Check PID files
    echo -e "\n${BLUE}Checking PID files:${NC}"
    if docker compose exec -T nginx-rtmp-staging ls -la /var/log/broadcaster/*.pid 2>/dev/null; then
        echo ""
        echo "PID files exist - checking if processes are alive..."
    else
        echo "No PID files found"
    fi

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    echo "  1. Check broadcaster debug log:"
    echo "     docker compose exec nginx-rtmp-staging tail -f /var/log/broadcaster/debug.log"
    echo "  2. Restart stream if needed:"
    echo "     docker compose restart nginx-rtmp-staging"
    echo "  3. Check stream keys are correctly configured in Docker secrets"
}

# Webhook Unhealthy Response
handle_webhook_unhealthy() {
    echo -e "${BLUE}=== Webhook Unhealthy Alert Response ===${NC}"
    echo ""

    # Check webhook health endpoint
    if curl -s http://localhost:8090/health &>/dev/null; then
        echo -e "${GREEN}✓${NC} Webhook health endpoint is responding"
    else
        echo -e "${RED}✗${NC} Webhook health endpoint is not responding"
    fi

    # Check webhook container status
    webhook_status=$(docker inspect webhook-staging 2>/dev/null | jq -r '.[0].State.Status' || echo "not found")
    echo "Webhook container status: $webhook_status"

    # Check webhook logs
    echo -e "\n${BLUE}Recent webhook logs:${NC}"
    docker compose logs --tail=20 webhook-staging

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    echo "  1. Restart webhook service:"
    echo "     docker compose restart webhook-staging"
    echo "  2. Check webhook logs for errors:"
    echo "     docker compose logs -f webhook-staging"
    echo "  3. Verify network connectivity between nginx-rtmp and webhook"
}

# RTMP Stream Dropped Response
handle_rtmp_dropped() {
    echo -e "${BLUE}=== RTMP Stream Dropped Alert Response ===${NC}"
    echo ""

    # Check NGINX RTMP logs
    echo "Checking NGINX RTMP logs..."
    query_loki '{job="nginx"} |= "disconnect"' 20 | jq -r '.values[][]' || echo "No recent disconnects"

    # Check broadcaster logs
    echo -e "\n${BLUE}Checking broadcaster logs:${NC}"
    query_loki '{job="broadcaster"} |= "Stopping stream"' 10 | jq -r '.values[][]' || echo "No recent stream stops"

    # Recommendations
    echo -e "\n${BLUE}Recommendations:${NC}"
    echo "  1. Check client connection (OBS, etc.)"
    echo "  2. Verify RTMP URL and profile name"
    echo "  3. Check network stability"
    echo "  4. Review NGINX RTMP stats:"
    echo "     curl http://localhost:8081/stat"
}

# Main execution
if [ -z "$ALERT_TYPE" ]; then
    usage
fi

case "$ALERT_TYPE" in
    gpu_high)
        handle_gpu_utilization "high"
        ;;
    gpu_critical)
        handle_gpu_utilization "critical"
        ;;
    gpu_temp_high)
        handle_gpu_temperature "high"
        ;;
    gpu_temp_critical)
        handle_gpu_temperature "critical"
        ;;
    nvenc_limit)
        handle_nvenc_limit
        ;;
    ffmpeg_missing)
        handle_ffmpeg_missing
        ;;
    webhook_unhealthy)
        handle_webhook_unhealthy
        ;;
    rtmp_dropped)
        handle_rtmp_dropped
        ;;
    *)
        echo -e "${RED}Error:${NC} Unknown alert type: $ALERT_TYPE"
        usage
        ;;
esac
