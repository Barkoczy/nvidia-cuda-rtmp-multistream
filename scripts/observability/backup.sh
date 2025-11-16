#!/bin/bash
# Backup automation for Grafana dashboards and Prometheus data
# Usage: ./backup.sh [grafana|prometheus|all]

set -euo pipefail

BACKUP_TYPE="${1:-all}"
BACKUP_DIR="${BACKUP_DIR:-./backups/observability}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create backup directory
mkdir -p "$BACKUP_DIR"

backup_grafana() {
    echo -e "${BLUE}=== Backing up Grafana ===${NC}"

    local grafana_backup_dir="$BACKUP_DIR/grafana_$TIMESTAMP"
    mkdir -p "$grafana_backup_dir"

    # Export Grafana configuration
    echo "Exporting Grafana configuration..."
    if docker exec grafana-staging grafana-cli admin data-migration export --path /tmp/grafana_backup 2>/dev/null; then
        docker cp grafana-staging:/tmp/grafana_backup "$grafana_backup_dir/" 2>/dev/null || true
    fi

    # Backup Grafana volume
    echo "Backing up Grafana volume..."
    docker run --rm \
        -v grafana-data:/data:ro \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/grafana_data_${TIMESTAMP}.tar.gz" /data

    # Backup dashboard JSON files
    echo "Backing up dashboard provisioning files..."
    if [ -d "./observability/grafana/provisioning/dashboards" ]; then
        cp -r ./observability/grafana/provisioning/dashboards "$grafana_backup_dir/"
    fi

    # Backup datasource configs
    echo "Backing up datasource configs..."
    if [ -d "./observability/grafana/provisioning/datasources" ]; then
        cp -r ./observability/grafana/provisioning/datasources "$grafana_backup_dir/"
    fi

    echo -e "${GREEN}✓${NC} Grafana backup completed: $grafana_backup_dir"
    echo "   Volume backup: $BACKUP_DIR/grafana_data_${TIMESTAMP}.tar.gz"
}

backup_prometheus() {
    echo -e "${BLUE}=== Backing up Prometheus ===${NC}"

    # Trigger snapshot via API (requires --web.enable-admin-api)
    echo "Creating Prometheus snapshot..."
    snapshot_name=$(curl -s -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot | jq -r '.data.name' 2>/dev/null)

    if [ -n "$snapshot_name" ] && [ "$snapshot_name" != "null" ]; then
        echo "Snapshot created: $snapshot_name"

        # Copy snapshot from container
        docker cp "prometheus-staging:/prometheus/snapshots/$snapshot_name" "$BACKUP_DIR/prometheus_snapshot_${TIMESTAMP}"
        echo -e "${GREEN}✓${NC} Prometheus snapshot backup: $BACKUP_DIR/prometheus_snapshot_${TIMESTAMP}"
    else
        echo -e "${YELLOW}⚠${NC} Prometheus snapshot API failed, falling back to volume backup..."

        # Fallback: Backup entire Prometheus volume
        docker run --rm \
            -v prometheus-data:/data:ro \
            -v "$(pwd)/$BACKUP_DIR":/backup \
            alpine tar czf "/backup/prometheus_data_${TIMESTAMP}.tar.gz" /data

        echo -e "${GREEN}✓${NC} Prometheus volume backup: $BACKUP_DIR/prometheus_data_${TIMESTAMP}.tar.gz"
    fi

    # Backup Prometheus config
    echo "Backing up Prometheus configuration..."
    local prom_config_dir="$BACKUP_DIR/prometheus_config_$TIMESTAMP"
    mkdir -p "$prom_config_dir"

    if [ -f "./observability/prometheus.yml" ]; then
        cp ./observability/prometheus.yml "$prom_config_dir/"
    fi

    if [ -d "./observability/alerts" ]; then
        cp -r ./observability/alerts "$prom_config_dir/"
    fi

    echo -e "${GREEN}✓${NC} Prometheus config backup: $prom_config_dir"
}

backup_loki() {
    echo -e "${BLUE}=== Backing up Loki ===${NC}"

    # Backup Loki volume
    echo "Backing up Loki volume..."
    docker run --rm \
        -v loki-data:/data:ro \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine tar czf "/backup/loki_data_${TIMESTAMP}.tar.gz" /data

    # Backup Loki config
    local loki_config_dir="$BACKUP_DIR/loki_config_$TIMESTAMP"
    mkdir -p "$loki_config_dir"

    if [ -f "./observability/loki-config.yml" ]; then
        cp ./observability/loki-config.yml "$loki_config_dir/"
    fi

    if [ -f "./observability/promtail-config.yml" ]; then
        cp ./observability/promtail-config.yml "$loki_config_dir/"
    fi

    echo -e "${GREEN}✓${NC} Loki backup completed"
    echo "   Volume backup: $BACKUP_DIR/loki_data_${TIMESTAMP}.tar.gz"
    echo "   Config backup: $loki_config_dir"
}

cleanup_old_backups() {
    echo -e "\n${BLUE}=== Cleaning up old backups ===${NC}"

    # Keep only last 7 backups
    RETENTION_DAYS=7

    echo "Removing backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -type d -mtime +$RETENTION_DAYS -empty -delete 2>/dev/null || true

    echo -e "${GREEN}✓${NC} Cleanup completed"
}

list_backups() {
    echo -e "\n${BLUE}=== Available Backups ===${NC}"
    ls -lh "$BACKUP_DIR" | grep -E "grafana|prometheus|loki" || echo "No backups found"
}

# Main execution
case "$BACKUP_TYPE" in
    grafana)
        backup_grafana
        ;;
    prometheus)
        backup_prometheus
        ;;
    loki)
        backup_loki
        ;;
    all)
        backup_grafana
        backup_prometheus
        backup_loki
        cleanup_old_backups
        ;;
    list)
        list_backups
        exit 0
        ;;
    *)
        echo "Usage: $0 [grafana|prometheus|loki|all|list]"
        exit 1
        ;;
esac

cleanup_old_backups
list_backups

echo ""
echo -e "${GREEN}Backup completed successfully!${NC}"
echo "Backup location: $BACKUP_DIR"
echo ""
echo "To restore:"
echo "  Grafana volume:    docker run --rm -v grafana-data:/data -v \$(pwd)/$BACKUP_DIR:/backup alpine tar xzf /backup/grafana_data_${TIMESTAMP}.tar.gz -C /"
echo "  Prometheus volume: docker run --rm -v prometheus-data:/data -v \$(pwd)/$BACKUP_DIR:/backup alpine tar xzf /backup/prometheus_data_${TIMESTAMP}.tar.gz -C /"
echo "  Loki volume:       docker run --rm -v loki-data:/data -v \$(pwd)/$BACKUP_DIR:/backup alpine tar xzf /backup/loki_data_${TIMESTAMP}.tar.gz -C /"
