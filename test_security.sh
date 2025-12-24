#!/bin/bash
# Comprehensive security smoke tests (Block 1.4)

set -e

CONTAINER="nginx-rtmp-staging"
COMPOSE_FILE="docker-compose.staging.yml"

echo "=== Security Hardening Smoke Tests ==="
echo ""

# Test 1: Verify container is running
echo "[1/11] Checking container status..."
if docker compose -f "$COMPOSE_FILE" ps | grep -q "$CONTAINER.*Up"; then
    echo "✓ Container is running"
else
    echo "✗ Container is not running"
    exit 1
fi

# Test 2: Verify NGINX workers run as non-root
echo "[2/11] Verifying NGINX worker user..."
worker_users=$(docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" sh -c "ps -o user= -C nginx | tr -s ' ' | sort -u" 2>/dev/null || echo "error")
if echo "$worker_users" | grep -q "broadcaster"; then
    echo "✓ NGINX workers run as broadcaster"
else
    echo "✗ NGINX workers not running as broadcaster (users: $worker_users)"
    exit 1
fi

# Test 3: Verify broadcaster UID
echo "[3/11] Verifying broadcaster UID..."
uid_gid=$(docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" id -u broadcaster 2>/dev/null || echo "error")
if [ "$uid_gid" = "1001" ]; then
    echo "✓ Correct UID: $uid_gid"
else
    echo "✗ Incorrect UID: $uid_gid (expected 1001)"
    exit 1
fi

# Test 4: Verify read-only root filesystem
echo "[4/11] Verifying read-only root filesystem..."
if docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" sh -c "touch /test 2>&1" | grep -q "Read-only file system"; then
    echo "✓ Root filesystem is read-only"
else
    echo "✗ Root filesystem is writable (security issue)"
    exit 1
fi

# Test 5: Verify tmpfs is writable
echo "[5/11] Verifying tmpfs volumes are writable..."
if docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" touch /tmp/test 2>/dev/null; then
    echo "✓ Tmpfs /tmp is writable"
    docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" rm -f /tmp/test
else
    echo "✗ Tmpfs /tmp is not writable"
    exit 1
fi

# Test 6: Verify secrets are mounted and readable
echo "[6/11] Verifying Docker secrets..."
if docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" ls /run/secrets/ 2>/dev/null | grep -q "gaming_youtube_key"; then
    echo "✓ Docker secrets are mounted"
    # Verify file permissions
    perms=$(docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" stat -c "%a" /run/secrets/gaming_youtube_key 2>/dev/null || echo "000")
    if [ "$perms" = "400" ] || [ "$perms" = "600" ]; then
        echo "✓ Secret file permissions are secure ($perms)"
    else
        echo "⚠ Warning: Secret permissions are $perms (expected 400 or 600)"
    fi
else
    echo "⚠ Warning: Docker secrets not found (may not be initialized yet)"
fi

# Test 7: Verify capabilities
echo "[7/11] Verifying minimal capabilities..."
caps=$(docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" grep CapEff /proc/1/status 2>/dev/null | awk '{print $2}')
if [ ! -z "$caps" ] && [ "$caps" != "0000003fffffffff" ]; then
    echo "✓ Capabilities are restricted (CapEff: $caps)"
else
    echo "⚠ Warning: Container may have all capabilities"
fi

# Test 8: Verify no privilege escalation
echo "[8/11] Verifying no-new-privileges..."
no_new_priv=$(docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" grep NoNewPrivs /proc/1/status 2>/dev/null | awk '{print $2}')
if [ "$no_new_priv" = "1" ]; then
    echo "✓ no-new-privileges is enabled"
else
    echo "⚠ Warning: no-new-privileges may not be enabled"
fi

# Test 9: Verify NVIDIA GPU access
echo "[9/11] Verifying NVIDIA GPU access..."
if docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" nvidia-smi -L 2>/dev/null | grep -q "GPU"; then
    echo "✓ NVIDIA GPU is accessible"
else
    echo "✗ NVIDIA GPU not detected (NVENC required)"
    exit 1
fi

# Test 10: Verify NVENC via FFmpeg
echo "[10/11] Verifying NVENC via FFmpeg..."
if docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" sh -c "ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc=size=128x128:rate=1 -t 1 -c:v h264_nvenc -f null -" >/dev/null 2>&1; then
    echo "✓ NVENC encoding test passed"
else
    echo "✗ NVENC encoding test failed"
    exit 1
fi

# Test 11: Verify webhook connectivity
echo "[11/11] Verifying webhook integration..."
webhook_health=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8090/health 2>/dev/null || echo "000")
if [ "$webhook_health" = "200" ]; then
    echo "✓ Webhook server is healthy"
else
    echo "✗ Webhook server is not responding (HTTP $webhook_health)"
    exit 1
fi

echo ""
echo "=== Security Audit Summary ==="
echo ""

# Generate security report
echo "Detailed security information:"
echo ""

echo "Container User:"
docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" id 2>/dev/null || echo "  Error retrieving user info"

echo ""
echo "Mounted Secrets:"
docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" ls -la /run/secrets/ 2>/dev/null | head -n 10 || echo "  No secrets mounted"

echo ""
echo "Process Capabilities:"
docker compose -f "$COMPOSE_FILE" exec -T "$CONTAINER" grep "^Cap" /proc/1/status 2>/dev/null || echo "  Error retrieving capabilities"

echo ""
echo "Container Security Options:"
docker inspect "$CONTAINER" 2>/dev/null | grep -A 10 "SecurityOpt" || echo "  Error retrieving security options"

echo ""
echo "=== All security tests passed! ==="
echo ""
echo "Next steps:"
echo "1. Test RTMP streaming: ffmpeg -re -i test.mp4 -c copy -f flv rtmp://localhost:1936/live/gaming"
echo "2. Monitor logs: docker compose -f $COMPOSE_FILE logs -f"
echo "3. Check webhook logs: docker compose -f $COMPOSE_FILE logs webhook"
echo "4. Run functional tests: ./test_webhook.sh"
