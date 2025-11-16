# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker-based NGINX RTMP server that restreams to multiple platforms simultaneously (YouTube, Twitch, Kick, X/Twitter) using NVIDIA GPU hardware acceleration (NVENC). The system uses a profile-based configuration where each profile can broadcast to multiple services with different encoding settings.

## Architecture

### Core Components

1. **NGINX RTMP Server** (nginx.conf:10-35)
   - Listens on port 1935 for incoming RTMP streams
   - Application endpoint: `rtmp://localhost:1935/live/PROFILE_NAME`
   - Triggers two scripts when a stream starts (`exec_publish`):
     - `hls_transcode`: Creates HLS adaptive bitrate streams for playback
     - `broadcaster`: Spawns FFmpeg processes to restream to configured platforms

2. **Broadcaster Script** (broadcaster)
   - Profile-based restreaming orchestrator
   - Reads `profiles.yml` using `yq` to get service configurations
   - Loads streaming keys from environment variables using convention: `PROFILENAME_SERVICENAME_KEY`
   - Spawns separate FFmpeg process for each configured service
   - Process management via PID files in `/var/log/broadcaster/`
   - Automatically stops existing streams before starting new ones

3. **HLS Transcode Script** (hls_transcode)
   - Creates GPU-accelerated HLS streams with 3 quality levels (1080p, 720p, 480p)
   - Uses fMP4 segments for modern HLS playback
   - Outputs to `/tmp/hls/` directory
   - Accessible via HTTP at `http://localhost:8080/hls/PROFILE_NAME.m3u8`

### Key File Flow

```
Incoming RTMP Stream → NGINX (port 1935)
  ├─→ hls_transcode → Creates HLS variants in /tmp/hls/
  └─→ broadcaster → Reads profiles.yml → Spawns FFmpeg per service → Restreams to platforms
```

### Configuration System

- **profiles.yml**: Defines streaming profiles and per-service encoding settings
  - Each profile (e.g., "gaming", "events") contains service configurations
  - Service settings: url, bitrate, framerate, gopSize, preset, profile, scale

- **Environment Variables**: Store streaming keys
  - Format: `PROFILENAME_SERVICENAME_KEY` (all uppercase)
  - Example: `GAMING_YOUTUBE_KEY`, `GAMING_TWITCH_KEY`
  - Exported to `/etc/broadcaster/.env` on container startup

### NVIDIA GPU Integration

- Uses CUDA 12.8 base image with NVENC/NVDEC support
- FFmpeg compiled with `--enable-cuda-nvcc`, `--enable-nvenc`, `--enable-nvdec`
- Entrypoint script (entrypoint.sh:12-50) auto-detects GPU and creates required symlinks
- Hardware acceleration flags: `-hwaccel cuda -hwaccel_device 0`

### Codec Selection Logic (broadcaster:218-234)

- **YouTube**: `hevc_nvenc` (H.265) for 4K/high bitrate streams
- **Twitch/Kick**: `h264_nvenc` (H.264) due to platform requirements
- **Others**: Defaults to `h264_nvenc` with high profile

## Common Commands

### Building and Running

```bash
# Copy configuration templates
cp .env.example .env
cp profiles.yml.example profiles.yml

# Configure streaming keys in .env
# Format: PROFILENAME_SERVICENAME_KEY=your_key_here

# Build and start container
docker compose up -d --build

# View logs
docker compose logs -f nginx-rtmp

# Rebuild after Dockerfile changes
docker compose up -d --build --force-recreate
```

### Streaming

```bash
# Stream to a profile (e.g., "gaming" profile)
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

# Verify environment variables are loaded
docker compose exec nginx-rtmp cat /etc/broadcaster/.env

# Test yq and profile parsing
docker compose exec nginx-rtmp yq e '.gaming' /etc/broadcaster/profiles.yml
```

### Stopping Streams

```bash
# Stop all streams for a profile
docker compose exec nginx-rtmp /usr/local/bin/broadcaster --profile PROFILE_NAME --stop

# Kill all FFmpeg processes (emergency stop)
docker compose exec nginx-rtmp pkill -9 ffmpeg
```

## Development Notes

### Modifying Encoding Settings

When adding new platforms or modifying encoding parameters in profiles.yml:

- **gopSize**: Should equal framerate * 2 for most platforms (e.g., 60fps = 120 gop, 30fps = 60 gop)
- **bitrate**: Platform-specific limits apply (see README tables for YouTube/Twitch/Kick/X)
- **scale**: Optional resolution scaling (format: `1920:1080` or `1280:720`)
- **preset**: NVENC presets (fast, medium, slow, p1-p7 for newer drivers)
- **profile**: H.264/H.265 profile (baseline, main, high)

### Script Modifications

- **broadcaster**: Bash script with yq-based YAML parsing. Modifying requires understanding PID file management and FFmpeg parameter construction.
- **hls_transcode**: Fixed 3-tier ABR configuration. Changes require understanding fMP4 HLS segmentation.
- **nginx.conf**: RTMP and HTTP server config. Changes to `exec_publish` directives affect stream lifecycle.

### Adding New Streaming Services

1. Add service configuration to profile in `profiles.yml`
2. Set environment variable: `PROFILENAME_SERVICENAME_KEY=key` in `.env`
3. Broadcaster script will auto-detect and spawn FFmpeg process
4. May need to adjust codec selection in broadcaster:218-234 for service requirements

### Container User Permissions

- Container runs NGINX as user `broadcaster` (created in Dockerfile:138)
- All scripts, logs, and config files owned by `broadcaster:broadcaster`
- Permissions set in Dockerfile:142-150 and entrypoint.sh:67-83
- If adding new directories/files, ensure proper ownership for `broadcaster` user

### Log Rotation

- Configured in `broadcaster-logrotate`
- Daily rotation, 50MB max size, 3-day retention
- Cron job runs at midnight (entrypoint.sh:86)
- Old logs auto-deleted by broadcaster script (broadcaster:17)

## File Purposes

- **Dockerfile**: Multi-stage build with CUDA, FFmpeg (NVENC), NGINX, and dependencies
- **docker-compose.yml**: Service definition with GPU reservation and port mappings
- **entrypoint.sh**: Container initialization, GPU detection, symlink creation, env export
- **nginx.conf**: RTMP server config and HTTP endpoints for stats/HLS/logs
- **broadcaster**: Main restreaming orchestrator (profile → FFmpeg processes)
- **hls_transcode**: ABR HLS stream generator for web playback
- **profiles.yml**: Streaming profile and service configuration
- **.env**: Streaming keys storage (not committed to git)
