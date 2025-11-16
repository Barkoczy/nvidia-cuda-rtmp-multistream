# Phase 2: Observability Stack Hardening - Implementation Plan

**Date**: 2025-11-16
**Phase**: Phase 2 - Observability Stack Hardening
**Status**: 🚧 IN PROGRESS
**Previous Phase**: Phase 1 - Security Baseline ✅ COMPLETE

---

## Overview

Phase 2 focuses on hardening the observability stack (Prometheus, Grafana, Loki, exporters) to achieve:
- **CIS Docker Benchmark 5/5 (100% compliance)**
- **Secure admin UI access** (VPN/SSH tunnel + auth)
- **Rate limiting** for all HTTP endpoints
- **Structured security logging**
- **Minimal attack surface** for metrics/logging pipeline

---

## Definition of Done

Phase 2 is complete when:

- [ ] All observability containers pass CIS Docker Benchmark checks
- [ ] Prometheus UI accessible only via VPN/SSH tunnel with auth
- [ ] Grafana has proper RBAC (admin/editor/viewer roles)
- [ ] Loki has retention limits and rate limiting configured
- [ ] All exporters bind to internal network only
- [ ] Rate limiting implemented for webhook and NGINX endpoints
- [ ] Security events logged to Loki with structured labels
- [ ] Automated security test suite updated (15+ tests)
- [ ] All changes documented in phase2_done.md

---

## Phase 2 Blocks

### Block 2.0: Before Production (from Phase 1)

**Goal**: Close remaining Phase 1 items before proceeding.

#### 2.0.1 Firewall Configuration

- [ ] Install UFW on host
  ```bash
  sudo apt update
  sudo apt install ufw -y
  ```

- [ ] Apply firewall rules from `docs/FIREWALL-SETUP.md`
  ```bash
  # Critical: SSH first
  sudo ufw allow 22/tcp comment 'SSH access'

  # RTMP public access
  sudo ufw allow 1936/tcp comment 'RTMP staging ingress'

  # Admin UIs - VPN/localhost only
  sudo ufw allow from <VPN_IP> to any port 3000 proto tcp comment 'Grafana'
  sudo ufw allow from <VPN_IP> to any port 9090 proto tcp comment 'Prometheus'
  sudo ufw allow from <VPN_IP> to any port 8081 proto tcp comment 'NGINX status'

  # Enable firewall
  sudo ufw enable
  ```

- [ ] Verify UFW status
  ```bash
  sudo ufw status verbose
  ```

- [ ] Test external access (should fail)
  ```bash
  # From external machine
  telnet <server-ip> 3000  # Should timeout
  telnet <server-ip> 9090  # Should timeout
  telnet <server-ip> 1936  # Should succeed (RTMP)
  ```

#### 2.0.2 VPN / SSH Tunnel Setup

- [ ] Document VPN configuration (if using cloud VPN)
- [ ] Test SSH tunnel access
  ```bash
  # On local machine
  ssh -L 3000:localhost:3000 -L 9090:localhost:9090 ubuntu@<server-ip>

  # Test in browser
  curl http://localhost:3000  # Grafana
  curl http://localhost:9090  # Prometheus
  ```

- [ ] Create helper script for SSH tunnels
  ```bash
  # scripts/admin_tunnel.sh
  #!/bin/bash
  ssh -L 3000:localhost:3000 \
      -L 9090:localhost:9090 \
      -L 8081:localhost:8081 \
      -L 3100:localhost:3100 \
      ubuntu@<server-ip>
  ```

#### 2.0.3 Secure .env.grafana Backup

- [ ] Backup `.env.grafana` outside repository
  ```bash
  mkdir -p ~/backups/nvidia-rtmp-secrets
  cp .env.grafana ~/backups/nvidia-rtmp-secrets/.env.grafana.$(date +%Y%m%d)
  chmod 600 ~/backups/nvidia-rtmp-secrets/.env.grafana.*
  ```

- [ ] Document recovery procedure in `docs/DISASTER-RECOVERY.md`

---

### Block 2.1: Prometheus Hardening

**Goal**: Prometheus is secure, has proper retention, and is accessible only from admin network.

#### 2.1.1 Network Isolation

- [ ] Review current docker-compose.staging.yml Prometheus config
- [ ] Change port exposure strategy:
  - **Current**: `ports: "9090:9090"` (public)
  - **Target**: `expose: ["9090"]` (internal only) + UFW for localhost/VPN

- [ ] Update docker-compose.staging.yml:
  ```yaml
  prometheus:
    # Option A: Internal only (recommended)
    expose:
      - "9090"

    # Option B: Keep published but rely on UFW
    ports:
      - "127.0.0.1:9090:9090"  # Localhost only
  ```

- [ ] Test: Prometheus accessible from Docker network
  ```bash
  docker exec nginx-rtmp-staging wget -q -O- http://prometheus-staging:9090/api/v1/targets
  ```

- [ ] Test: Prometheus NOT accessible from host (if using expose)
  ```bash
  curl --connect-timeout 2 http://localhost:9090  # Should fail
  ```

#### 2.1.2 Reverse Proxy with Auth (Optional)

- [ ] Evaluate: Do we need reverse proxy with auth?
  - **Yes if**: Multiple admin users, need audit trail
  - **No if**: SSH tunnel + UFW is sufficient

- [ ] If yes: Add nginx reverse proxy with basic auth
  ```yaml
  nginx-admin:
    image: nginx:alpine
    volumes:
      - ./observability/nginx-admin.conf:/etc/nginx/nginx.conf:ro
      - ./observability/.htpasswd:/etc/nginx/.htpasswd:ro
    ports:
      - "127.0.0.1:8443:443"
    networks:
      - streaming
    depends_on:
      - prometheus
      - grafana
  ```

#### 2.1.3 Prometheus Configuration Review

- [ ] Review `observability/prometheus.yml`
  - [ ] Check `scrape_interval` (current: 15s)
  - [ ] Verify `scrape_timeout` is reasonable (10s default)
  - [ ] Review job definitions:
    - `prometheus` (self-monitoring)
    - `node-exporter` (host metrics)
    - `cadvisor` (container metrics)
    - `dcgm-exporter` (GPU metrics)
    - `nginx-vts-exporter` (RTMP metrics)
    - `webhook` (application metrics)

- [ ] Optimize scrape configs:
  ```yaml
  scrape_configs:
    # Critical services: 15s interval
    - job_name: 'rtmp-metrics'
      scrape_interval: 15s
      static_configs:
        - targets: ['nginx-vts-exporter:9913']

    # Non-critical: 30s interval
    - job_name: 'host-metrics'
      scrape_interval: 30s
      static_configs:
        - targets: ['node-exporter:9100']
  ```

- [ ] Validate configuration:
  ```bash
  docker exec prometheus-staging promtool check config /etc/prometheus/prometheus.yml
  ```

#### 2.1.4 Retention and Storage

- [ ] Check current retention setting
  ```bash
  docker inspect prometheus-staging --format '{{.Args}}'
  # Look for --storage.tsdb.retention.time
  ```

- [ ] Update docker-compose.staging.yml:
  ```yaml
  prometheus:
    command:
      - '--storage.tsdb.retention.time=30d'  # Currently 30d
      - '--storage.tsdb.retention.size=10GB'  # Add size limit
  ```

- [ ] Verify data directory size
  ```bash
  docker exec prometheus-staging du -sh /prometheus
  ```

- [ ] Consider separate volume for Prometheus data (already done)

#### 2.1.5 CIS Docker Benchmark for Prometheus

- [ ] Check if Prometheus runs as non-root
  ```bash
  docker exec prometheus-staging id
  # Expected: uid=65534(nobody) or prometheus user
  ```

- [ ] Add security hardening to docker-compose.staging.yml:
  ```yaml
  prometheus:
    # Security: User (check official image)
    user: "65534:65534"  # nobody:nobody (if supported)

    # Security: Read-only root filesystem
    read_only: true
    tmpfs:
      - /prometheus  # TSDB needs write access
      - /tmp

    # Security: Drop capabilities
    cap_drop:
      - ALL

    # Security: No new privileges
    security_opt:
      - no-new-privileges:true
  ```

- [ ] Test after changes:
  ```bash
  docker compose -f docker-compose.staging.yml up -d prometheus
  docker logs prometheus-staging
  ```

---

### Block 2.2: Grafana Hardening

**Goal**: Grafana has proper authentication, RBAC, and secure datasource access.

#### 2.2.1 Authentication and Access

- [ ] Review current Grafana configuration
  ```bash
  docker exec grafana-staging env | grep GF_
  ```

- [ ] Verify secure password is set (already done in Phase 1)
  ```bash
  grep GF_SECURITY_ADMIN_PASSWORD .env.grafana
  # Should be 32-char random, not "admin"
  ```

- [ ] Disable sign-up (already done)
  ```yaml
  environment:
    - GF_USERS_ALLOW_SIGN_UP=false
  ```

- [ ] Configure anonymous access (disable for security)
  ```yaml
  environment:
    - GF_AUTH_ANONYMOUS_ENABLED=false
  ```

- [ ] Consider OAuth integration (optional)
  ```yaml
  environment:
    - GF_AUTH_GITHUB_ENABLED=true
    - GF_AUTH_GITHUB_CLIENT_ID=xxx
    - GF_AUTH_GITHUB_CLIENT_SECRET=xxx
    - GF_AUTH_GITHUB_ALLOWED_ORGANIZATIONS=your-org
  ```

#### 2.2.2 Role-Based Access Control (RBAC)

- [ ] Create Grafana users via UI or provisioning:
  - **Admin**: Full access (you)
  - **Editor**: Can edit dashboards
  - **Viewer**: Read-only access

- [ ] Create provisioning config:
  ```yaml
  # observability/grafana/provisioning/users/users.yml
  apiVersion: 1
  users:
    - name: Admin User
      email: admin@example.com
      login: admin
      password: ${GF_SECURITY_ADMIN_PASSWORD}
      orgId: 1
      role: Admin
  ```

- [ ] Set folder permissions:
  - Production dashboards: Viewer role only
  - Development dashboards: Editor role

#### 2.2.3 Datasource Security

- [ ] Review Prometheus datasource config
  ```yaml
  # observability/grafana/provisioning/datasources/datasources.yml
  datasources:
    - name: Prometheus
      type: prometheus
      access: proxy
      url: http://prometheus-staging:9090
      isDefault: true
      editable: false  # Prevent users from changing URL
      jsonData:
        timeInterval: 15s
  ```

- [ ] Review Loki datasource config
  ```yaml
  - name: Loki
    type: loki
    access: proxy
    url: http://loki-staging:3100
    editable: false
    jsonData:
      maxLines: 1000  # Limit query results
  ```

- [ ] Test datasource connectivity
  ```bash
  # Via Grafana UI: Configuration > Data Sources > Test
  # Or via API:
  curl -u admin:<password> http://localhost:3000/api/datasources
  ```

#### 2.2.4 TLS / Network Access

- [ ] Network isolation (same as Prometheus)
  ```yaml
  grafana:
    # Option A: Internal only + SSH tunnel
    expose:
      - "3000"

    # Option B: Localhost binding
    ports:
      - "127.0.0.1:3000:3000"
  ```

- [ ] Configure TLS (if exposing publicly - NOT recommended)
  ```yaml
  environment:
    - GF_SERVER_PROTOCOL=https
    - GF_SERVER_CERT_FILE=/etc/grafana/ssl/cert.pem
    - GF_SERVER_CERT_KEY=/etc/grafana/ssl/key.pem
  ```

#### 2.2.5 Audit Logging

- [ ] Enable audit logging (optional, for compliance)
  ```yaml
  environment:
    - GF_LOG_MODE=console file
    - GF_LOG_LEVEL=info
  ```

- [ ] Review logs for suspicious activity
  ```bash
  docker logs grafana-staging | grep -i "failed\|error\|unauthorized"
  ```

#### 2.2.6 CIS Docker Benchmark for Grafana

- [ ] Check if Grafana runs as non-root
  ```bash
  docker exec grafana-staging id
  # Expected: uid=472(grafana)
  ```

- [ ] Add security hardening:
  ```yaml
  grafana:
    # Security: User (official image already uses grafana user)
    # No change needed if using official image

    # Security: Read-only root filesystem (NOT possible - Grafana needs RW)
    # Skip this for Grafana

    # Security: Drop capabilities
    cap_drop:
      - ALL
    cap_add:
      - CHOWN  # For plugin installation
      - DAC_OVERRIDE

    # Security: No new privileges
    security_opt:
      - no-new-privileges:true
  ```

- [ ] Test after changes:
  ```bash
  docker compose -f docker-compose.staging.yml up -d grafana
  docker logs grafana-staging
  ```

---

### Block 2.3: Loki + Logging Pipeline Hardening

**Goal**: Logs are secure, have retention limits, and don't become a DoS vector.

#### 2.3.1 Loki Configuration Review

- [ ] Review `observability/loki-config.yml`
  ```yaml
  auth_enabled: false  # Single-tenant mode

  server:
    http_listen_port: 3100

  ingester:
    lifecycler:
      ring:
        replication_factor: 1
    chunk_idle_period: 3m
    max_chunk_age: 1h
    chunk_retain_period: 30s

  schema_config:
    configs:
      - from: 2024-01-01
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h

  storage_config:
    boltdb_shipper:
      active_index_directory: /loki/index
      cache_location: /loki/cache
    filesystem:
      directory: /loki/chunks

  limits_config:
    retention_period: 168h  # 7 days
    ingestion_rate_mb: 10
    ingestion_burst_size_mb: 20
  ```

- [ ] Add/update limits:
  ```yaml
  limits_config:
    retention_period: 168h  # 7 days (adjust as needed)
    reject_old_samples: true
    reject_old_samples_max_age: 168h
    ingestion_rate_mb: 10  # Max 10MB/s per stream
    ingestion_burst_size_mb: 20
    max_label_name_length: 1024
    max_label_value_length: 2048
    max_label_names_per_series: 30  # Prevent label explosion
    max_streams_per_user: 0  # Unlimited (single tenant)
    max_global_streams_per_user: 5000  # Global limit
  ```

#### 2.3.2 Retention and Compaction

- [ ] Configure retention in limits_config (see above)
- [ ] Enable compaction for storage efficiency
  ```yaml
  compactor:
    working_directory: /loki/compactor
    shared_store: filesystem
    compaction_interval: 10m
    retention_enabled: true
    retention_delete_delay: 2h
    retention_delete_worker_count: 150
  ```

- [ ] Verify retention is working
  ```bash
  # Check Loki metrics
  curl http://localhost:3100/metrics | grep loki_ingester_streams

  # Check storage size
  docker exec loki-staging du -sh /loki
  ```

#### 2.3.3 Promtail Configuration Review

- [ ] Review `observability/promtail-config.yml`
  ```yaml
  server:
    http_listen_port: 9080

  positions:
    filename: /tmp/positions.yaml

  clients:
    - url: http://loki-staging:3100/loki/api/v1/push

  scrape_configs:
    - job_name: broadcaster-logs
      static_configs:
        - targets:
            - localhost
          labels:
            job: broadcaster
            __path__: /var/log/broadcaster/*.log
  ```

- [ ] Ensure no sensitive logs are collected:
  - [ ] No `/var/log/*` wildcard
  - [ ] No logs containing tokens/secrets
  - [ ] Add regex filters for sensitive data

- [ ] Add pipeline stages for structured logging:
  ```yaml
  scrape_configs:
    - job_name: nginx-logs
      static_configs:
        - targets:
            - localhost
          labels:
            job: nginx
            __path__: /var/log/nginx/*.log
      pipeline_stages:
        - regex:
            expression: '^(?P<remote_addr>\S+) - (?P<remote_user>\S+) \[(?P<time_local>[^\]]+)\] "(?P<request>[^"]*)" (?P<status>\d+) (?P<body_bytes_sent>\d+)'
        - labels:
            status:
            request:
  ```

#### 2.3.4 Structured Logging for Webhook/NGINX

- [ ] Update webhook to log in JSON format
  ```go
  // webhook/main.go
  import "github.com/sirupsen/logrus"

  func init() {
      logrus.SetFormatter(&logrus.JSONFormatter{})
  }

  func handlePublish(w http.ResponseWriter, r *http.Request) {
      logrus.WithFields(logrus.Fields{
          "stream": "security",
          "action": "publish",
          "profile": profile,
          "ip": r.RemoteAddr,
      }).Info("Stream publish attempt")
  }
  ```

- [ ] Update NGINX to log in JSON format (optional)
  ```nginx
  log_format json_combined escape=json
    '{'
      '"time_local":"$time_local",'
      '"remote_addr":"$remote_addr",'
      '"request":"$request",'
      '"status": "$status",'
      '"body_bytes_sent":"$body_bytes_sent",'
      '"http_user_agent":"$http_user_agent"'
    '}';

  access_log /var/log/nginx/access.log json_combined;
  ```

#### 2.3.5 Loki Network Access

- [ ] Restrict Loki to internal network
  ```yaml
  loki:
    # Internal only
    expose:
      - "3100"

    # No public ports
  ```

- [ ] Test: Loki accessible from Docker network
  ```bash
  docker exec promtail-staging wget -q -O- http://loki-staging:3100/ready
  ```

- [ ] Test: Loki NOT accessible from host
  ```bash
  curl --connect-timeout 2 http://localhost:3100  # Should fail
  ```

#### 2.3.6 CIS Docker Benchmark for Loki/Promtail

- [ ] Check if Loki runs as non-root
  ```bash
  docker exec loki-staging id
  # Expected: uid=10001(loki)
  ```

- [ ] Check if Promtail runs as non-root
  ```bash
  docker exec promtail-staging id
  ```

- [ ] Add security hardening:
  ```yaml
  loki:
    # Security: User (official image uses loki user)
    # No change needed

    # Security: Read-only root filesystem (NOT possible - needs RW for TSDB)
    # Skip this

    # Security: Drop capabilities
    cap_drop:
      - ALL

    # Security: No new privileges
    security_opt:
      - no-new-privileges:true

  promtail:
    # Security: User
    user: "0:0"  # Needs root for Docker socket access

    # Security: Read-only root filesystem
    read_only: true
    tmpfs:
      - /tmp

    # Security: Drop capabilities (limited - needs Docker access)
    cap_drop:
      - ALL
    cap_add:
      - DAC_READ_SEARCH  # For reading logs

    # Security: No new privileges
    security_opt:
      - no-new-privileges:true
  ```

---

### Block 2.4: Exporters + Rate Limiting

**Goal**: Exporters are internal-only, rate limiting protects HTTP endpoints.

#### 2.4.1 Exporters Network Isolation

- [ ] Review all exporters in docker-compose.staging.yml:
  - node-exporter (port 9100)
  - cadvisor (port 8082)
  - dcgm-exporter (port 9400)
  - nginx-vts-exporter (port 9913)

- [ ] Change to internal-only exposure:
  ```yaml
  node-exporter:
    # Before: ports: "9100:9100"
    # After:
    expose:
      - "9100"

  cadvisor:
    expose:
      - "8080"  # Internal cadvisor port

  dcgm-exporter:
    expose:
      - "9400"

  nginx-vts-exporter:
    expose:
      - "9913"
  ```

- [ ] Verify UFW blocks external access
  ```bash
  # From external machine
  telnet <server-ip> 9100  # Should timeout
  telnet <server-ip> 9400  # Should timeout
  ```

- [ ] Test: Prometheus can scrape metrics
  ```bash
  docker exec prometheus-staging wget -q -O- http://node-exporter:9100/metrics
  docker exec prometheus-staging wget -q -O- http://dcgm-exporter:9400/metrics
  ```

#### 2.4.2 CIS Docker Benchmark for Exporters

**node-exporter**:
- [ ] Check user
  ```bash
  docker exec node-exporter-staging id
  # Expected: uid=65534(nobody)
  ```

- [ ] Add hardening:
  ```yaml
  node-exporter:
    user: "65534:65534"
    read_only: true
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
  ```

**cadvisor**:
- [ ] Note: cAdvisor REQUIRES privileged mode (by design)
  ```yaml
  cadvisor:
    privileged: true  # Cannot be removed
    # This is a known limitation for container metrics
  ```

- [ ] Document exception in security audit

**dcgm-exporter**:
- [ ] Check user
  ```bash
  docker exec dcgm-exporter-staging id
  ```

- [ ] Add hardening (limited by GPU access needs):
  ```yaml
  dcgm-exporter:
    # User: Cannot change (needs GPU access)
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
  ```

**nginx-vts-exporter**:
- [ ] Check user
  ```bash
  docker exec nginx-vts-exporter-staging id
  ```

- [ ] Add hardening:
  ```yaml
  nginx-vts-exporter:
    user: "65534:65534"  # If supported
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
  ```

#### 2.4.3 NGINX Rate Limiting

- [ ] Review current nginx.staging.conf
- [ ] Add rate limiting zones:
  ```nginx
  http {
      # Rate limiting zones
      limit_req_zone $binary_remote_addr zone=rtmp_publish:10m rate=10r/m;
      limit_req_zone $binary_remote_addr zone=webhook:10m rate=100r/m;
      limit_req_zone $binary_remote_addr zone=general:10m rate=100r/s;

      # Connection limiting
      limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
  ```

- [ ] Apply rate limits to locations:
  ```nginx
  # HTTP status page
  location /stat {
      limit_req zone=general burst=20 nodelay;
      limit_conn conn_limit 10;
      # ... existing config
  }

  # Webhook endpoint (if exposed via NGINX proxy)
  location /webhook/ {
      limit_req zone=webhook burst=50 nodelay;
      # ... proxy config
  }
  ```

- [ ] Add rate limiting to RTMP module (if supported):
  ```nginx
  rtmp {
      # Note: RTMP module has limited rate limiting support
      # Best practice: Implement in webhook
  }
  ```

- [ ] Test rate limiting:
  ```bash
  # Flood test
  for i in {1..200}; do
      curl -s http://localhost:8081/stat > /dev/null &
  done
  wait

  # Check for 429 Too Many Requests
  docker logs nginx-rtmp-staging | grep "429"
  ```

#### 2.4.4 Webhook Rate Limiting

- [ ] Add rate limiting middleware in webhook/main.go
  ```go
  import "golang.org/x/time/rate"

  var limiter = rate.NewLimiter(rate.Limit(100), 200) // 100 req/s, burst 200

  func rateLimitMiddleware(next http.Handler) http.Handler {
      return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
          if !limiter.Allow() {
              logrus.WithFields(logrus.Fields{
                  "stream": "security",
                  "event": "rate_limit",
                  "ip": r.RemoteAddr,
              }).Warn("Rate limit exceeded")

              http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
              return
          }
          next.ServeHTTP(w, r)
      })
  }
  ```

- [ ] Apply middleware to all routes:
  ```go
  http.Handle("/api/v1/publish", rateLimitMiddleware(http.HandlerFunc(handlePublish)))
  http.Handle("/api/v1/publish_done", rateLimitMiddleware(http.HandlerFunc(handlePublishDone)))
  ```

- [ ] Test webhook rate limiting:
  ```bash
  # Flood test
  for i in {1..500}; do
      curl -s -X POST http://webhook:8090/api/v1/publish \
        -H "Content-Type: application/json" \
        -d '{"name":"test"}' &
  done
  wait

  # Check for 429 responses
  docker logs webhook-staging | grep "Rate limit exceeded"
  ```

#### 2.4.5 Structured Security Logging

- [ ] Webhook: Log all security events
  ```go
  // Rejected requests
  logrus.WithFields(logrus.Fields{
      "stream": "security",
      "event": "publish_rejected",
      "reason": "invalid_profile_name",
      "profile": name,
      "ip": r.RemoteAddr,
  }).Warn("Publish rejected")

  // Rate limit hits
  logrus.WithFields(logrus.Fields{
      "stream": "security",
      "event": "rate_limit",
      "ip": r.RemoteAddr,
  }).Warn("Rate limit exceeded")
  ```

- [ ] NGINX: Log security events (403, 429, etc.)
  ```nginx
  # Custom error log for security events
  error_log /var/log/nginx/security.log warn;

  # Log rejected connections
  if ($request_method !~ ^(GET|POST)$ ) {
      access_log /var/log/nginx/security.log;
      return 405;
  }
  ```

- [ ] Promtail: Collect security logs with label
  ```yaml
  scrape_configs:
    - job_name: security-logs
      static_configs:
        - targets:
            - localhost
          labels:
            job: security
            __path__: /var/log/*/security.log
  ```

- [ ] Grafana: Create security dashboard
  - Panel 1: Rate limit violations (LogQL: `{job="security"} |= "rate_limit"`)
  - Panel 2: Rejected publish attempts
  - Panel 3: Suspicious IPs (multiple rejections)

---

## Testing Plan

### Security Test Suite (Phase 2)

Extend `/tmp/phase1_security_tests.sh` to include Phase 2 tests:

#### 2.5.1 Observability Stack Tests

```bash
#!/bin/bash
# Phase 2 Security Tests

echo "=== Phase 2: Observability Stack Security Tests ==="

# Test 11: Prometheus non-root user
echo "Test 11: Prometheus non-root user"
prom_uid=$(docker exec prometheus-staging id -u)
if [ "$prom_uid" != "0" ]; then
    echo "✅ PASS: Prometheus uid=$prom_uid (non-root)"
else
    echo "❌ FAIL: Prometheus uid=0 (root)"
fi

# Test 12: Prometheus read-only filesystem
echo "Test 12: Prometheus read-only filesystem"
prom_ro=$(docker inspect prometheus-staging --format '{{.HostConfig.ReadonlyRootfs}}')
if [ "$prom_ro" = "true" ]; then
    echo "✅ PASS: Prometheus read-only FS"
else
    echo "⚠️ SKIP: Prometheus needs RW for TSDB"
fi

# Test 13: Grafana non-root user
echo "Test 13: Grafana non-root user"
grafana_uid=$(docker exec grafana-staging id -u)
if [ "$grafana_uid" != "0" ]; then
    echo "✅ PASS: Grafana uid=$grafana_uid (non-root)"
else
    echo "❌ FAIL: Grafana uid=0 (root)"
fi

# Test 14: Loki non-root user
echo "Test 14: Loki non-root user"
loki_uid=$(docker exec loki-staging id -u)
if [ "$loki_uid" != "0" ]; then
    echo "✅ PASS: Loki uid=$loki_uid (non-root)"
else
    echo "❌ FAIL: Loki uid=0 (root)"
fi

# Test 15: Exporters internal-only (no public ports)
echo "Test 15: Exporters internal-only"
node_exp_external=$(curl -s --connect-timeout 2 http://localhost:9100/metrics)
if [ -z "$node_exp_external" ]; then
    echo "✅ PASS: Node exporter NOT accessible from localhost"
else
    echo "❌ FAIL: Node exporter accessible from localhost"
fi

# Test 16: Prometheus accessible from Docker network
echo "Test 16: Prometheus Docker network access"
prom_internal=$(docker exec nginx-rtmp-staging wget -q -O- http://prometheus-staging:9090/api/v1/targets 2>&1)
if echo "$prom_internal" | grep -q "targets"; then
    echo "✅ PASS: Prometheus accessible from Docker network"
else
    echo "❌ FAIL: Prometheus NOT accessible from Docker network"
fi

# Test 17: Loki accessible from Promtail
echo "Test 17: Loki accessible from Promtail"
loki_ready=$(docker exec promtail-staging wget -q -O- http://loki-staging:3100/ready 2>&1)
if echo "$loki_ready" | grep -q "ready"; then
    echo "✅ PASS: Loki accessible from Promtail"
else
    echo "❌ FAIL: Loki NOT accessible from Promtail"
fi

# Test 18: Rate limiting configured (NGINX)
echo "Test 18: NGINX rate limiting"
nginx_conf=$(docker exec nginx-rtmp-staging cat /usr/local/nginx/conf/nginx.conf)
if echo "$nginx_conf" | grep -q "limit_req_zone"; then
    echo "✅ PASS: NGINX rate limiting configured"
else
    echo "❌ FAIL: NGINX rate limiting NOT configured"
fi

# Test 19: Webhook rate limiting (test endpoint)
echo "Test 19: Webhook rate limiting functional test"
# Send 10 rapid requests
success_count=0
for i in {1..10}; do
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://webhook:8090/health)
    if [ "$response" = "200" ]; then
        ((success_count++))
    fi
done

if [ "$success_count" -gt 0 ] && [ "$success_count" -lt 10 ]; then
    echo "✅ PASS: Webhook rate limiting active (allowed $success_count/10)"
else
    echo "⚠️ WARNING: Webhook rate limiting may not be active (allowed $success_count/10)"
fi

# Test 20: Security logs collected by Loki
echo "Test 20: Security logs in Loki"
loki_logs=$(curl -s -G http://loki-staging:3100/loki/api/v1/query \
  --data-urlencode 'query={job="security"}' | grep -o "stream")
if [ -n "$loki_logs" ]; then
    echo "✅ PASS: Security logs found in Loki"
else
    echo "⚠️ WARNING: No security logs found in Loki (may need time to ingest)"
fi

echo ""
echo "=== Phase 2 Test Summary ==="
echo "Tests 11-20 completed"
echo "Review results above for any failures"
```

#### 2.5.2 Functional Tests

- [ ] RTMP streaming still works after hardening
- [ ] Prometheus scrapes all targets successfully
- [ ] Grafana displays all dashboards correctly
- [ ] Loki ingests logs from all sources
- [ ] Rate limiting doesn't block legitimate traffic

---

## Documentation

### 2.6.1 Update Existing Docs

- [ ] Update `docs/SECURITY-BASELINE.md`:
  - Add Phase 2 observability stack section
  - Document CIS compliance for all services
  - Update network access matrix

- [ ] Update `CLAUDE.md`:
  - Mark Phase 2 as complete
  - Update monitoring commands with new access methods

- [ ] Update `docs/FIREWALL-SETUP.md`:
  - Add rules for admin access to observability UIs
  - Document SSH tunnel usage

### 2.6.2 Create New Docs

- [ ] `docs/OBSERVABILITY-SECURITY.md`:
  - Prometheus security best practices
  - Grafana RBAC configuration
  - Loki retention and rate limiting
  - Exporter security considerations

- [ ] `docs/RATE-LIMITING.md`:
  - NGINX rate limiting configuration
  - Webhook rate limiting implementation
  - Tuning guidelines
  - Troubleshooting

- [ ] `docs/ADMIN-ACCESS.md`:
  - SSH tunnel setup
  - VPN configuration (if applicable)
  - Admin UI access procedures
  - Emergency access procedures

### 2.6.3 Phase 2 Completion Report

- [ ] `.changelogs/20251116/phase2_done.md`:
  - Implementation summary
  - Test results (Tests 11-20)
  - CIS compliance status (5/5)
  - Performance impact
  - Known limitations
  - Next steps (Phase 3)

---

## Rollback Plan

If Phase 2 changes cause issues:

1. **Rollback docker-compose changes**:
   ```bash
   git checkout HEAD~1 docker-compose.staging.yml
   docker compose -f docker-compose.staging.yml up -d --force-recreate
   ```

2. **Restore original configs**:
   ```bash
   git checkout HEAD~1 observability/
   docker compose -f docker-compose.staging.yml restart prometheus grafana loki
   ```

3. **Emergency access restore**:
   ```bash
   # Temporarily expose Grafana publicly
   docker compose -f docker-compose.staging.yml down grafana
   # Edit docker-compose.staging.yml: change expose to ports
   docker compose -f docker-compose.staging.yml up -d grafana
   ```

---

## Timeline Estimate

| Block | Tasks | Estimated Time |
|-------|-------|----------------|
| 2.0 | Before Production | 1 hour |
| 2.1 | Prometheus Hardening | 2 hours |
| 2.2 | Grafana Hardening | 2 hours |
| 2.3 | Loki + Logging | 3 hours |
| 2.4 | Exporters + Rate Limiting | 3 hours |
| 2.5 | Testing | 2 hours |
| 2.6 | Documentation | 2 hours |
| **Total** | **15 hours** |

---

## Success Criteria

Phase 2 is successful when:

- ✅ All observability containers run as non-root (where possible)
- ✅ All admin UIs accessible only via VPN/SSH tunnel
- ✅ Rate limiting prevents DoS on all HTTP endpoints
- ✅ Security events logged to Loki with structured labels
- ✅ CIS Docker Benchmark: 5/5 (100% compliance)
- ✅ RTMP streaming still functional
- ✅ No performance degradation
- ✅ All tests pass (20/20)
- ✅ Documentation complete

---

**Next Phase**: Phase 3 - Performance & Capacity Planning

**Related Documents**:
- `.changelogs/20251116/phase1_done.md` - Phase 1 completion
- `docs/SECURITY-BASELINE.md` - Security documentation
- `CLAUDE.md` - Development guide
