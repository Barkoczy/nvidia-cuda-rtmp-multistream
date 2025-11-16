# Observability Stack Operational Scripts

This directory contains operational scripts for managing the observability stack (Prometheus, Grafana, Loki, etc.).

## Scripts Overview

### Daily Operations

#### `health_check_daily.sh`
Performs daily health checks of the observability stack.

```bash
./health_check_daily.sh
```

Checks:
- Service endpoint availability
- Prometheus targets status
- Active alerts
- GPU metrics (DCGM)
- Grafana datasources
- Loki log ingestion

**Usage in cron:**
```cron
0 9 * * * /path/to/scripts/observability/health_check_daily.sh | mail -s "Daily Observability Check" admin@example.com
```

### Weekly Operations

#### `health_check_weekly.sh`
Performs detailed weekly analysis of the observability stack.

```bash
./health_check_weekly.sh
```

Checks:
- Docker volume disk usage
- Container memory usage
- Alert frequency (alert fatigue detection)
- Prometheus TSDB health
- Loki retention configuration
- Container restart history
- Component versions

**Usage in cron:**
```cron
0 10 * * 1 /path/to/scripts/observability/health_check_weekly.sh > /var/log/observability_weekly_$(date +\%Y\%m\%d).log
```

### Alert Response

#### `alert_response.sh`
Automated response procedures for common alerts.

```bash
# GPU utilization alerts
./alert_response.sh gpu_high
./alert_response.sh gpu_critical

# GPU temperature alerts
./alert_response.sh gpu_temp_high
./alert_response.sh gpu_temp_critical

# Other alerts
./alert_response.sh nvenc_limit
./alert_response.sh ffmpeg_missing
./alert_response.sh webhook_unhealthy
./alert_response.sh rtmp_dropped
```

Each alert type provides:
- Current metrics analysis
- Log inspection
- Diagnostic commands
- Remediation recommendations

### Query Library

#### `query_library.sh`
Pre-built PromQL and LogQL queries for common monitoring tasks.

```bash
# GPU metrics
./query_library.sh gpu_util
./query_library.sh gpu_mem_percent
./query_library.sh gpu_temp
./query_library.sh nvenc_util

# System metrics
./query_library.sh cpu_usage
./query_library.sh mem_usage_percent
./query_library.sh network_rx

# Container metrics
./query_library.sh container_count
./query_library.sh ffmpeg_count

# Logs (Loki)
./query_library.sh broadcaster_errors
./query_library.sh webhook_logs
./query_library.sh stream_starts

# With time range
./query_library.sh gpu_util 1h
./query_library.sh broadcaster_errors 24h
```

### Backup and Recovery

#### `backup.sh`
Automated backup of Grafana dashboards and Prometheus data.

```bash
# Backup everything
./backup.sh all

# Backup specific components
./backup.sh grafana
./backup.sh prometheus
./backup.sh loki

# List backups
./backup.sh list
```

Features:
- Grafana dashboards, datasources, and configuration
- Prometheus TSDB snapshots (or volume backup if API unavailable)
- Loki data and configuration
- Automatic cleanup (7-day retention)

**Backup location:** `./backups/observability/`

**Usage in cron:**
```cron
0 2 * * * /path/to/scripts/observability/backup.sh all
```

**Restore procedures:**

Grafana:
```bash
docker run --rm -v grafana-data:/data -v $(pwd)/backups/observability:/backup \
  alpine tar xzf /backup/grafana_data_TIMESTAMP.tar.gz -C /
docker compose restart grafana
```

Prometheus:
```bash
docker run --rm -v prometheus-data:/data -v $(pwd)/backups/observability:/backup \
  alpine tar xzf /backup/prometheus_data_TIMESTAMP.tar.gz -C /
docker compose restart prometheus
```

### Upgrade Management

#### `upgrade.sh`
Helper script for upgrading observability stack components.

```bash
# Check for available updates
./upgrade.sh check

# Perform rolling upgrade
./upgrade.sh upgrade

# Verify health after upgrade
./upgrade.sh verify

# Emergency rollback (requires recent backup)
./upgrade.sh rollback
```

Upgrade process:
1. Pre-upgrade checks (disk space, backups)
2. Automatic backup
3. Pull new images
4. Rolling restart (exporters → Loki → Prometheus → Grafana)
5. Health verification

## Environment Variables

All scripts support the following environment variables:

```bash
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3000
LOKI_URL=http://localhost:3100
DCGM_URL=http://localhost:9400
BACKUP_DIR=./backups/observability
```

## Integration with Monitoring

### Prometheus Alertmanager Integration

You can trigger `alert_response.sh` automatically from Alertmanager using webhook receiver:

**alertmanager.yml:**
```yaml
receivers:
  - name: 'alert-scripts'
    webhook_configs:
      - url: 'http://localhost:9999/alert'
        send_resolved: false
```

**Webhook handler example:**
```bash
#!/bin/bash
# Simple webhook receiver that executes alert_response.sh

while true; do
  nc -l -p 9999 -c 'read request; alertname=$(echo "$request" | jq -r ".alerts[0].labels.alertname"); /path/to/alert_response.sh "$alertname"'
done
```

### Grafana Annotation Integration

Create annotations in Grafana when running operational tasks:

```bash
# After backup
curl -X POST http://localhost:3000/api/annotations \
  -H "Content-Type: application/json" \
  -d '{"text":"Observability stack backup completed","tags":["backup","automation"]}'

# After upgrade
curl -X POST http://localhost:3000/api/annotations \
  -H "Content-Type: application/json" \
  -d '{"text":"Observability stack upgraded","tags":["upgrade","maintenance"]}'
```

## Monitoring the Monitors

### Health Check for Scripts

Add this to your monitoring:

```bash
# Check if daily health check ran today
if [ ! -f /tmp/health_check_daily_$(date +%Y%m%d) ]; then
  echo "WARNING: Daily health check did not run today"
fi
```

### Backup Verification

```bash
# Verify backups are current
latest_backup=$(find ./backups/observability -name "*.tar.gz" -mtime -1 | wc -l)
if [ "$latest_backup" -eq 0 ]; then
  echo "WARNING: No backups created in last 24 hours"
fi
```

## Troubleshooting

### Permission Issues

If scripts fail due to Docker permissions:
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### Missing Dependencies

All scripts require:
- `curl`
- `jq`
- Docker and Docker Compose
- `bc` (for calculations)

Install on Ubuntu:
```bash
sudo apt-get install curl jq bc
```

### Network Connectivity

If scripts can't reach services, verify ports:
```bash
netstat -tlnp | grep -E '3000|9090|3100|9400'
```

## Best Practices

1. **Run health checks regularly** - Schedule daily and weekly checks via cron
2. **Backup before upgrades** - Always create backups before major changes
3. **Test in staging first** - Validate scripts in staging environment
4. **Monitor script execution** - Log script output for debugging
5. **Document customizations** - Track any modifications to scripts
6. **Review alert thresholds** - Tune based on your environment
7. **Keep backups offsite** - Copy backups to remote storage

## Related Documentation

- Main observability documentation: `../../docs/OBSERVABILITY.md`
- Alert rules: `../../observability/alerts/`
- Dashboards: `../../observability/grafana/provisioning/dashboards/`
- Prometheus config: `../../observability/prometheus.yml`
