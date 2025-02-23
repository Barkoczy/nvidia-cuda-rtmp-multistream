# NGINX RTMP Multi-Platform Restreaming Server (NVIDIA GPU Only)

A Docker-based NGINX RTMP server leveraging NVIDIA GPU hardware acceleration for restreaming to multiple platforms simultaneously (YouTube, Twitch, and Kick). This solution is designed exclusively for systems with NVIDIA GPUs to provide optimal transcoding performance.

## Features

- Simultaneous streaming to multiple platforms
- NVIDIA GPU (Required)
- NVIDIA Driver version 450.80.02 or higher
- NVIDIA Container Toolkit
- NVIDIA GPU hardware acceleration (NVENC)
- Windows 10/11 or Linux with NVIDIA GPU support
- Configurable streaming quality per platform
- Low-latency streaming options
- Docker containerization
- Automatic fallback to CPU encoding if GPU is unavailable

## Prerequisites

- Docker and Docker Compose
- NVIDIA GPU with compatible drivers (optional, for hardware acceleration)
- NVIDIA Container Toolkit (for GPU support)

## Hardware Acceleration

This project utilizes:
- NVIDIA NVENC encoder
- CUDA acceleration
- Hardware-based video processing

## Quick Start

1. Copy `.env.sample` to `.env` and configure your streaming keys:
```bash
cp .env.sample .env
```

2. Edit `.env` file with your platform-specific streaming keys and URLs

3. Start the container:
```bash
docker compose up -d
```

## Existing Commands

```bash
docker compose exec -u root nginx-rtmp /bin/bash
```

```bash
/usr/local/nginx/sbin/nginx
```

```
/usr/local/nginx/sbin/nginx -s reload
```

## Platform-Specific Information

### Twitch

For getting Twitch ingest servers:

```bash
curl -X GET 'https://ingest.twitch.tv/ingests' 
```

Reference: https://dev.twitch.tv/docs/video-broadcast/reference/#get-ingest-servers

## Configuration

### Stream Quality Settings

Default quality settings per platform:

- YouTube: 1080p60 at 51Mbps
- Twitch: 1080p60 at 8Mbps
- Kick: 1080p60 at 8Mbps

### Transcoding Templates

Located in `/transcoding-templates/`:
- youtube-4k.conf
- youtube-1080p.conf
- twitch.conf
- kick.conf
- low-latency.conf
- backup-720p.conf

## Monitoring

Access the NGINX RTMP status page at:
```
http://localhost:8080/stat
```

## Troubleshooting

1. Check NGINX logs:
```bash
docker compose logs nginx-rtmp
```

2. Monitor GPU usage:
```bash
docker compose exec nginx-rtmp nvidia-smi
```

## License

MIT License

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.
