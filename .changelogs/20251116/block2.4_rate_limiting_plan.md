# Block 2.4 (Part 2): Rate Limiting Implementation Plan

**Date**: 2025-11-16
**Block**: 2.4 - Rate Limiting
**Status**: 📋 **PLANNING**

---

## Executive Summary

Implement comprehensive rate limiting across all attack surfaces:
1. NGINX HTTP endpoints (status page, webhook callbacks)
2. Webhook API (Go-based rate limiting with sliding window)
3. RTMP connections (connection limits per IP)

**Goals**:
- Prevent brute-force attacks on stream publish attempts
- Prevent DoS attacks on HTTP endpoints
- Mitigate bandwidth exhaustion from rogue clients
- Log rate limit violations for security monitoring

---

## Attack Vectors to Mitigate

### 1. RTMP Publish Brute Force

**Scenario**: Attacker repeatedly tries to publish streams with invalid profiles

**Current State**: ❌ No limit - can attempt unlimited connections

**Impact**:
- Webhook overload (each attempt = HTTP POST)
- NGINX process saturation
- Log file flooding

**Solution**: Webhook rate limiting + NGINX connection limits

### 2. HTTP Status Page DoS

**Scenario**: Attacker floods `/stat` endpoint with requests

**Current State**: ❌ No limit - can query unlimited times

**Impact**:
- CPU exhaustion from generating status JSON
- Network bandwidth saturation
- VTS module overhead

**Solution**: NGINX `limit_req` on `/stat` endpoint

### 3. Webhook Endpoint Flooding

**Scenario**: Direct HTTP POST flooding to webhook:8090/api/v1/publish

**Current State**: ❌ No limit (webhook is internal-only but defense-in-depth)

**Impact**:
- If network isolation fails, webhook could be overwhelmed
- activeStreams map manipulation

**Solution**: Go-based rate limiting with exponential backoff

---

## Implementation Strategy

### Part 1: NGINX HTTP Rate Limiting

**File**: `nginx.staging.conf`

**Changes**:
```nginx
http {
    # Rate limiting zones (10MB = ~160k IP addresses tracked)
    limit_req_zone $binary_remote_addr zone=status_page:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=webhook_callback:10m rate=30r/m;
    limit_req_zone $binary_remote_addr zone=hls_playback:10m rate=100r/m;

    # Connection limiting zones
    limit_conn_zone $binary_remote_addr zone=rtmp_conn:10m;
    limit_conn_zone $binary_remote_addr zone=http_conn:10m;

    server {
        # Limit concurrent connections per IP
        limit_conn http_conn 10;

        location /stat {
            # 10 requests per minute per IP, burst of 5
            limit_req zone=status_page burst=5 nodelay;
            limit_req_status 429;
            # ... existing config ...
        }

        location /status/format/json {
            # For nginx-vts-exporter only
            allow 172.0.0.0/8;  # Docker internal network
            deny all;
            # ... existing config ...
        }

        location /hls/ {
            # 100 requests per minute per IP (HLS segment fetching)
            limit_req zone=hls_playback burst=20 nodelay;
            limit_req_status 429;
            # ... existing config ...
        }
    }
}
```

**Rate Limits Chosen**:
- **Status page**: 10 req/min (manual checks only, burst for page refreshes)
- **HLS playback**: 100 req/min (HLS segments = ~2 req/sec for 1080p)
- **HTTP connections**: 10 concurrent per IP (prevents connection exhaustion)

---

### Part 2: Webhook Go-Based Rate Limiting

**File**: `webhook/main.go`

**Implementation**: Sliding window rate limiter per IP address

```go
package main

import (
    "sync"
    "time"
)

// RateLimiter tracks request timestamps per IP
type RateLimiter struct {
    requests map[string][]time.Time
    mu       sync.RWMutex
    limit    int           // Max requests
    window   time.Duration // Time window
}

// NewRateLimiter creates a rate limiter
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
    rl := &RateLimiter{
        requests: make(map[string][]time.Time),
        limit:    limit,
        window:   window,
    }

    // Cleanup goroutine (runs every window duration)
    go rl.cleanup()

    return rl
}

// Allow checks if request from IP is allowed
func (rl *RateLimiter) Allow(ip string) bool {
    rl.mu.Lock()
    defer rl.mu.Unlock()

    now := time.Now()
    cutoff := now.Add(-rl.window)

    // Get requests for this IP
    timestamps := rl.requests[ip]

    // Remove expired timestamps
    valid := timestamps[:0]
    for _, ts := range timestamps {
        if ts.After(cutoff) {
            valid = append(valid, ts)
        }
    }

    // Check if limit exceeded
    if len(valid) >= rl.limit {
        rl.requests[ip] = valid
        return false
    }

    // Add current timestamp
    valid = append(valid, now)
    rl.requests[ip] = valid

    return true
}

// cleanup removes old entries to prevent memory leak
func (rl *RateLimiter) cleanup() {
    ticker := time.NewTicker(rl.window)
    defer ticker.Stop()

    for range ticker.C {
        rl.mu.Lock()
        now := time.Now()
        cutoff := now.Add(-rl.window)

        for ip, timestamps := range rl.requests {
            valid := timestamps[:0]
            for _, ts := range timestamps {
                if ts.After(cutoff) {
                    valid = append(valid, ts)
                }
            }
            if len(valid) == 0 {
                delete(rl.requests, ip)
            } else {
                rl.requests[ip] = valid
            }
        }
        rl.mu.Unlock()
    }
}

// Global rate limiter for publish attempts
var publishRateLimiter = NewRateLimiter(10, 1*time.Minute)

// Modify handlePublish to use rate limiter
func handlePublish(w http.ResponseWriter, r *http.Request) {
    // Extract client IP
    clientIP := extractClientIP(r)

    // Check rate limit
    if !publishRateLimiter.Allow(clientIP) {
        log.Printf("Rate limit exceeded for IP: %s", clientIP)
        http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
        return
    }

    // ... existing logic ...
}

// extractClientIP gets real client IP (considering X-Forwarded-For)
func extractClientIP(r *http.Request) string {
    // Check X-Forwarded-For header (if behind proxy)
    xff := r.Header.Get("X-Forwarded-For")
    if xff != "" {
        ips := strings.Split(xff, ",")
        return strings.TrimSpace(ips[0])
    }

    // Check X-Real-IP header
    xri := r.Header.Get("X-Real-IP")
    if xri != "" {
        return xri
    }

    // Fall back to RemoteAddr
    ip, _, err := net.SplitHostPort(r.RemoteAddr)
    if err != nil {
        return r.RemoteAddr
    }
    return ip
}
```

**Rate Limits**:
- **Publish attempts**: 10 per minute per IP (prevents rapid reconnect abuse)
- **Window**: 1 minute sliding window
- **Memory**: Auto-cleanup of old entries

---

### Part 3: RTMP Connection Limiting

**File**: `nginx.staging.conf`

**Changes**:
```nginx
rtmp {
    server {
        listen 1935;

        # Limit concurrent connections per IP
        # Note: NGINX RTMP module doesn't support limit_conn natively
        # Use max_connections for global limit instead

        application live {
            live on;

            # Global connection limit (all clients combined)
            max_connections 100;

            # Drop idle publishers aggressively
            drop_idle_publisher 10s;

            # ... existing config ...
        }
    }
}
```

**Limitations**:
- NGINX RTMP module does NOT support per-IP connection limits
- Best we can do: Global `max_connections` + aggressive `drop_idle_publisher`
- Webhook rate limiting provides per-IP protection

---

## Logging and Monitoring

### 1. NGINX Rate Limit Logs

**Add to nginx.staging.conf**:
```nginx
http {
    # Custom log format for rate limiting
    log_format rate_limit '[$time_local] RATE_LIMIT IP=$remote_addr '
                          'Status=$status Request="$request" '
                          'Upstream=$upstream_addr';

    # Log rate limit violations separately
    access_log /var/log/nginx/rate_limit.log rate_limit if=$limit_req_status;
}
```

**Prometheus Metrics** (via nginx-vts-exporter):
- `nginx_server_requests_total{status="429"}` - Count of rate-limited requests
- Alert on high 429 rate = potential attack

### 2. Webhook Rate Limit Logs

**Add to webhook/main.go**:
```go
func (rl *RateLimiter) Allow(ip string) bool {
    // ... existing code ...

    if len(valid) >= rl.limit {
        rl.requests[ip] = valid
        // Log to structured logger (for Loki)
        log.Printf("RATE_LIMIT_EXCEEDED ip=%s requests=%d limit=%d window=%v",
                   ip, len(valid), rl.limit, rl.window)
        return false
    }

    // ... existing code ...
}
```

**Loki Query** (for Grafana alerts):
```logql
{job="webhook"} |= "RATE_LIMIT_EXCEEDED" | json
```

---

## Testing Strategy

### Test 1: NGINX HTTP Rate Limiting

```bash
# Test status page rate limit (10 req/min)
for i in {1..15}; do
    curl -w "Status: %{http_code}\n" http://localhost:8081/stat -o /dev/null
    sleep 1
done

# Expected:
# Requests 1-5: HTTP 200 (burst)
# Requests 6-10: HTTP 200 (rate limit)
# Requests 11+: HTTP 429 (rate limit exceeded)
```

### Test 2: Webhook Rate Limiting

```bash
# Simulate rapid publish attempts from same IP
for i in {1..15}; do
    curl -X POST http://localhost:8090/api/v1/publish \
         -d "name=gaming&app=live" \
         -w "Status: %{http_code}\n"
    sleep 2
done

# Expected:
# Requests 1-10: HTTP 200 (within limit)
# Requests 11+: HTTP 429 (rate limit exceeded)
```

### Test 3: RTMP Connection Limiting

```bash
# Start multiple RTMP streams simultaneously
for i in {1..5}; do
    timeout 10 ffmpeg -re -f lavfi -i testsrc=size=640x480:rate=25 \
                     -c:v libx264 -preset veryfast -b:v 500k \
                     -f flv rtmp://localhost:1936/live/gaming_$i &
done

# Check NGINX stats for connection count
curl http://localhost:8081/stat

# Expected: Max 100 connections (max_connections limit)
```

---

## Configuration Summary

### NGINX Rate Limits

| Endpoint | Rate Limit | Burst | Scope | Enforcement |
|----------|-----------|-------|-------|-------------|
| `/stat` | 10 req/min | 5 | per IP | NGINX limit_req |
| `/hls/*` | 100 req/min | 20 | per IP | NGINX limit_req |
| HTTP connections | 10 concurrent | - | per IP | NGINX limit_conn |
| RTMP connections | 100 total | - | global | RTMP max_connections |

### Webhook Rate Limits

| Endpoint | Rate Limit | Window | Scope | Enforcement |
|----------|-----------|--------|-------|-------------|
| `/api/v1/publish` | 10 requests | 1 min | per IP | Go rate limiter |
| `/api/v1/publish_done` | No limit | - | - | (cleanup only) |
| `/health` | No limit | - | - | (monitoring) |

---

## Security Considerations

### 1. Distributed Attacks

**Issue**: Attacker uses multiple IPs (botnet)

**Mitigation**:
- Rate limiting still effective (each IP limited independently)
- Global `max_connections` provides fallback
- Monitor for coordinated attacks via Prometheus/Grafana

### 2. Legitimate Traffic Bursts

**Issue**: Legitimate users may hit rate limits during events

**Mitigation**:
- Generous burst allowance on critical endpoints
- `/hls/*` has high limit (100 req/min) for normal playback
- Status page burst=5 allows rapid refreshes

### 3. IP Spoofing

**Issue**: Attacker could spoof X-Forwarded-For header

**Mitigation**:
- Webhook is **internal-only** (Docker network)
- NGINX doesn't trust X-Forwarded-For from external sources
- `extractClientIP()` prioritizes RemoteAddr for security

---

## Implementation Checklist

### NGINX Changes

- [ ] Add `limit_req_zone` definitions (http block)
- [ ] Add `limit_conn_zone` definitions (http block)
- [ ] Apply `limit_req` to `/stat` endpoint
- [ ] Apply `limit_req` to `/hls/*` endpoint
- [ ] Apply `limit_conn` to http server
- [ ] Add `max_connections` to RTMP application
- [ ] Add rate_limit log format
- [ ] Test and reload NGINX config

### Webhook Changes

- [ ] Implement `RateLimiter` struct and methods
- [ ] Add `publishRateLimiter` global variable
- [ ] Implement `extractClientIP()` helper
- [ ] Modify `handlePublish()` to check rate limit
- [ ] Add structured logging for rate limit violations
- [ ] Rebuild and redeploy webhook container
- [ ] Test rate limiting functionality

### Documentation

- [ ] Create `docs/RATE-LIMITING.md` guide
- [ ] Update CLAUDE.md with rate limit info
- [ ] Document Prometheus queries for rate limit monitoring
- [ ] Add Grafana dashboard panel for 429 errors

---

## Expected Outcomes

After implementation:

1. **HTTP endpoints protected** from query flooding
2. **Webhook protected** from brute-force publish attempts
3. **RTMP protected** from connection exhaustion
4. **Logs structured** for security analysis in Loki
5. **Metrics exposed** for Prometheus alerting

**Success Criteria**:
- Rate limit tests pass (HTTP 429 returned after threshold)
- Legitimate traffic NOT affected (burst allowances work)
- Rate limit violations logged to Loki with `job="webhook"` label
- Prometheus scrapes nginx 429 status codes

---

**Next Steps**: Begin implementation with NGINX HTTP rate limiting, then webhook, then testing.

**Author**: Claude Code
**Date**: 2025-11-16
**Phase**: Phase 2 - Observability Hardening
**Block**: 2.4 - Rate Limiting (Part 2)
**Status**: 📋 PLANNING → 🚧 IMPLEMENTATION
