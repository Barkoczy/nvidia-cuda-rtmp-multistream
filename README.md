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

**### YouTube RTMP Stream Settings - YAML Configuration Table**
| **Setting**        | **Resolution**   | **Framerate** | **gopSize** | **Video Bitrate**     | **Example YAML**                        |
|--------------------|------------------|---------------|-------------|-----------------------|-----------------------------------------|
| `url`              | -                | -             | -           | -                     | `rtmp://a.rtmp.youtube.com/live2`       |
| `bitrate`          | 4K / 2160p       | 60 fps        | 120         | 40 Mbps               | `bitrate: 40000k`                       |
| `bitrate`          | 4K / 2160p       | 30 fps        | 60          | 35 Mbps               | `bitrate: 35000k`                       |
| `bitrate`          | 1440p            | 60 fps        | 120         | 30 Mbps               | `bitrate: 30000k`                       |
| `bitrate`          | 1440p            | 30 fps        | 60          | 25 Mbps               | `bitrate: 25000k`                       |
| `bitrate`          | 1080p            | 60 fps        | 120         | 10 Mbps               | `bitrate: 10000k`                       |
| `bitrate`          | 1080p            | 30 fps        | 60          | 8 Mbps                | `bitrate: 8000k`                        |
| `bitrate`          | 720p             | 60 fps        | 120         | 8 Mbps                | `bitrate: 8000k`                        |
| `bitrate`          | 240p - 720p      | 30 fps        | 60          | 8 Mbps                | `bitrate: 8000k`                        |
| `framerate`        | 4K / 2160p       | 60 fps        | 120         | 40 Mbps               | `framerate: 60`                         |
| `framerate`        | 4K / 2160p       | 30 fps        | 60          | 35 Mbps               | `framerate: 30`                         |
| `framerate`        | 1440p            | 60 fps        | 120         | 30 Mbps               | `framerate: 60`                         |
| `framerate`        | 1440p            | 30 fps        | 60          | 25 Mbps               | `framerate: 30`                         |
| `framerate`        | 1080p            | 60 fps        | 120         | 10 Mbps               | `framerate: 60`                         |
| `framerate`        | 1080p            | 30 fps        | 60          | 8 Mbps                | `framerate: 30`                         |
| `framerate`        | 720p             | 60 fps        | 120         | 8 Mbps                | `framerate: 60`                         |
| `framerate`        | 240p - 720p      | 30 fps        | 60          | 8 Mbps                | `framerate: 30`                         |
| `gopSize`          | 4K / 2160p       | 60 fps        | 120         | 40 Mbps               | `gopSize: 120`                          |
| `gopSize`          | 4K / 2160p       | 30 fps        | 60          | 35 Mbps               | `gopSize: 60`                           |
| `gopSize`          | 1440p            | 60 fps        | 120         | 30 Mbps               | `gopSize: 120`                          |
| `gopSize`          | 1440p            | 30 fps        | 60          | 25 Mbps               | `gopSize: 60`                           |
| `gopSize`          | 1080p            | 60 fps        | 120         | 10 Mbps               | `gopSize: 120`                          |
| `gopSize`          | 1080p            | 30 fps        | 60          | 8 Mbps                | `gopSize: 60`                           |
| `gopSize`          | 720p             | 60 fps        | 120         | 8 Mbps                | `gopSize: 120`                          |
| `gopSize`          | 240p - 720p      | 30 fps        | 60          | 8 Mbps                | `gopSize: 60`                           |
| `preset`           | -                | -             | -           | -                     | `preset: fast`                      |
| `scale`            | 4K / 2160p       | 60 fps        | 120         | 40 Mbps               | `scale: 3840x2160`                      |
| `scale`            | 4K / 2160p       | 30 fps        | 60          | 35 Mbps               | `scale: 3840x2160`                      |
| `scale`            | 1440p            | 60 fps        | 120         | 30 Mbps               | `scale: 2560x1440`                      |
| `scale`            | 1440p            | 30 fps        | 60          | 25 Mbps               | `scale: 2560x1440`                      |
| `scale`            | 1080p            | 60 fps        | 120         | 10 Mbps               | `scale: 1920x1080`                      |
| `scale`            | 1080p            | 30 fps        | 60          | 8 Mbps                | `scale: 1920x1080`                      |
| `scale`            | 720p             | 60 fps        | 120         | 8 Mbps                | `scale: 1280x720`                       |
| `scale`            | 240p - 720p      | 30 fps        | 60          | 8 Mbps                | `scale: 1280x720`                       |

**### YAML configuration example for YouTube with NVIDIA NVENC:**
```yaml
youtube:
  url: rtmp://a.rtmp.youtube.com/live2
  bitrate: 40000k
  framerate: 60
  gopSize: 120
  preset: fast
  profile: main
```

### Twitch RTMP Stream Settings - YAML Configuration Table

| **Setting**        | **Resolution**   | **Framerate** | **gopSize** | **Video Bitrate**     | **Example YAML**                        |
|--------------------|------------------|---------------|-------------|-----------------------|-----------------------------------------|
| `url`              | -                | -             | -           | -                     | `rtmp://live.twitch.tv/app`             |
| `bitrate`          | 1920x1080        | 60 fps        | 120         | 6000k                 | `bitrate: 6000k`                       |
| `bitrate`          | 1920x1080        | 30 fps        | 60          | 4500k                 | `bitrate: 4500k`                       |
| `bitrate`          | 1280x720         | 60 fps        | 120         | 4500k                 | `bitrate: 4500k`                       |
| `framerate`        | 1920x1080        | 60 fps        | 120         | 6000k                 | `framerate: 60`                        |
| `framerate`        | 1920x1080        | 30 fps        | 60          | 4500k                 | `framerate: 30`                        |
| `framerate`        | 1280x720         | 60 fps        | 120         | 4500k                 | `framerate: 60`                        |
| `gopSize`          | 1920x1080        | 60 fps        | 120         | 6000k                 | `gopSize: 120`                         |
| `gopSize`          | 1920x1080        | 30 fps        | 60          | 4500k                 | `gopSize: 60`                          |
| `gopSize`          | 1280x720         | 60 fps        | 120         | 4500k                 | `gopSize: 120`                         |
| `preset`           | -                | -             | -           | -                     | `preset: fast`                      |
| `scale`            | 1920x1080        | 60 fps        | 120         | 6000k                 | `scale: 1920x1080`                     |
| `scale`            | 1920x1080        | 30 fps        | 60          | 4500k                 | `scale: 1920x1080`                     |
| `scale`            | 1280x720         | 60 fps        | 120         | 4500k                 | `scale: 1280x720`                      |

### YAML configuration example for Twitch with NVIDIA NVENC:

```yaml
twitch:
  url: rtmp://live.twitch.tv/app
  bitrate: 6000k
  framerate: 60
  gopSize: 120
  preset: fast
  scale: 1920x1080
```

This configuration is now fully updated with all adjustments made for **Twitch** using **NVIDIA NVENC**. Let me know if you need further adjustments or additional platforms!

### Kick Encoder RTMP Stream Settings - YAML Configuration Table

| **Setting**        | **Resolution**   | **Framerate** | **gopSize** | **Video Bitrate**     | **Example YAML**                        |
|--------------------|------------------|---------------|-------------|-----------------------|-----------------------------------------|
| `url`              | -                | -             | -           | -                     | `rtmp://rtmp.kick.com/live`             |
| `bitrate`          | 1920x1080        | -             | 60          | 1000k to 8000k         | `bitrate: 8000k`                       |
| `framerate`        | 1920x1080        | -             | 60          | 1000k to 8000k         | `framerate: 60`                        |
| `gopSize`          | 1920x1080        | -             | 60          | 1000k to 8000k         | `gopSize: 120`                         |
| `preset`           | 1920x1080        | -             | 60          | 1000k to 8000k         | `preset: fast`                         |
| `profile`          | 1920x1080        | -             | 60          | 1000k to 8000k         | `profile: high`                        |
| `scale`            | 1920x1080        | -             | 60          | 1000k to 8000k         | `scale: 1920x1080` (if source has higher resolution) |

### YAML configuration example for Kick encoder:

```yaml
kick:
  url: rtmp://rtmp.kick.com/live
  bitrate: 8000k
  framerate: 60
  gopSize: 120
  preset: fast
  profile: high
  scale: 1920x1080
```

### x (Twitter) RTMP Stream Settings - YAML Configuration Table

| **Setting**        | **Resolution**   | **Framerate** | **gopSize** | **Video Bitrate** | **Example YAML**                        |
|--------------------|------------------|---------------|-------------|-------------------|-----------------------------------------|
| `url`              | -                | -             | -           | -                 | `rtmp://rtmp.x.com/live`                |
| `bitrate`          | 1280x720         | 30 fps        | 90          | 9Mbps (recommended) | `bitrate: 9000k`                       |
| `bitrate`          | 1280x720         | 60 fps        | 180         | 9Mbps (recommended) | `bitrate: 9000k`                       |
| `bitrate`          | 1280x720         | 60 fps        | 180         | 12Mbps (maximum)   | `bitrate: 12000k`                      |
| `bitrate`          | 1920x1080        | 30 fps        | 90          | 9Mbps (recommended) | `bitrate: 9000k`                       |
| `bitrate`          | 1920x1080        | 30 fps        | 90          | 12Mbps (maximum)   | `bitrate: 12000k`                      |
| `framerate`        | 1280x720         | 30 fps        | 90          | 9Mbps (recommended) | `framerate: 30`                        |
| `framerate`        | 1280x720         | 60 fps        | 180         | 9Mbps (recommended) | `framerate: 60`                        |
| `framerate`        | 1280x720         | 60 fps        | 180         | 12Mbps (maximum)   | `framerate: 60`                        |
| `gopSize`          | 1280x720         | 30 fps        | 90          | 9Mbps (recommended) | `gopSize: 90`                          |
| `gopSize`          | 1280x720         | 60 fps        | 180         | 9Mbps (recommended) | `gopSize: 180`                         |
| `gopSize`          | 1280x720         | 60 fps        | 180         | 12Mbps (maximum)   | `gopSize: 180`                         |
| `gopSize`          | 1920x1080        | 30 fps        | 90          | 9Mbps (recommended) | `gopSize: 90`                          |
| `gopSize`          | 1920x1080        | 30 fps        | 90          | 12Mbps (maximum)   | `gopSize: 90`                          |
| `gopSize`          | 1920x1080        | 60 fps        | 180         | 9Mbps (recommended) | `gopSize: 180`                         |
| `gopSize`          | 1920x1080        | 60 fps        | 180         | 12Mbps (maximum)   | `gopSize: 180`                         |
| `preset`           | -                | -             | -           | -                 | `preset: fast`                         |
| `profile`          | -                | -             | -           | -                 | `profile: high`                        |
| `scale`            | 1280x720         | 30 fps        | 90          | 9Mbps (recommended) | `scale: 1280:720`                      |
| `scale`            | 1280x720         | 60 fps        | 180         | 9Mbps (recommended) | `scale: 1280:720`                      |
| `scale`            | 1920x1080        | 30 fps        | 90          | 9Mbps (recommended) | `scale: 1920:1080`                     |
| `scale`            | 1920x1080        | 60 fps        | 180         | 9Mbps (recommended) | `scale: 1920:1080`                     |

### For an example YAML configuration file:

```yaml
x:
  url: rtmp://rtmp.x.com/live
  bitrate: 12000k
  framerate: 60
  gopSize: 180
  preset: fast
  profile: high
  scale: 1280:720
```

### Keyframe interval (gopSize) based on the documentation:
- For **30 fps**: gopSize = `90`
- For **60 fps**: gopSize = `180`

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