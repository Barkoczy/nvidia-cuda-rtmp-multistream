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

# Check NVIDIA GPU availability
if [ "$(nvidia-smi 2>/dev/null)" ]; then
    echo "NVIDIA GPU detected - enabling hardware acceleration"
    export NVIDIA_VISIBLE_DEVICES=all
    export NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
else
    echo "Warning: No NVIDIA GPU detected - falling back to CPU encoding"
fi

# Define variables for envsubst
VARS='${YOUTUBE_URL} ${YOUTUBE_KEY} ${TWITCH_URL} ${TWITCH_KEY} ${KICK_URL} ${KICK_KEY} ${YOUTUBE_PRESET} ${YOUTUBE_BITRATE} ${YOUTUBE_GOP_SIZE} ${YOUTUBE_FRAMERATE} ${TWITCH_BITRATE} ${TWITCH_GOP_SIZE} ${TWITCH_FRAMERATE} ${KICK_BITRATE} ${KICK_GOP_SIZE} ${KICK_FRAMERATE}'

# Generate final nginx configuration from template
envsubst "$VARS" < /usr/local/nginx/conf/nginx.conf.template > /usr/local/nginx/conf/nginx.conf

# Start nginx
/usr/local/nginx/sbin/nginx -g "daemon off;"