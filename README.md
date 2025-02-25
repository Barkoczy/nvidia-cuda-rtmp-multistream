# NGINX RTMP Multi-Platform Restreaming Server (NVIDIA GPU Only)

A Docker-based NGINX RTMP server leveraging NVIDIA GPU hardware acceleration for restreaming to multiple platforms simultaneously (YouTube, Twitch, and Kick). This solution is designed exclusively for systems with NVIDIA GPUs to provide optimal transcoding performance.

## Features

- Simultaneous streaming to multiple platforms
- NVIDIA GPU hardware acceleration (NVENC)
- Profile-based configuration system
- Automatic stream key management
- Log rotation and management
- Real-time stream monitoring
- GPU-accelerated video transcoding
- Automatic fallback to CPU encoding if GPU is unavailable

## Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with compatible drivers
- NVIDIA Container Toolkit
- NVIDIA Driver version 450.80.02 or higher

## Quick Start

1. Copy configuration files:
```bash
cp .env.sample .env
cp profiles.yml.sample profiles.yml
```

2. Configure your streaming keys in .env:
```
GAMING_YOUTUBE_KEY=your_youtube_key
GAMING_TWITCH_KEY=your_twitch_key
GAMING_KICK_KEY=your_kick_key
```

3. Start the container:
```bash
docker compose up -d
```

## Configuration

### Profile System

Profiles are configured in profiles.yml. Each profile can have multiple streaming services:

```yaml
profile_name:
  youtube:
    url: rtmp://a.rtmp.youtube.com/live2
    bitrate: 40000k
    framerate: 60
    gopSize: 120
    preset: fast
    profile: main
  twitch:
    url: rtmps://prg03.contribute.live-video.net/app
    bitrate: 8000k
    framerate: 60
    gopSize: 120
    preset: fast
    profile: high
    scale: 1920:1080
```

### Stream Keys

Stream keys are loaded from environment variables using the naming convention:
```
PROFILE_SERVICE_KEY
```
Example: For profile "gaming" and service "youtube", the key will be loaded from `GAMING_YOUTUBE_KEY`

## Monitoring

1. RTMP Statistics:
```
http://localhost:8080/stat
```

2. Log Files:
```
http://localhost:8080/logs
```

3. Stream Status:
```bash
docker compose logs -f nginx-rtmp
```

## GPU Monitoring

Check GPU utilization:
```bash
docker compose exec nginx-rtmp nvidia-smi
```

## Log Management

Logs are automatically rotated with these settings:
- Rotation: Daily
- Maximum size: 50MB
- Compression: Enabled
- Retention: 3 days

## License

MIT License

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.