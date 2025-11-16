#!/bin/bash
# Upgrade helper for observability stack components
# Usage: ./upgrade.sh [check|upgrade|rollback]

set -euo pipefail

ACTION="${1:-check}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Current versions (from docker-compose.staging.yml)
CURRENT_PROMETHEUS="v2.48.0"
CURRENT_GRAFANA="10.2.2"
CURRENT_LOKI="2.9.3"
CURRENT_PROMTAIL="2.9.3"
CURRENT_NODE_EXPORTER="v1.7.0"
CURRENT_CADVISOR="v0.47.2"
CURRENT_DCGM_EXPORTER="3.3.5-3.4.0-ubuntu22.04"

check_latest_versions() {
    echo -e "${BLUE}=== Checking for Latest Versions ===${NC}"
    echo ""

    echo "Current versions:"
    echo "  Prometheus:    $CURRENT_PROMETHEUS"
    echo "  Grafana:       $CURRENT_GRAFANA"
    echo "  Loki:          $CURRENT_LOKI"
    echo "  Promtail:      $CURRENT_PROMTAIL"
    echo "  Node Exporter: $CURRENT_NODE_EXPORTER"
    echo "  cAdvisor:      $CURRENT_CADVISOR"
    echo "  DCGM Exporter: $CURRENT_DCGM_EXPORTER"
    echo ""

    echo -e "${YELLOW}Check for updates:${NC}"
    echo "  Prometheus:    https://github.com/prometheus/prometheus/releases"
    echo "  Grafana:       https://github.com/grafana/grafana/releases"
    echo "  Loki/Promtail: https://github.com/grafana/loki/releases"
    echo "  Node Exporter: https://github.com/prometheus/node_exporter/releases"
    echo "  cAdvisor:      https://github.com/google/cadvisor/releases"
    echo "  DCGM Exporter: https://catalog.ngc.nvidia.com/orgs/nvidia/teams/k8s/containers/dcgm-exporter"
    echo ""

    echo -e "${BLUE}To upgrade, update versions in docker-compose.staging.yml and run:${NC}"
    echo "  $0 upgrade"
}

pre_upgrade_checks() {
    echo -e "${BLUE}=== Pre-Upgrade Checks ===${NC}"

    # Check if services are running
    echo "Checking service status..."
    for service in prometheus-staging grafana-staging loki-staging promtail-staging \
                   node-exporter-staging cadvisor-staging dcgm-exporter-staging; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            echo -e "  ${GREEN}✓${NC} $service is running"
        else
            echo -e "  ${YELLOW}⚠${NC} $service is not running"
        fi
    done

    # Check disk space
    echo ""
    echo "Checking disk space..."
    available_space=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_space" -lt 10 ]; then
        echo -e "  ${RED}✗${NC} Low disk space: ${available_space}GB available (recommend >10GB)"
        return 1
    else
        echo -e "  ${GREEN}✓${NC} Sufficient disk space: ${available_space}GB available"
    fi

    # Check if backup exists
    echo ""
    echo "Checking for recent backups..."
    if [ -d "./backups/observability" ] && [ -n "$(find ./backups/observability -name '*.tar.gz' -mtime -7 2>/dev/null)" ]; then
        echo -e "  ${GREEN}✓${NC} Recent backup found (within 7 days)"
    else
        echo -e "  ${YELLOW}⚠${NC} No recent backup found"
        echo "  Run './scripts/observability/backup.sh all' before upgrading"
    fi
}

perform_upgrade() {
    echo -e "${BLUE}=== Performing Upgrade ===${NC}"
    echo ""

    # Pre-flight checks
    pre_upgrade_checks || {
        echo -e "${RED}Pre-upgrade checks failed. Aborting.${NC}"
        exit 1
    }

    echo ""
    echo -e "${YELLOW}This will:${NC}"
    echo "  1. Create a backup (if not done recently)"
    echo "  2. Pull new images from docker-compose.staging.yml"
    echo "  3. Perform rolling restart of services"
    echo "  4. Verify all services are healthy"
    echo ""
    read -p "Continue with upgrade? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Upgrade cancelled"
        exit 0
    fi

    # Step 1: Backup
    echo ""
    echo -e "${BLUE}Step 1: Creating backup${NC}"
    if [ -x "./scripts/observability/backup.sh" ]; then
        ./scripts/observability/backup.sh all
    else
        echo -e "${YELLOW}⚠${NC} Backup script not found, skipping backup"
    fi

    # Step 2: Pull new images
    echo ""
    echo -e "${BLUE}Step 2: Pulling new images${NC}"
    docker compose -f docker-compose.staging.yml pull prometheus grafana loki promtail \
        node-exporter cadvisor dcgm-exporter

    # Step 3: Rolling upgrade
    echo ""
    echo -e "${BLUE}Step 3: Performing rolling upgrade${NC}"

    # Upgrade order: exporters → Loki/Promtail → Prometheus → Grafana
    for service in dcgm-exporter node-exporter cadvisor promtail loki prometheus grafana; do
        echo "Upgrading $service-staging..."
        docker compose -f docker-compose.staging.yml up -d "$service"
        sleep 5
    done

    # Step 4: Verify
    echo ""
    echo -e "${BLUE}Step 4: Verifying upgrade${NC}"
    sleep 10
    verify_upgrade
}

verify_upgrade() {
    echo "Checking service health..."

    all_healthy=true

    # Check Prometheus
    if curl -s http://localhost:9090/-/healthy &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Prometheus is healthy"
    else
        echo -e "  ${RED}✗${NC} Prometheus is unhealthy"
        all_healthy=false
    fi

    # Check Grafana
    if curl -s http://localhost:3000/api/health | jq -e '.database == "ok"' &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Grafana is healthy"
    else
        echo -e "  ${RED}✗${NC} Grafana is unhealthy"
        all_healthy=false
    fi

    # Check Loki
    if curl -s http://localhost:3100/ready &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Loki is healthy"
    else
        echo -e "  ${RED}✗${NC} Loki is unhealthy"
        all_healthy=false
    fi

    # Check Prometheus targets
    echo ""
    echo "Checking Prometheus targets..."
    targets=$(curl -s http://localhost:9090/api/v1/targets)
    up_count=$(echo "$targets" | jq -r '[.data.activeTargets[] | select(.health=="up")] | length' 2>/dev/null || echo "0")
    total_count=$(echo "$targets" | jq -r '.data.activeTargets | length' 2>/dev/null || echo "0")

    if [ "$up_count" = "$total_count" ] && [ "$up_count" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} All $total_count targets are UP"
    else
        echo -e "  ${YELLOW}⚠${NC} Only $up_count/$total_count targets are UP"
        all_healthy=false
    fi

    echo ""
    if [ "$all_healthy" = true ]; then
        echo -e "${GREEN}✓ Upgrade completed successfully!${NC}"
        echo ""
        echo "Post-upgrade steps:"
        echo "  1. Open Grafana at http://localhost:3000"
        echo "  2. Verify all dashboards are working"
        echo "  3. Check Prometheus alerts at http://localhost:9090/alerts"
        echo "  4. Review logs for any errors"
    else
        echo -e "${RED}✗ Upgrade completed with warnings${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check logs: docker compose -f docker-compose.staging.yml logs"
        echo "  2. Restart unhealthy services: docker compose -f docker-compose.staging.yml restart <service>"
        echo "  3. If issues persist, consider rollback: $0 rollback"
    fi
}

perform_rollback() {
    echo -e "${BLUE}=== Performing Rollback ===${NC}"
    echo ""

    # Find most recent backup
    latest_backup=$(find ./backups/observability -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -rn | head -1 | awk '{print $2}')

    if [ -z "$latest_backup" ]; then
        echo -e "${RED}✗${NC} No backup found for rollback"
        exit 1
    fi

    echo "Found backup: $latest_backup"
    echo ""
    echo -e "${YELLOW}Warning: This will restore data from the backup${NC}"
    echo "All data since the backup will be lost."
    echo ""
    read -p "Continue with rollback? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Rollback cancelled"
        exit 0
    fi

    # Stop services
    echo "Stopping observability services..."
    docker compose -f docker-compose.staging.yml stop prometheus grafana loki promtail

    # Restore volumes
    echo "Restoring volumes from backup..."

    # Determine which volume to restore based on backup name
    if echo "$latest_backup" | grep -q "prometheus"; then
        echo "Restoring Prometheus data..."
        docker run --rm \
            -v prometheus-data:/data \
            -v "$(pwd)/backups/observability":/backup \
            alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$latest_backup") -C /"
    elif echo "$latest_backup" | grep -q "grafana"; then
        echo "Restoring Grafana data..."
        docker run --rm \
            -v grafana-data:/data \
            -v "$(pwd)/backups/observability":/backup \
            alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$latest_backup") -C /"
    elif echo "$latest_backup" | grep -q "loki"; then
        echo "Restoring Loki data..."
        docker run --rm \
            -v loki-data:/data \
            -v "$(pwd)/backups/observability":/backup \
            alpine sh -c "rm -rf /data/* && tar xzf /backup/$(basename "$latest_backup") -C /"
    fi

    # Restart services
    echo "Restarting services..."
    docker compose -f docker-compose.staging.yml up -d prometheus grafana loki promtail

    echo ""
    echo -e "${GREEN}Rollback completed${NC}"
    echo "Verify services at:"
    echo "  - Grafana: http://localhost:3000"
    echo "  - Prometheus: http://localhost:9090"
}

# Main execution
case "$ACTION" in
    check)
        check_latest_versions
        ;;
    upgrade)
        perform_upgrade
        ;;
    verify)
        verify_upgrade
        ;;
    rollback)
        perform_rollback
        ;;
    *)
        echo "Usage: $0 [check|upgrade|verify|rollback]"
        echo ""
        echo "  check    - Check current versions and available updates"
        echo "  upgrade  - Perform rolling upgrade of observability stack"
        echo "  verify   - Verify health of all services after upgrade"
        echo "  rollback - Rollback to previous backup (emergency only)"
        exit 1
        ;;
esac
