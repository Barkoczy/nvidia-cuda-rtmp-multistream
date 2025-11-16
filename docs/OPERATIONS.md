# Operational Guide - Observability Stack

This guide covers daily operations, maintenance, and troubleshooting procedures for the observability stack (Prometheus, Grafana, Loki, Promtail, DCGM Exporter, Node Exporter, cAdvisor).

## Quick Start

All operational scripts are located in `scripts/observability/`. See full documentation in `scripts/observability/README.md`.

## Daily Operations

### Health Check
```bash
./scripts/observability/health_check_daily.sh
```

**Checks:**
- Service availability (Prometheus, Grafana, Loki, DCGM)
- Prometheus target status
- Active alerts
- GPU metrics (utilization, temperature)
- Loki log ingestion

**Expected runtime:** ~30 seconds

### Quick Metrics Check
```bash
# GPU utilization
./scripts/observability/query_library.sh gpu_util

# GPU temperature
./scripts/observability/query_library.sh gpu_temp

# Check for errors
./scripts/observability/query_library.sh broadcaster_errors
```

## Weekly Operations

### Detailed Health Analysis
```bash
./scripts/observability/health_check_weekly.sh
```

**Analyzes:**
- Disk usage (volumes)
- Memory consumption
- Alert frequency (alert fatigue detection)
- Container restart history
- Component versions

**Expected runtime:** ~1-2 minutes

### Review Checklist
- [ ] Open Grafana dashboard "NVIDIA GPU Metrics"
- [ ] Open Grafana dashboard "System Overview"
- [ ] Check Prometheus alerts: http://localhost:9090/alerts
- [ ] Verify backup exists (last 7 days)
- [ ] Review disk usage vs expected (~8GB/month)
- [ ] Check for component updates

## Alert Response Procedures

When an alert fires, use the automated response script:

```bash
# GPU alerts
./scripts/observability/alert_response.sh gpu_high
./scripts/observability/alert_response.sh gpu_critical
./scripts/observability/alert_response.sh gpu_temp_high
./scripts/observability/alert_response.sh gpu_temp_critical

# Stream alerts
./scripts/observability/alert_response.sh nvenc_limit
./scripts/observability/alert_response.sh ffmpeg_missing

# Service alerts
./scripts/observability/alert_response.sh webhook_unhealthy
./scripts/observability/alert_response.sh rtmp_dropped
```

Each script provides:
1. Current metric values
2. Related log analysis
3. Diagnostic commands
4. Remediation steps

## Common Scenarios

### Scenario 1: High GPU Utilization (>85%)

**Automated response:**
```bash
./scripts/observability/alert_response.sh gpu_high
```

**Manual steps if persistent:**
1. Check stream count: `./scripts/observability/query_library.sh stream_starts`
2. Review profiles: `cat profiles.yml`
3. Reduce bitrate or stop non-critical streams
4. Consider implementing single-process FFmpeg (Block 2.4)

### Scenario 2: GPU Temperature High (>80°C)

**Automated response:**
```bash
./scripts/observability/alert_response.sh gpu_temp_high
```

**Manual intervention:**
1. Physical check: Clean dust from GPU fans
2. Verify case airflow
3. Reduce encoding load temporarily
4. If critical (>85°C): Stop all streams immediately

### Scenario 3: NVENC Session Limit (>90%)

**Context:** GTX 1060 supports max 8 concurrent NVENC sessions.

**Automated response:**
```bash
./scripts/observability/alert_response.sh nvenc_limit
```

**Solutions:**
- **Short-term:** Stop non-essential streams
- **Long-term:** Implement single-process FFmpeg pipeline (Block 2.4)
  - Reduces NVENC sessions from N (one per target) to 1 (shared encode)

### Scenario 4: FFmpeg Process Missing

**Automated response:**
```bash
./scripts/observability/alert_response.sh ffmpeg_missing
```

**Common causes:**
1. Stream key incorrect/expired
2. Broadcaster script error
3. Network connectivity issue
4. NGINX RTMP disconnect

**Check:**
```bash
docker compose exec nginx-rtmp-staging tail -f /var/log/broadcaster/debug.log
./scripts/observability/query_library.sh broadcaster_errors
```

## Backup and Recovery

### Create Backup
```bash
# Full backup
./scripts/observability/backup.sh all

# Selective backup
./scripts/observability/backup.sh grafana
./scripts/observability/backup.sh prometheus
./scripts/observability/backup.sh loki
```

**Backup location:** `./backups/observability/`
**Retention:** 7 days (automatic cleanup)

### Restore from Backup

**Grafana:**
```bash
docker compose -f docker-compose.staging.yml stop grafana
docker run --rm -v grafana-data:/data -v $(pwd)/backups/observability:/backup \
  alpine tar xzf /backup/grafana_data_TIMESTAMP.tar.gz -C /
docker compose -f docker-compose.staging.yml start grafana
```

**Prometheus:**
```bash
docker compose -f docker-compose.staging.yml stop prometheus
docker run --rm -v prometheus-data:/data -v $(pwd)/backups/observability:/backup \
  alpine tar xzf /backup/prometheus_data_TIMESTAMP.tar.gz -C /
docker compose -f docker-compose.staging.yml start prometheus
```

## Upgrading Components

### Check for Updates
```bash
./scripts/observability/upgrade.sh check
```

### Perform Upgrade
```bash
./scripts/observability/upgrade.sh upgrade
```

**Process:**
1. Pre-upgrade checks (disk space, backups)
2. Automatic backup creation
3. Pull new Docker images
4. Rolling restart (exporters → Loki → Prometheus → Grafana)
5. Health verification

**Downtime:** Minimal (~2-5 minutes per service)

### Rollback
```bash
./scripts/observability/upgrade.sh rollback
```

Emergency use only. Requires recent backup.

## Automation with Cron

### Daily Health Check
```cron
# Run daily health check at 9 AM
0 9 * * * /path/to/scripts/observability/health_check_daily.sh | mail -s "Daily Observability Check" admin@example.com
```

### Weekly Analysis
```cron
# Run weekly analysis every Monday at 10 AM
0 10 * * 1 /path/to/scripts/observability/health_check_weekly.sh > /var/log/observability_weekly_$(date +\%Y\%m\%d).log
```

### Automated Backups
```cron
# Backup every night at 2 AM
0 2 * * * /path/to/scripts/observability/backup.sh all
```

## Resource Monitoring

### Expected Resource Usage

**Memory:**
- Total stack: ~695 MB
- Prometheus: ~250 MB
- Grafana: ~200 MB
- Loki: ~150 MB
- Others: ~95 MB

**Disk:**
- Prometheus: ~8 GB/month (30-day retention)
- Loki: ~2-4 GB/month (7-day retention)
- Grafana: <100 MB

**Verify current usage:**
```bash
./scripts/observability/health_check_weekly.sh | grep -A 10 "Memory Usage"
./scripts/observability/health_check_weekly.sh | grep -A 10 "Volume Disk Usage"
```

## Integration with Phase 2 Blocks

### Block 2.2: NGINX RTMP Metrics
When implemented, add to daily checks:
```bash
./scripts/observability/query_library.sh rtmp_active_streams
./scripts/observability/query_library.sh rtmp_bandwidth
```

### Block 2.3: FFmpeg Metrics
When implemented, add to alert responses:
```bash
./scripts/observability/query_library.sh ffmpeg_fps
./scripts/observability/query_library.sh ffmpeg_dropped_frames
```

### Block 2.4: Single-Process FFmpeg
After implementation:
1. Update baseline measurements
2. Compare NVENC session count (should drop from N to 1 per profile)
3. Update GPU utilization thresholds

## Troubleshooting

### Services Not Starting
```bash
# Check logs
docker compose -f docker-compose.staging.yml logs prometheus
docker compose -f docker-compose.staging.yml logs grafana

# Verify volumes exist
docker volume ls | grep -E "prometheus|grafana|loki"

# Check disk space
df -h
```

### Prometheus Targets Down
```bash
# Check target status
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up")'

# Restart affected services
docker compose -f docker-compose.staging.yml restart dcgm-exporter
docker compose -f docker-compose.staging.yml restart node-exporter
```

### Grafana Dashboards Empty
```bash
# Verify datasources
curl http://localhost:3000/api/datasources

# Check Prometheus is reachable from Grafana
docker compose -f docker-compose.staging.yml exec grafana wget -O- http://prometheus:9090/-/healthy

# Restart Grafana
docker compose -f docker-compose.staging.yml restart grafana
```

### Loki Not Receiving Logs
```bash
# Check Promtail status
docker compose -f docker-compose.staging.yml logs promtail

# Verify Promtail can reach Loki
docker compose -f docker-compose.staging.yml exec promtail wget -O- http://loki:3100/ready

# Restart Promtail
docker compose -f docker-compose.staging.yml restart promtail
```

## Best Practices

1. **Monitor the monitors** - Ensure health check scripts run successfully
2. **Backup before upgrades** - Always create backup before major changes
3. **Test in staging** - Validate all changes in staging environment first
4. **Document incidents** - Log all alerts and responses for pattern analysis
5. **Review alert thresholds** - Tune based on actual workload
6. **Keep backups offsite** - Copy critical backups to remote storage
7. **Rotate credentials** - Change Grafana admin password from default

## Additional Resources

- **Full script documentation:** `scripts/observability/README.md`
- **Observability architecture:** `docs/OBSERVABILITY.md`
- **Alert rules:** `observability/alerts/`
- **Dashboard definitions:** `observability/grafana/provisioning/dashboards/`
- **Prometheus config:** `observability/prometheus.yml`
