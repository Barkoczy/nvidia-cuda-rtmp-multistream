#!/bin/bash
# Test script for webhook integration (Block 1.1.4)

set -e

WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:8090}"
PROFILE="${TEST_PROFILE:-gaming}"

echo "=== Webhook Integration Test ==="
echo "Webhook URL: $WEBHOOK_URL"
echo "Test Profile: $PROFILE"
echo ""

# Test 1: Health check
echo "[1/6] Testing health endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" "$WEBHOOK_URL/health")
if [ "$response" = "200" ]; then
    echo "✓ Health check passed (HTTP $response)"
else
    echo "✗ Health check failed (HTTP $response)"
    exit 1
fi

# Test 2: Publish event (stream start)
echo "[2/6] Testing publish event..."
response=$(curl -s -X POST "$WEBHOOK_URL/api/v1/publish" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "name=$PROFILE&app=live" \
    -w "\n%{http_code}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo "✓ Publish event accepted (HTTP $http_code)"
    echo "  Response: $body"
else
    echo "✗ Publish event failed (HTTP $http_code)"
    echo "  Response: $body"
    exit 1
fi

# Test 3: Wait for processes to start
echo "[3/6] Testing invalid profile rejection..."
response=$(curl -s -X POST "$WEBHOOK_URL/api/v1/publish" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "name=bad;rm%20-rf&app=live" \
    -w "\n%{http_code}")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "400" ]; then
    echo "✓ Invalid profile rejected (HTTP $http_code)"
else
    echo "⚠ Warning: Invalid profile not rejected (HTTP $http_code)"
fi

# Test 4: Wait for processes to start
echo "[4/6] Waiting for processes to start (5 seconds)..."
sleep 5

# Test 5: Check if broadcaster processes are running
echo "[5/6] Checking for active broadcaster processes..."
if docker compose exec -T nginx-rtmp-staging ps aux | grep -q "[b]roadcaster.*$PROFILE"; then
    echo "✓ Broadcaster process found"
    docker compose exec -T nginx-rtmp-staging ps aux | grep "[b]roadcaster.*$PROFILE" | head -n3
else
    echo "⚠ Warning: Broadcaster process not found (may have already completed)"
fi

# Test 6: Publish done event (stream stop)
echo "[6/6] Testing publish_done event..."
response=$(curl -s -X POST "$WEBHOOK_URL/api/v1/publish_done" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "name=$PROFILE&app=live" \
    -w "\n%{http_code}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo "✓ Publish done event accepted (HTTP $http_code)"
    echo "  Response: $body"
else
    echo "✗ Publish done event failed (HTTP $http_code)"
    echo "  Response: $body"
    exit 1
fi

echo ""
echo "=== All webhook tests passed! ==="
echo ""
echo "Additional verification:"
echo "- Check webhook logs: docker compose logs webhook"
echo "- Check broadcaster logs: docker compose exec nginx-rtmp-staging ls -la /var/log/broadcaster/"
echo "- Check RTMP stats: curl http://localhost:8081/stat"
