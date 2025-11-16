# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based NGINX RTMP server that restreams to multiple platforms simultaneously (YouTube, Twitch, Kick, X/Twitter) using NVIDIA GPU hardware acceleration (NVENC). The system uses a profile-based configuration where each profile can broadcast to multiple services with different encoding settings.

**Current Branch**: `feature/phase1-security`
**Status**: Phase 1 security hardening complete, Phase 2 observability stack implemented

## Architecture

### Core Components

1. **NGINX RTMP Server** (nginx.conf:10-35)
   - Listens on port 1935 for incoming RTMP streams
   - Application endpoint: `rtmp://localhost:1935/live/PROFILE_NAME`
   - **Staging**: Uses port 1936 and calls webhook instead of direct exec
   - Triggers two mechanisms when a stream starts:
     - **Production**: `exec_publish` - Directly executes scripts (legacy)
     - **Staging**: `on_publish` webhook - HTTP POST to webhook service (secure)
   - Scripts/endpoints triggered:
     - `hls_transcode`: Creates HLS adaptive bitrate streams for playback
     - `broadcaster`: Spawns FFmpeg processes to restream to configured platforms

2. **Webhook Service** (webhook/main.go) - **NEW in Phase 1**
   - Go-based HTTP server replacing vulnerable `exec_publish`
   - Endpoints:
     - `POST /api/v1/publish` - Start stream
     - `POST /api/v1/publish_done` - Stop stream
     - `GET /health` - Health check
   - Input sanitization (alphanumeric + underscore/hyphen only)
   - Eliminates command injection vulnerability
   - Runs on port 8090 (staging)

3. **Broadcaster Script** (broadcaster)
   - Profile-based restreaming orchestrator
   - Reads `profiles.yml` using `yq` to get service configurations
   - **Secret Loading** (Phase 1):
     - Primary: Reads from Docker secrets at `/run/secrets/{profile}_{service}_key`
     - Fallback: Environment variables `PROFILENAME_SERVICENAME_KEY` (legacy)
   - Spawns separate FFmpeg process for each configured service
   - Process management via PID files in `/var/log/broadcaster/`
   - Automatically stops existing streams before starting new ones

4. **HLS Transcode Script** (hls_transcode)
   - Creates GPU-accelerated HLS streams with 3 quality levels (1080p, 720p, 480p)
   - Uses fMP4 segments for modern HLS playback
   - Outputs to `/tmp/hls/` directory
   - Accessible via HTTP at `http://localhost:8080/hls/PROFILE_NAME.m3u8`

5. **Observability Stack** - **NEW in Phase 2**
   - **Prometheus**: Metrics collection (port 9090)
   - **Grafana**: Dashboards and visualization (port 3000)
   - **Loki**: Log aggregation (port 3100)
   - **Promtail**: Log collection agent
   - **DCGM Exporter**: NVIDIA GPU metrics (port 9400)
   - **Node Exporter**: Host metrics (port 9100)
   - **cAdvisor**: Container metrics (port 8082)

### Key File Flow

```
Incoming RTMP Stream → NGINX (port 1935)
  ├─→ hls_transcode → Creates HLS variants in /tmp/hls/
  └─→ broadcaster → Reads profiles.yml → Spawns FFmpeg per service → Restreams to platforms

Staging Flow (Secure):
RTMP Stream → NGINX (port 1936) → Webhook HTTP POST → Webhook validates → broadcaster → FFmpeg
```

### Configuration System

- **profiles.yml**: Defines streaming profiles and per-service encoding settings
  - Each profile (e.g., "gaming", "events") contains service configurations
  - Service settings: url, bitrate, framerate, gopSize, preset, profile, scale

- **Docker Secrets** (Phase 1 - Preferred):
  - Stored in `/run/secrets/` as read-only files
  - Naming convention: `{profile}_{service}_key` (lowercase, e.g., `gaming_youtube_key`)
  - Permissions: 600 (owner read-only)
  - Not visible in `docker inspect` or process environment

- **Environment Variables** (Legacy fallback):
  - Format: `PROFILENAME_SERVICENAME_KEY` (all uppercase)
  - Example: `GAMING_YOUTUBE_KEY`, `GAMING_TWITCH_KEY`
  - Exported to `/etc/broadcaster/.env` on container startup
  - Use `./init_secrets.sh` to migrate to Docker secrets

### NVIDIA GPU Integration

- Uses CUDA 12.8 base image with NVENC/NVDEC support
- FFmpeg compiled with `--enable-cuda-nvcc`, `--enable-nvenc`, `--enable-nvdec`
- Entrypoint script (entrypoint.sh:12-50) auto-detects GPU and creates required symlinks
- Hardware acceleration flags: `-hwaccel cuda -hwaccel_device 0`
- **GPU Monitoring**: DCGM Exporter provides real-time NVENC/NVDEC utilization

### Codec Selection Logic (broadcaster:226-241)

- **YouTube**: `hevc_nvenc` (H.265) for 4K/high bitrate streams
- **Twitch/Kick**: `h264_nvenc` (H.264) due to platform requirements
- **Others**: Defaults to `h264_nvenc` with high profile

### Security Features (Phase 1)

- **Read-only root filesystem**: Container uses `read_only: true` with tmpfs for writable paths
- **Non-root execution**: Runs as `broadcaster` user (UID 1000)
- **Minimal capabilities**: Only 5 Linux capabilities (CHOWN, DAC_OVERRIDE, SETGID, SETUID, NET_BIND_SERVICE)
- **no-new-privileges**: Prevents privilege escalation
- **Docker secrets**: Stream keys never exposed in environment or logs
- **Webhook validation**: Sanitizes all inputs to prevent command injection
- **CIS Docker Benchmark compliant**

## Common Commands

### Building and Running

```bash
# Copy configuration templates
cp .env.example .env
cp profiles.yml.example profiles.yml

# Configure streaming keys
# Option 1: Docker Secrets (Recommended)
./init_secrets.sh  # Migrates .env keys to secrets/

# Option 2: Environment Variables (Legacy)
# Edit .env with keys: PROFILENAME_SERVICENAME_KEY=your_key_here

# Production environment
docker compose up -d --build

# Staging environment (secure hardened version)
docker compose -f docker-compose.staging.yml up -d --build

# View logs
docker compose logs -f nginx-rtmp

# Rebuild after Dockerfile changes
docker compose up -d --build --force-recreate
```

### Streaming

```bash
# Stream to a profile (e.g., "gaming" profile)
# Production: rtmp://SERVER_IP:1935/live/gaming
# Staging:    rtmp://SERVER_IP:1936/live/gaming

# Using OBS: Set RTMP URL to rtmp://SERVER_IP:1935/live/gaming
# The profile name must match a profile defined in profiles.yml
```

### Monitoring

```bash
# RTMP statistics (shows active streams and bandwidth)
curl http://localhost:8080/stat

# GPU utilization
docker compose exec nginx-rtmp nvidia-smi

# View broadcaster logs
docker compose exec nginx-rtmp ls -la /var/log/broadcaster/

# Check active streams for a profile
docker compose exec nginx-rtmp cat /var/log/broadcaster/PROFILE_*.pid

# View HLS streams
# Access http://localhost:8080/hls/PROFILE_NAME.m3u8

# === Observability Stack (Phase 2) ===

# Grafana dashboards
open http://localhost:3000  # Default: admin/admin

# Prometheus metrics and alerts
curl http://localhost:9090/api/v1/targets
curl http://localhost:9090/api/v1/alerts

# GPU metrics (DCGM)
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL

# Host metrics (Node Exporter)
curl http://localhost:9100/metrics

# Container metrics (cAdvisor)
curl http://localhost:8082/metrics

# Loki logs
curl http://localhost:3100/loki/api/v1/query

# Query logs for specific profile
curl -G http://localhost:3100/loki/api/v1/query \
  --data-urlencode 'query={job="broadcaster", profile="gaming"}'
```

### Debugging

```bash
# Check if FFmpeg processes are running
docker compose exec nginx-rtmp ps aux | grep ffmpeg

# View debug log
docker compose exec nginx-rtmp tail -f /var/log/broadcaster/debug.log
docker compose exec nginx-rtmp tail -f /var/log/broadcaster/exec_debug.log

# Test NVIDIA GPU detection
docker compose exec nginx-rtmp nvidia-smi

# Verify Docker secrets are mounted
docker compose exec nginx-rtmp ls -la /run/secrets/

# Verify environment variables are loaded (legacy)
docker compose exec nginx-rtmp cat /etc/broadcaster/.env

# Test yq and profile parsing
docker compose exec nginx-rtmp yq e '.gaming' /etc/broadcaster/profiles.yml

# Webhook health check (staging)
curl http://localhost:8090/health

# Check webhook logs
docker compose -f docker-compose.staging.yml logs -f webhook-staging
```

### Testing

```bash
# Security smoke tests (10 automated checks)
./test_security.sh

# Webhook integration tests
./test_webhook.sh

# Full staging validation
docker compose -f docker-compose.staging.yml up -d
sleep 15
./test_security.sh && ./test_webhook.sh
```

### Stopping Streams

```bash
# Stop all streams for a profile
docker compose exec nginx-rtmp /usr/local/bin/broadcaster --profile PROFILE_NAME --stop

# Kill all FFmpeg processes (emergency stop)
docker compose exec nginx-rtmp pkill -9 ffmpeg
```

## Development Notes

### Environments

**Production** (`docker-compose.yml`):
- Ports: 1935 (RTMP), 8080 (HTTP)
- Uses `exec_publish` (legacy, vulnerable to command injection)
- Direct script execution

**Staging** (`docker-compose.staging.yml`):
- Ports: 1936 (RTMP), 8081 (HTTP), 8090 (Webhook)
- Uses webhook server (secure)
- Security hardening enabled
- Read-only filesystem
- Non-root user
- Docker secrets
- Observability stack included

### Modifying Encoding Settings

When adding new platforms or modifying encoding parameters in profiles.yml:

- **gopSize**: Should equal framerate * 2 for most platforms (e.g., 60fps = 120 gop, 30fps = 60 gop)
  - Exception: X/Twitter uses gopSize = framerate * 3 (e.g., 60fps = 180 gop)
- **bitrate**: Platform-specific limits apply (see README tables for YouTube/Twitch/Kick/X)
- **scale**: Optional resolution scaling (format: `1920:1080` or `1280:720`)
- **preset**: NVENC presets (fast, medium, slow, p1-p7 for newer drivers)
- **profile**: H.264/H.265 profile (baseline, main, high)

### Script Modifications

- **broadcaster**: Bash script with yq-based YAML parsing. Modifying requires understanding:
  - PID file management (broadcaster:74-118)
  - Docker secrets fallback logic (broadcaster:184-217)
  - FFmpeg parameter construction (broadcaster:249-269)

- **hls_transcode**: Fixed 3-tier ABR configuration. Changes require understanding fMP4 HLS segmentation.

- **nginx.conf**: RTMP and HTTP server config. Changes to `exec_publish` directives affect stream lifecycle.
  - **Staging**: Use `on_publish` webhook instead of `exec_publish`

- **webhook/main.go**: Webhook server for secure stream control. Modify to add:
  - Additional validation rules
  - Custom metrics endpoint
  - Stream lifecycle hooks

### Adding New Streaming Services

1. Add service configuration to profile in `profiles.yml`
2. Add streaming key:
   - **Docker Secrets**: Create `secrets/{profile}_{service}_key.txt`
   - **Environment Variables**: Set `PROFILENAME_SERVICENAME_KEY=key` in `.env`
3. Broadcaster script will auto-detect and spawn FFmpeg process
4. May need to adjust codec selection in broadcaster:226-241 for service requirements

### Container User Permissions

- Container runs NGINX as user `broadcaster` (created in Dockerfile:138)
- **Staging**: Runs as UID 1000 for security
- All scripts, logs, and config files owned by `broadcaster:broadcaster`
- Permissions set in Dockerfile:142-150 and entrypoint.sh:67-83
- If adding new directories/files, ensure proper ownership for `broadcaster` user
- **Tmpfs volumes**: Required for writable paths in read-only filesystem (`/tmp`, `/var/run`, `/var/cache/nginx`)

### Log Rotation

- Configured in `broadcaster-logrotate`
- Daily rotation, 50MB max size, 3-day retention
- Cron job runs at midnight (entrypoint.sh:86)
- Old logs auto-deleted by broadcaster script (broadcaster:17)
- **Loki**: 7-day retention for aggregated logs

### Security Best Practices

1. **Always use Docker secrets** for new deployments
2. **Never commit secrets** to git (covered by `.gitignore`)
3. **Test in staging** before production deployment
4. **Run security tests** after any changes: `./test_security.sh`
5. **Monitor alerts** in Prometheus for security events
6. **Rotate keys regularly** by updating secret files and restarting containers

### Migration from Production to Staging

```bash
# 1. Migrate secrets
./init_secrets.sh

# 2. Test in staging
docker compose -f docker-compose.staging.yml up -d

# 3. Validate security
./test_security.sh
./test_webhook.sh

# 4. Deploy to production (when ready)
# See docs/PRODUCTION_MIGRATION.md for detailed steps
```

## File Purposes

**Core Files**:
- **Dockerfile**: Multi-stage build with CUDA, FFmpeg (NVENC), NGINX, and dependencies
- **Dockerfile.hardened**: Security-hardened multi-stage build (Phase 1)
- **docker-compose.yml**: Production service definition with GPU reservation and port mappings
- **docker-compose.staging.yml**: Staging environment with security hardening and observability
- **entrypoint.sh**: Container initialization, GPU detection, symlink creation, env export
- **nginx.conf**: RTMP server config and HTTP endpoints for stats/HLS/logs
- **nginx.staging.conf**: Staging NGINX config with webhook integration
- **broadcaster**: Main restreaming orchestrator (profile → FFmpeg processes)
- **hls_transcode**: ABR HLS stream generator for web playback
- **profiles.yml**: Streaming profile and service configuration
- **.env**: Streaming keys storage (not committed to git) - legacy

**Security (Phase 1)**:
- **webhook/main.go**: Go webhook server for secure stream control
- **webhook/Dockerfile**: Multi-stage build for webhook
- **secrets/**: Docker secrets directory for stream keys
- **init_secrets.sh**: Helper script to migrate .env to Docker secrets
- **test_security.sh**: 10 automated security smoke tests
- **test_webhook.sh**: Webhook integration tests

**Observability (Phase 2)**:
- **observability/prometheus.yml**: Prometheus configuration
- **observability/loki-config.yml**: Loki configuration
- **observability/promtail-config.yml**: Promtail configuration
- **observability/alerts/**: Alert rules for GPU and streams
- **observability/grafana/**: Dashboard provisioning and datasources

**Documentation**:
- **README.md**: User-facing documentation
- **CLAUDE.md**: This file - development guide
- **docs/PHASE1_SUMMARY.md**: Phase 1 security hardening summary
- **docs/OBSERVABILITY.md**: Observability stack documentation
- **docs/PRODUCTION_MIGRATION.md**: Production deployment guide
- **docs/SECRETS_MIGRATION.md**: Docker secrets migration guide
- **docs/CONTAINER_HARDENING.md**: Container security documentation

## Troubleshooting

### Stream Keys Not Working

```bash
# Check if secrets are mounted
docker compose exec nginx-rtmp ls -la /run/secrets/

# Check broadcaster is reading secrets
docker compose exec nginx-rtmp grep "Loading key from Docker secret" /var/log/broadcaster/debug.log

# Fallback to environment variables
docker compose exec nginx-rtmp cat /etc/broadcaster/.env
```

### Webhook Not Responding (Staging)

```bash
# Check webhook health
curl http://localhost:8090/health

# Check webhook logs
docker compose -f docker-compose.staging.yml logs webhook-staging

# Restart webhook
docker compose -f docker-compose.staging.yml restart webhook-staging
```

### Read-Only Filesystem Errors (Staging)

```bash
# Check tmpfs mounts
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging df -h | grep tmpfs

# Verify writable paths
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging touch /tmp/test
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging touch /var/run/test
```

### GPU Metrics Missing

```bash
# Check DCGM exporter
docker compose logs dcgm-exporter-staging

# Verify GPU access
docker compose exec dcgm-exporter-staging nvidia-smi

# Check metrics endpoint
curl http://localhost:9400/metrics | grep DCGM
```

## Performance Baselines

See `.changelogs/20251116/baseline_measurements.md` for performance metrics before and after Phase 1/2 implementations.

**Expected Overhead**:
- Webhook: <1ms latency, ~50MB memory
- Observability stack: ~700MB total memory
- Security hardening: Negligible CPU/GPU impact

## Git Workflow

```bash
# Current work branch
git checkout feature/phase1-security

# View Phase 1 commits
git log --oneline feature/phase1-security

# Main branch for PRs
git checkout main
```

## References

- [NVIDIA NVENC Documentation](https://developer.nvidia.com/nvidia-video-codec-sdk)
- [NGINX RTMP Module](https://github.com/arut/nginx-rtmp-module)
- [FFmpeg NVENC Guide](https://trac.ffmpeg.org/wiki/HWAccelIntro)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- Platform streaming guides in README.md
