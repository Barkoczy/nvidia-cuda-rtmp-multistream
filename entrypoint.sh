#!/bin/bash
set -e

# Clean up any existing FFmpeg processes
echo "Checking and terminating any existing FFmpeg processes..."
pkill -9 ffmpeg 2>/dev/null || true

# Clean up any existing PID files
rm -f /var/log/broadcaster/*.pid

# Automatic detection and setup of NVIDIA libraries
if command -v nvidia-smi > /dev/null 2>&1; then
    if ! nvidia-smi -L >/dev/null 2>&1; then
        echo "ERROR: NVIDIA GPU not detected - NVENC is required"
        exit 1
    fi
    echo "NVIDIA GPU detected - enabling hardware acceleration"
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=all

    # Detecting the driver version
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
    echo "Detected NVIDIA driver version: ${DRIVER_VERSION}"

    # Extraction of a major version number (e.g. 570 from 570.86.10)
    DRIVER_MAJOR=$(echo $DRIVER_VERSION | cut -d. -f1)

    # Creating the necessary symlinks for NVIDIA libraries (only if writable)
    if [ -w /usr/local/lib ]; then
        echo "Creating symlinks for NVIDIA libraries version ${DRIVER_MAJOR}"

        # Finding and creating symlinks for libnvidia-encode.so
        ENCODE_LIB=$(find /usr/lib/x86_64-linux-gnu -name "libnvidia-encode.so.*" | sort | tail -n 1)
        if [ ! -z "$ENCODE_LIB" ]; then
            ln -sf "$ENCODE_LIB" /usr/local/lib/libnvidia-encode.so.1
            echo "Created symlink: $ENCODE_LIB -> /usr/local/lib/libnvidia-encode.so.1"
        else
            echo "Warning: libnvidia-encode.so library not found"
        fi

        # Finding and creating symlinks for libnvcuvid.so
        CUVID_LIB=$(find /usr/lib/x86_64-linux-gnu -name "libnvcuvid.so.*" | sort | tail -n 1)
        if [ ! -z "$CUVID_LIB" ]; then
            ln -sf "$CUVID_LIB" /usr/local/lib/libnvcuvid.so.1
            echo "Created symlink: $CUVID_LIB -> /usr/local/lib/libnvcuvid.so.1"
        else
            echo "Warning: libnvcuvid.so library not found"
        fi
    else
        echo "Read-only filesystem detected; skipping NVIDIA symlink creation"
    fi

    # LD_LIBRARY_PATH setting
    export LD_LIBRARY_PATH="/usr/local/nvidia/lib64:/usr/local/nvidia/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
    echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
else
    echo "ERROR: nvidia-smi not available - NVENC is required"
    exit 1
fi

# Print diagnostic information
# Note: FFmpeg version check disabled to avoid missing library errors during startup
# FFmpeg will be verified when actually used for streaming
# echo "FFmpeg version:"
# ffmpeg -version | head -n 1

# NVIDIA library check
echo "NVIDIA libraries in LD_LIBRARY_PATH:"
ldconfig -p | grep nvidia || echo "No NVIDIA libraries found in path"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ERROR: ffmpeg not found in PATH"
    exit 1
fi

echo "Validating NVENC availability via FFmpeg..."
if ! ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=128x128:rate=1 -t 1 \
    -c:v h264_nvenc -f null - >/dev/null 2>&1; then
    echo "ERROR: NVENC test failed - check NVIDIA driver/container runtime"
    exit 1
fi

# Note: broadcaster scripts ownership set in Dockerfile (read-only filesystem)
echo "Verifying broadcaster scripts permissions..."
ls -la /usr/local/bin/broadcaster /usr/local/bin/hls_transcode | head -3

# Create and set permissions for log directory (mounted volume)
mkdir -p /var/log/broadcaster /var/log/nginx
chown -R broadcaster:broadcaster /var/log/broadcaster /var/log/nginx || true
chmod -R 755 /var/log/broadcaster /var/log/nginx || true

# Ensure log files are readable by promtail
touch /var/log/nginx/streaming.log /var/log/nginx/error.log || true
chmod 644 /var/log/nginx/streaming.log /var/log/nginx/error.log || true

# Start cron service for log rotation
service cron start

# Print diagnostic information
echo "Setting up log rotation..."
logrotate --debug /etc/logrotate.d/broadcaster

# Start nginx
echo "Starting NGINX RTMP server..."
/usr/local/nginx/sbin/nginx -g "daemon off;"
