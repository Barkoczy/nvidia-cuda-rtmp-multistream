#!/bin/bash
set -e

# Clean up any existing FFmpeg processes
echo "Checking and terminating any existing FFmpeg processes..."
pkill -9 ffmpeg 2>/dev/null || true

# Clean up any existing PID files
rm -f /var/log/broadcaster/*.pid

# Automatic detection and setup of NVIDIA libraries
if which nvidia-smi > /dev/null 2>&1; then
    echo "NVIDIA GPU detected - enabling hardware acceleration"
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=all

    # Detecting the driver version
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
    echo "Detected NVIDIA driver version: ${DRIVER_VERSION}"

    # Extraction of a major version number (e.g. 570 from 570.86.10)
    DRIVER_MAJOR=$(echo $DRIVER_VERSION | cut -d. -f1)

    # Creating the necessary symlinks for NVIDIA libraries
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

    # LD_LIBRARY_PATH setting
    export LD_LIBRARY_PATH="/usr/local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
    echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
else
    echo "Warning: No NVIDIA GPU detected - falling back to CPU encoding"
fi

# Print diagnostic information
# Note: FFmpeg version check disabled to avoid missing library errors during startup
# FFmpeg will be verified when actually used for streaming
# echo "FFmpeg version:"
# ffmpeg -version | head -n 1

# NVIDIA library check
echo "NVIDIA libraries in LD_LIBRARY_PATH:"
ldconfig -p | grep nvidia || echo "No NVIDIA libraries found in path"

# Saving all environment variables to /tmp/.env (tmpfs is writable)
echo "Exporting environment variables to /tmp/.env..."
env | grep -E '(_YOUTUBE_KEY|_TWITCH_KEY|_KICK_KEY|_X_KEY)=' > /tmp/.env || true
chmod 644 /tmp/.env
chown broadcaster:broadcaster /tmp/.env

# Note: broadcaster scripts ownership set in Dockerfile (read-only filesystem)
echo "Verifying broadcaster scripts permissions..."
ls -la /usr/local/bin/broadcaster /usr/local/bin/hls_transcode | head -3

# Create and set permissions for log directory (mounted volume)
mkdir -p /var/log/broadcaster
chown -R broadcaster:broadcaster /var/log/broadcaster || true
chmod -R 755 /var/log/broadcaster || true

# Note: profiles.yml is read-only mounted from host, ownership set by Docker

# Create debug log file with correct permissions (in mounted volume)
touch /var/log/broadcaster/exec_debug.log || true
chown broadcaster:broadcaster /var/log/broadcaster/exec_debug.log || true
chmod 644 /var/log/broadcaster/exec_debug.log || true

# Start cron service for log rotation
service cron start

# Print diagnostic information
echo "Setting up log rotation..."
logrotate --debug /etc/logrotate.d/broadcaster

# Start nginx
echo "Starting NGINX RTMP server..."
/usr/local/nginx/sbin/nginx -g "daemon off;"