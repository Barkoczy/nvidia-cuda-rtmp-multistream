# Observability Stack Documentation

This document describes the monitoring, logging, and metrics infrastructure for the RTMP multistreaming server.

## Stack Overview

**Components**:
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization and dashboards
- **Loki** - Log aggregation
- **Promtail** - Log collection agent
- **Node Exporter** - Host metrics
- **cAdvisor** - Container metrics
- **DCGM Exporter** - NVIDIA GPU metrics

**Architecture**:
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Webhook   │────▶│  Prometheus  │────▶│   Grafana   │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                     │
       │                    │                     │
┌─────────────┐     ┌──────────────┐             │
│ NGINX RTMP  │────▶│ Node Exporter│             │
└─────────────┘     └──────────────┘             │
       │                    │                     │
       │                    │                     │
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   FFmpeg    │     │   cAdvisor   │     │     Loki    │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                     │
       │                    │                     │
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ NVIDIA GPU  │────▶│ DCGM Exporter│     │  Promtail   │
└─────────────┘     └──────────────┘     └─────────────┘
```

## Accessing Services

### Grafana
- **URL**: http://localhost:3000
- **Default credentials**: admin / admin
- **Dashboards**:
  - NVIDIA GPU Metrics
  - System Overview
  - Stream Health (to be created)

### Prometheus
- **URL**: http://localhost:9090
- **Targets**: http://localhost:9090/targets
- **Alerts**: http://localhost:9090/alerts

### Loki
- **URL**: http://localhost:3100
- **Query endpoint**: http://localhost:3100/loki/api/v1/query

### Exporters
- **Node Exporter**: http://localhost:9100/metrics
- **cAdvisor**: http://localhost:8082
- **DCGM Exporter**: http://localhost:9400/metrics

## Metrics Collected

### GPU Metrics (DCGM Exporter)

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `DCGM_FI_DEV_GPU_UTIL` | GPU utilization % | >85% (warning), >95% (critical) |
| `DCGM_FI_DEV_FB_USED` | GPU memory used (bytes) | >80% (warning) |
| `DCGM_FI_DEV_FB_FREE` | GPU memory free (bytes) | - |
| `DCGM_FI_DEV_GPU_TEMP` | GPU temperature (°C) | >80°C (warning), >85°C (critical) |
| `DCGM_FI_DEV_ENC_UTIL` | NVENC encoder utilization | >90% (warning) |
| `DCGM_FI_DEV_DEC_UTIL` | NVDEC decoder utilization | - |
| `DCGM_FI_DEV_POWER_USAGE` | Power consumption (W) | - |

**Example Queries**:
```promql
# GPU utilization
DCGM_FI_DEV_GPU_UTIL

# GPU memory usage percentage
(DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_TOTAL) * 100

# Average GPU temperature
avg(DCGM_FI_DEV_GPU_TEMP)
```

### Host Metrics (Node Exporter)

| Metric | Description |
|--------|-------------|
| `node_cpu_seconds_total` | CPU usage by mode |
| `node_memory_MemTotal_bytes` | Total memory |
| `node_memory_MemAvailable_bytes` | Available memory |
| `node_disk_io_time_seconds_total` | Disk I/O time |
| `node_network_receive_bytes_total` | Network RX bytes |
| `node_network_transmit_bytes_total` | Network TX bytes |
| `node_load1`, `node_load5`, `node_load15` | System load averages |

**Example Queries**:
```promql
# CPU usage percentage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100

# Disk space usage
(node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes * 100
```

### Container Metrics (cAdvisor)

| Metric | Description |
|--------|-------------|
| `container_cpu_usage_seconds_total` | Container CPU usage |
| `container_memory_usage_bytes` | Container memory usage |
| `container_network_receive_bytes_total` | Container RX bytes |
| `container_network_transmit_bytes_total` | Container TX bytes |
| `container_processes` | Number of processes in container |

**Example Queries**:
```promql
# FFmpeg process count
count(container_processes{name=~".*ffmpeg.*"})

# Container memory usage
container_memory_usage_bytes{name="nginx-rtmp-staging"}

# Container CPU usage
rate(container_cpu_usage_seconds_total{name="nginx-rtmp-staging"}[5m])
```

## Alerts

### GPU Alerts

**High GPU Utilization** (Warning)
- **Condition**: GPU >85% for 5 minutes
- **Action**: Review stream count and quality settings

**Critical GPU Utilization** (Critical)
- **Condition**: GPU >95% for 2 minutes
- **Action**: Reduce stream count or quality immediately

**High GPU Temperature** (Warning)
- **Condition**: Temperature >80°C for 3 minutes
- **Action**: Check cooling, reduce load

**Critical GPU Temperature** (Critical)
- **Condition**: Temperature >85°C for 1 minute
- **Action**: Emergency shutdown or reduce load

**NVENC Session Limit** (Warning)
- **Condition**: NVENC utilization >90% for 2 minutes
- **Action**: GTX 1060 has 8-session limit, reduce concurrent encoders

### Stream Alerts

**FFmpeg Process Missing** (Critical)
- **Condition**: RTMP connection active but no FFmpeg processes
- **Action**: Check broadcaster logs, restart stream

**RTMP Connection Dropped** (Warning)
- **Condition**: Connections being dropped
- **Action**: Check network, NGINX buffers

**Webhook Unhealthy** (Critical)
- **Condition**: Webhook service down for 1 minute
- **Action**: Restart webhook container, check logs

## Log Aggregation

### Log Sources

1. **Docker Container Logs** (via Promtail)
   - All container stdout/stderr
   - Labeled by: container, service, compose_project

2. **Broadcaster Logs** (via mounted volume)
   - Profile-specific logs
   - Labeled by: profile, level

3. **NGINX Access Logs**
   - RTMP/HTTP access logs
   - Labeled by: status code

### Log Queries (Loki)

```logql
# All logs from nginx-rtmp container
{container="nginx-rtmp-staging"}

# Broadcaster errors
{job="broadcaster", level="ERROR"}

# Logs for specific profile
{job="broadcaster", profile="gaming"}

# FFmpeg process starts
{container="nginx-rtmp-staging"} |= "Starting stream"

# RTMP connection logs
{job="nginx"} |= "RTMP"

# Last 1 hour of webhook logs
{container="webhook-staging"} [1h]
```

### Log Retention

- **Loki retention**: 7 days (168 hours)
- **Promtail positions**: /tmp/positions.yaml
- **Loki storage**: /loki volume (Docker volume)

## Grafana Dashboards

### 1. NVIDIA GPU Metrics

**Panels**:
- GPU Utilization (line graph)
- GPU Memory Usage (line graph)
- GPU Temperature (line graph with alert)
- NVENC/NVDEC Utilization (line graph)

**Refresh**: 10 seconds

### 2. System Overview

**Panels**:
- CPU Usage (line graph)
- Memory Usage (line graph)
- Container Count (stat)
- FFmpeg Processes (stat)
- Network Traffic (line graph)

**Refresh**: 30 seconds

### 3. Stream Health (Future)

**Panels**:
- Active Streams by Profile
- Stream Bitrate by Service
- FFmpeg Process Tree
- Stream Latency
- Drop/Error Rate

## Performance Impact

| Component | Memory | CPU | Disk | Network |
|-----------|--------|-----|------|---------|
| Prometheus | ~200MB | Low | 5GB/month | Low |
| Grafana | ~100MB | Low | Minimal | Low |
| Loki | ~150MB | Low | 3GB/week | Low |
| Promtail | ~50MB | Low | Minimal | Low |
| Node Exporter | ~15MB | Negligible | None | Negligible |
| cAdvisor | ~80MB | Low | None | Low |
| DCGM Exporter | ~100MB | Negligible | None | Negligible |
| **Total** | **~695MB** | **Low** | **~8GB/month** | **Low** |

## Troubleshooting

### Prometheus

**Issue**: Targets down

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# Check specific service
docker compose logs prometheus-staging
docker compose logs dcgm-exporter-staging
```

**Issue**: High memory usage

```bash
# Reduce retention time in docker-compose.yml
--storage.tsdb.retention.time=15d  # Instead of 30d

# Or increase storage disk space
docker volume inspect prometheus-data
```

### Grafana

**Issue**: Data source not working

```bash
# Check Grafana logs
docker compose logs grafana-staging

# Test Prometheus connectivity
docker compose exec grafana-staging wget -qO- http://prometheus:9090/api/v1/status/config
```

**Issue**: Dashboards not loading

```bash
# Check provisioning directory
docker compose exec grafana-staging ls -la /etc/grafana/provisioning/dashboards/json/

# Restart Grafana
docker compose restart grafana-staging
```

### Loki/Promtail

**Issue**: Logs not appearing

```bash
# Check Promtail is running
docker compose ps promtail-staging

# Check Promtail targets
curl http://localhost:9080/targets

# Check Loki ingestion
curl http://localhost:3100/loki/api/v1/label
```

**Issue**: Disk space filling up

```bash
# Check Loki volume size
docker volume inspect loki-data

# Reduce retention in loki-config.yml
retention_period: 72h  # Instead of 168h

# Compact old data
docker compose restart loki-staging
```

### DCGM Exporter

**Issue**: GPU metrics not available

```bash
# Check DCGM exporter logs
docker compose logs dcgm-exporter-staging

# Verify GPU access
docker compose exec dcgm-exporter-staging nvidia-smi

# Check metrics endpoint
curl http://localhost:9400/metrics | grep DCGM
```

## Best Practices

1. **Regular Backups**
   ```bash
   # Backup Grafana dashboards
   docker compose exec grafana-staging grafana-cli admin export-dashboard

   # Backup Prometheus data
   docker run --rm -v prometheus-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz /data
   ```

2. **Alert Tuning**
   - Start with warning thresholds
   - Adjust based on actual usage patterns
   - Avoid alert fatigue

3. **Dashboard Organization**
   - One dashboard per subsystem
   - Use template variables for dynamic filtering
   - Keep panels focused and simple

4. **Query Optimization**
   - Use recording rules for expensive queries
   - Set appropriate scrape intervals
   - Use `rate()` instead of `irate()` for smoother graphs

5. **Security**
   - Change default Grafana password
   - Use read-only Prometheus in Grafana
   - Restrict access to metrics endpoints (firewall/nginx auth)

## Next Steps

1. **Add FFmpeg Metrics** (Phase 2.4)
   - Implement FFmpeg exporter
   - Track FPS, bitrate, dropped frames per stream

2. **Add NGINX RTMP Metrics** (Phase 2.3)
   - nginx-rtmp-exporter
   - Track connections, bandwidth, streams

3. **Advanced Alerting**
   - Alertmanager integration
   - Slack/Email notifications
   - PagerDuty integration for critical alerts

4. **Custom Metrics**
   - Webhook metrics (/metrics endpoint)
   - Stream quality metrics
   - Platform-specific metrics (YouTube/Twitch API)

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [DCGM Exporter](https://github.com/NVIDIA/dcgm-exporter)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [cAdvisor](https://github.com/google/cadvisor)
