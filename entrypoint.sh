#!/bin/bash
# Load environment variables from .env file if it exists
if [ -f "/.env" ]; then
    export $(cat /.env | grep -v '^#' | xargs)
fi

# Verify required environment variables
required_vars=(
    "YOUTUBE_KEY" "TWITCH_KEY" "KICK_KEY"
    "YOUTUBE_URL" "TWITCH_URL" "KICK_URL"
    "YOUTUBE_BITRATE" "YOUTUBE_FRAMERATE" "YOUTUBE_GOP_SIZE" "YOUTUBE_PRESET"
    "TWITCH_BITRATE" "TWITCH_FRAMERATE" "TWITCH_GOP_SIZE"
    "KICK_BITRATE" "KICK_FRAMERATE" "KICK_GOP_SIZE"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

# Automatic detection and setup of NVIDIA libraries
if which nvidia-smi > /dev/null 2>&1; then
    echo "NVIDIA GPU detected - enabling hardware acceleration"
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
    
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

# Define variables for envsubst
VARS='${YOUTUBE_URL} ${YOUTUBE_KEY} ${TWITCH_URL} ${TWITCH_KEY} ${KICK_URL} ${KICK_KEY} ${YOUTUBE_PRESET} ${YOUTUBE_BITRATE} ${YOUTUBE_GOP_SIZE} ${YOUTUBE_FRAMERATE} ${TWITCH_BITRATE} ${TWITCH_GOP_SIZE} ${TWITCH_FRAMERATE} ${KICK_BITRATE} ${KICK_GOP_SIZE} ${KICK_FRAMERATE}'

# Generate final nginx configuration from template
envsubst "$VARS" < /usr/local/nginx/conf/nginx.conf.template > /usr/local/nginx/conf/nginx.conf

# Print diagnostic information
echo "FFmpeg version:"
ffmpeg -version | head -n 1
echo "NVIDIA libraries in LD_LIBRARY_PATH:"
ldconfig -p | grep nvidia

# Start nginx
echo "Starting NGINX RTMP server..."
/usr/local/nginx/sbin/nginx -g "daemon off;"