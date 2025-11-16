# Observability Stack - Quick Reference Card

## Daily Tasks (5 minutes)

```bash
# 1. Health check
./scripts/observability/health_check_daily.sh

# 2. Check GPU
./scripts/observability/query_library.sh gpu_util
./scripts/observability/query_library.sh gpu_temp

# 3. Check for errors
./scripts/observability/query_library.sh broadcaster_errors
```

**Dashboards:** http://localhost:3000
**Alerts:** http://localhost:9090/alerts

---

## Alert Response (when alert fires)

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

---

## Common Queries

```bash
# GPU Metrics
./scripts/observability/query_library.sh gpu_util           # GPU %
./scripts/observability/query_library.sh gpu_mem_percent    # VRAM %
./scripts/observability/query_library.sh gpu_temp           # Temperature
./scripts/observability/query_library.sh nvenc_util         # NVENC %

# System Metrics
./scripts/observability/query_library.sh cpu_usage          # CPU %
./scripts/observability/query_library.sh mem_usage_percent  # RAM %

# Logs
./scripts/observability/query_library.sh broadcaster_errors # Errors
./scripts/observability/query_library.sh stream_starts      # Stream starts
./scripts/observability/query_library.sh webhook_logs       # Webhook logs
```

---

## Backup & Recovery

```bash
# Backup all
./scripts/observability/backup.sh all

# Backup specific
./scripts/observability/backup.sh grafana
./scripts/observability/backup.sh prometheus

# List backups
./scripts/observability/backup.sh list
```

**Location:** `./backups/observability/`
**Retention:** 7 days

---

## Upgrade

```bash
# Check for updates
./scripts/observability/upgrade.sh check

# Upgrade (with automatic backup)
./scripts/observability/upgrade.sh upgrade

# Verify health
./scripts/observability/upgrade.sh verify

# Rollback (emergency)
./scripts/observability/upgrade.sh rollback
```

---

## Emergency Procedures

### Critical GPU Temperature (>85°C)
```bash
# 1. Stop all streams immediately
docker compose exec nginx-rtmp-staging pkill -9 ffmpeg

# 2. Check temperature
./scripts/observability/query_library.sh gpu_temp

# 3. Physical check
# - Clean GPU fans
# - Verify case airflow
```

### All Services Down
```bash
# 1. Check logs
docker compose -f docker-compose.staging.yml logs

# 2. Restart observability stack
docker compose -f docker-compose.staging.yml restart prometheus grafana loki

# 3. Verify health
./scripts/observability/health_check_daily.sh
```

### Prometheus Out of Disk
```bash
# 1. Check volume usage
./scripts/observability/health_check_weekly.sh | grep "Volume Disk"

# 2. Reduce retention (emergency)
# Edit docker-compose.staging.yml:
#   --storage.tsdb.retention.time=15d  # reduce from 30d

# 3. Restart Prometheus
docker compose restart prometheus
```

---

## Service URLs

| Service | URL | Login |
|---------|-----|-------|
| Grafana | http://localhost:3000 | admin/admin |
| Prometheus | http://localhost:9090 | - |
| Loki | http://localhost:3100 | - |
| DCGM Exporter | http://localhost:9400/metrics | - |
| Node Exporter | http://localhost:9100/metrics | - |
| cAdvisor | http://localhost:8082 | - |

---

## Thresholds

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| GPU Utilization | >85% | >95% | Reduce streams |
| GPU Temperature | >80°C | >85°C | Check cooling |
| NVENC Utilization | >90% | - | Reduce encoders |
| Disk Space | <10GB | <5GB | Cleanup/expand |
| Memory Usage | >80% | >90% | Restart services |

---

## Cron Setup (Automation)

```cron
# Daily health check (9 AM)
0 9 * * * /path/to/scripts/observability/health_check_daily.sh

# Weekly analysis (Monday 10 AM)
0 10 * * 1 /path/to/scripts/observability/health_check_weekly.sh

# Automated backups (2 AM daily)
0 2 * * * /path/to/scripts/observability/backup.sh all
```

---

## Troubleshooting Quick Checks

```bash
# Services running?
docker compose ps | grep staging

# Prometheus targets up?
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up")'

# Grafana healthy?
curl http://localhost:3000/api/health

# Loki receiving logs?
curl http://localhost:3100/ready

# GPU accessible?
docker compose exec dcgm-exporter-staging nvidia-smi
```

---

**Full Documentation:** `scripts/observability/README.md` and `docs/OPERATIONS.md`
