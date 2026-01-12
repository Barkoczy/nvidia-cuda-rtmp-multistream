#!/bin/bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.staging.yml}"
CONTAINER="${CONTAINER:-nginx-rtmp-staging}"
STREAMS="${STREAMS:-3}"
DURATION="${DURATION:-15}"
RESOLUTION="${RESOLUTION:-1280x720}"
FRAMERATE="${FRAMERATE:-30}"

cleanup() {
  echo "Cleaning up load test FFmpeg processes..."
  docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" sh -c "pkill -f 'ffmpeg.*testsrc'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! docker compose -f "$COMPOSE_FILE" ps | grep -q "$CONTAINER.*Up"; then
  echo "ERROR: Container $CONTAINER is not running"
  exit 1
fi

echo "=== NVENC Load Test ==="
echo "Container: $CONTAINER"
echo "Streams: $STREAMS"
echo "Duration: ${DURATION}s"
echo "Resolution: $RESOLUTION"
echo "Framerate: $FRAMERATE"
echo ""

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "Host GPU memory (used/total):"
  nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader || true
  echo ""
fi

pids=()
for i in $(seq 1 "$STREAMS"); do
  echo "Starting NVENC load stream $i/$STREAMS..."
  docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" sh -c \
    "ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=${RESOLUTION}:rate=${FRAMERATE} -t ${DURATION} -c:v h264_nvenc -f null -" &
  pids+=("$!")
done

fail=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "ERROR: NVENC load test failed"
  exit 1
fi

echo "✓ NVENC load test completed successfully"
