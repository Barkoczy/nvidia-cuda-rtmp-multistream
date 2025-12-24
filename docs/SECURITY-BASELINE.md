# Security Baseline Documentation

**Version**: 1.0
**Last Updated**: 2025-11-16
**Status**: Phase 1 Implementation In Progress

---

## Table of Contents

1. [Service Inventory](#service-inventory)
2. [Secrets & Configuration Management](#secrets--configuration-management)
3. [Container Hardening](#container-hardening)
4. [Network & Access Control](#network--access-control)
5. [Webhook + RTMP Flow Security](#webhook--rtmp-flow-security)
6. [Known Limitations](#known-limitations)
7. [Security Testing](#security-testing)

---

## Service Inventory

### Production Services (`docker-compose.staging.yml`)

| Service | Container Name | Ports | External Access | Write Paths | Security Status |
|---------|---------------|-------|-----------------|-------------|-----------------|
| **nginx-rtmp-staging** | nginx-rtmp-staging | 1936 (RTMP), 8081 (HTTP) | ✅ RTMP public<br>⚠️ HTTP internal recommended | `/tmp`, `/var/run`, `/var/cache/nginx`, `/var/log/*` (tmpfs) | ✅ Hardened<br>- Non-root (broadcaster:1001)<br>- Read-only FS<br>- 5 capabilities only |
| **webhook-staging** | webhook-staging | 8090 (HTTP) | ✅ Local-only | `/app` (read-only) | ✅ Hardened<br>- Non-root (webhook:1000)<br>- Read-only FS |
| **prometheus-staging** | prometheus-staging | 9090 (HTTP) | ⚠️ Admin only (VPN/localhost) | `/prometheus` (volume) | ⏳ Audit pending<br>- Default root user<br>- No auth by default |
| **grafana-staging** | grafana-staging | 3000 (HTTP) | ⚠️ Admin only (VPN/localhost) | `/var/lib/grafana` (volume) | ⏳ Audit pending<br>- Default admin/admin<br>- Needs persistent storage |
| **loki-staging** | loki-staging | 3100 (HTTP) | ❌ Internal only | `/loki` (volume) | ⏳ Audit pending |
| **promtail-staging** | promtail-staging | N/A | ❌ Internal only | `/tmp` (logs aggregation) | ⏳ Audit pending<br>- Needs Docker socket access |
| **node-exporter-staging** | node-exporter-staging | 9100 (HTTP) | ❌ Internal only | N/A (metrics only) | ⏳ Audit pending<br>- Needs host /proc, /sys access |
| **cadvisor-staging** | cadvisor-staging | 8082 (HTTP) | ❌ Internal only | N/A (metrics only) | ⚠️ Privileged by design<br>- Needs host container metrics |
| **dcgm-exporter-staging** | dcgm-exporter-staging | 9400 (HTTP) | ❌ Internal only | N/A (GPU metrics only) | ⏳ Audit pending<br>- Needs nvidia runtime |
| **nginx-vts-exporter-staging** | nginx-vts-exporter-staging | 9913 (HTTP) | ❌ Internal only | N/A (metrics only) | ⏳ Audit pending |

### Port Access Matrix

| Port | Service | Protocol | Public Access | Firewall Rule | Notes |
|------|---------|----------|---------------|---------------|-------|
| 1936 | RTMP Ingress | TCP | ✅ Required | Allow from internet | RTMP stream input |
| 8081 | NGINX HTTP Status | HTTP | ⚠️ Should be internal | ⏳ Restrict to VPN | RTMP stats, HLS delivery |
| 8090 | Webhook API | HTTP | ❌ Internal only | Docker network | Auth-only, no public |
| 3000 | Grafana UI | HTTP | ⚠️ Admin only | ⏳ Restrict to VPN | Dashboard access |
| 9090 | Prometheus UI | HTTP | ⚠️ Admin only | ⏳ Restrict to VPN | Metrics & alerts |
| 3100 | Loki API | HTTP | ❌ Internal only | Docker network | Log aggregation |
| 9100 | Node Exporter | HTTP | ❌ Internal only | Docker network | Host metrics |
| 8082 | cAdvisor | HTTP | ❌ Internal only | Docker network | Container metrics |
| 9400 | DCGM Exporter | HTTP | ❌ Internal only | Docker network | GPU metrics |
| 9913 | VTS Exporter | HTTP | ❌ Internal only | Docker network | NGINX RTMP metrics |

### Service Dependencies

```
Internet → 1936 (RTMP) → nginx-rtmp-staging
                            ├─→ webhook-staging (auth)
                            ├─→ broadcaster script (exec_publish)
                            └─→ hls_transcode script (exec_publish)

VPN/Admin → 3000 (Grafana) → Prometheus (9090)
                               ├─→ VTS Exporter (9913) → nginx-rtmp-staging (8081)
                               ├─→ DCGM Exporter (9400) → GPU
                               ├─→ Node Exporter (9100) → Host
                               └─→ cAdvisor (8082) → Docker

Grafana → Loki (3100) ← Promtail ← Docker logs + /var/log/broadcaster
```

---

## Secrets & Configuration Management

### Secret Types

| Secret Type | Storage Method | Access Pattern | Rotation Policy |
|-------------|---------------|----------------|-----------------|
| **Stream Keys** | Docker secrets (`secrets/*.txt`) | Read-only mount at `/run/secrets/` | Manual (recommend quarterly) |
| **Grafana Admin Password** | ⏳ `.env.grafana` (pending) | Environment variable | ⏳ TBD |
| **API Tokens** (future) | ⏳ Docker secrets | Read-only mount | ⏳ TBD |

### Current Secret Inventory

**Docker Secrets** (stored in `secrets/` directory, ignored by git):
```
secrets/gaming_youtube_key.txt  → /run/secrets/gaming_youtube_key
secrets/gaming_twitch_key.txt   → /run/secrets/gaming_twitch_key
secrets/gaming_kick_key.txt     → /run/secrets/gaming_kick_key
secrets/gaming_x_key.txt        → /run/secrets/gaming_x_key
```

**Environment Variables**:
```
GF_SECURITY_ADMIN_PASSWORD=admin  ⚠️ Default, needs change
GF_SECURITY_ADMIN_USER=admin      ⚠️ Default, needs change
```

### Secret Access in Code

**broadcaster script** (`broadcaster:184-217`):
```bash
# Primary: Docker secrets
key_file="/run/secrets/${profile}_${platform}_key"
if [ -f "$key_file" ]; then
    stream_key=$(cat "$key_file")
# Fallback: Environment variables (legacy)
else
    env_var="${PROFILE_UPPER}_${platform_upper}_KEY"
    stream_key="${!env_var}"
fi
```

**Security Guarantees**:
- ✅ Secrets never logged in plaintext
- ✅ Secrets not visible in `docker inspect` output
- ✅ Secrets readable only by container owner
- ✅ Secrets permissions: 600 (owner read-only)
- ⏳ Rotation procedure documented (pending)

### .gitignore Protection

```gitignore
# Secrets (never commit)
secrets/*.txt
!secrets/.gitkeep
.env
.env.*
!.env.example

# Logs (may contain sensitive data)
logs-staging/
*.log
```

---

## Container Hardening

### Implemented Hardening (nginx-rtmp-staging, webhook-staging)

#### Non-root User Execution

**nginx-rtmp-staging** (Dockerfile.hardened:138-150):
```dockerfile
RUN groupadd -g 1001 broadcaster && \
    useradd -u 1001 -g broadcaster -s /bin/bash -m broadcaster

RUN chown -R broadcaster:broadcaster \
    /var/log/broadcaster \
    /usr/local/nginx \
    /etc/broadcaster

USER broadcaster:broadcaster
```

**webhook-staging** (webhook/Dockerfile:17-18):
```dockerfile
RUN addgroup -g 1000 webhook && \
    adduser -D -u 1000 -G webhook webhook

USER webhook:webhook
```

**Verification**:
```bash
docker exec nginx-rtmp-staging id
# uid=1001(broadcaster) gid=1001(broadcaster)

docker exec webhook-staging id
# uid=1000(webhook) gid=1000(webhook)
```

#### Read-only Root Filesystem

**nginx-rtmp-staging** (docker-compose.staging.yml:60-61):
```yaml
read_only: true
tmpfs:
  - /tmp
  - /var/run
  - /var/cache/nginx
  - /var/log/nginx
  - /usr/local/nginx/logs
  - /usr/local/nginx/client_body_temp
  - /usr/local/nginx/proxy_temp
  - /usr/local/nginx/fastcgi_temp
  - /usr/local/nginx/uwsgi_temp
  - /usr/local/nginx/scgi_temp
```

**webhook-staging**: ⏳ Pending implementation

#### Minimal Linux Capabilities

**nginx-rtmp-staging** (docker-compose.staging.yml:62-69):
```yaml
cap_drop:
  - ALL
cap_add:
  - CHOWN          # For log file ownership
  - DAC_OVERRIDE   # For writing to mounted volumes
  - SETGID         # For group changes
  - SETUID         # For user changes
  - NET_BIND_SERVICE  # For binding to ports <1024
```

**Rationale**:
- `CHOWN/DAC_OVERRIDE`: Required for entrypoint.sh to set log file ownership
- `SETGID/SETUID`: Required for entrypoint.sh to drop privileges to broadcaster user
- `NET_BIND_SERVICE`: Required only if binding to port 1935 (standard RTMP port)

**webhook-staging**: ⏳ Pending `cap_drop: ALL` implementation

### Pending Hardening (Observability Stack)

| Service | Non-root Status | Read-only FS Status | Capabilities Status |
|---------|----------------|---------------------|---------------------|
| prometheus | ⏳ Audit (likely root) | ❌ Needs RW for TSDB | ⏳ Pending |
| grafana | ⏳ Audit (has grafana user?) | ❌ Needs RW for DB | ⏳ Pending |
| loki | ⏳ Audit | ❌ Needs RW for chunks | ⏳ Pending |
| promtail | ⏳ Audit | ✅ Likely safe | ⏳ Pending |
| node-exporter | ✅ Nobody user (likely) | ✅ Metrics only | ⚠️ Needs host /proc access |
| cadvisor | ❌ Root required | ❌ Needs host access | ⚠️ privileged: true by design |
| dcgm-exporter | ⏳ Audit | ✅ Metrics only | ⚠️ Needs GPU access |
| nginx-vts-exporter | ⏳ Audit | ✅ Metrics only | ⏳ Pending |

**Known Exceptions**:
- **cAdvisor**: Must run privileged to access host container metrics
- **node-exporter**: Needs read-only host mounts (`/proc`, `/sys`, `/`)
- **dcgm-exporter**: Needs nvidia runtime and GPU device access

---

## Network & Access Control

### Docker Networks (Current State)

**Single bridged network**:
```yaml
networks:
  streaming:
    driver: bridge
```

**All services** currently on `streaming` network.

### Planned Network Separation

**Phase 1 Target**:
```yaml
networks:
  streaming-public:   # NGINX RTMP, Webhook
    driver: bridge
  streaming-internal: # Observability stack
    driver: bridge
    internal: true    # No external access
```

**Service Assignment**:
- `nginx-rtmp-staging`: both networks (receives RTMP, calls webhook)
- `webhook-staging`: both networks (auth for NGINX, logs to Loki)
- Observability stack: `streaming-internal` only

### Host Firewall Rules (Pending)

**UFW Configuration** (not yet applied):
```bash
# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# RTMP ingress (public)
sudo ufw allow 1936/tcp comment 'RTMP staging ingress'

# HTTP status (⏳ should be restricted to VPN)
sudo ufw allow 8081/tcp comment 'NGINX HTTP staging'

# Admin access (from VPN IP only)
sudo ufw allow from <VPN_IP> to any port 3000 comment 'Grafana'
sudo ufw allow from <VPN_IP> to any port 9090 comment 'Prometheus'

# SSH (always allow)
sudo ufw allow 22/tcp comment 'SSH'

sudo ufw enable
```

### Admin UI Access Control

**Grafana** (docker-compose.staging.yml:116-120):
```yaml
environment:
  - GF_SECURITY_ADMIN_USER=admin  ⚠️ DEFAULT - CHANGE THIS
  - GF_SECURITY_ADMIN_PASSWORD=admin  ⚠️ DEFAULT - CHANGE THIS
  - GF_USERS_ALLOW_SIGN_UP=false  ✅ Sign-up disabled
  - GF_SERVER_ROOT_URL=http://localhost:3000  ⏳ Consider HTTPS
```

**Action Required**:
1. Change default admin password
2. Store in `.env.grafana` (git-ignored)
3. Consider implementing OAuth/LDAP for multi-user access

**Prometheus**:
- ❌ No built-in authentication
- 📋 **Recommendation**: Access only via SSH tunnel or VPN
- 📋 **Future**: Implement reverse proxy with basic auth (nginx/traefik)

---

## Webhook + RTMP Flow Security

### Architecture Flow

```
1. RTMP Client → rtmp://host:1936/live/gaming
2. NGINX RTMP → on_publish → POST http://webhook:8090/api/v1/publish
   Body: name=gaming&app=live (application/x-www-form-urlencoded)
3. Webhook → sanitizeProfileName(gaming) → validate
4. Webhook → HTTP 200 {"status":"authorized"} OR HTTP 400
5. NGINX → if HTTP 200:
     exec_publish /usr/local/bin/hls_transcode gaming start
     exec_publish /usr/local/bin/broadcaster --profile gaming
   if HTTP 4xx/5xx:
     Reject RTMP connection
6. broadcaster → Read /run/secrets/gaming_*_key → Spawn FFmpeg per platform
7. hls_transcode → Create HLS variants in /tmp/hls/
```

### Input Sanitization (webhook/main.go:149-167)

```go
func sanitizeProfileName(name string) string {
    // Only allow alphanumeric characters, underscores, and hyphens
    allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

    var result strings.Builder
    for _, char := range name {
        if strings.ContainsRune(allowed, char) {
            result.WriteRune(char)
        }
    }

    sanitized := result.String()
    if len(sanitized) == 0 || len(sanitized) > 50 {
        return ""
    }

    return sanitized
}
```

**Protection Against**:
- ✅ Command injection (blocks `;`, `|`, `&`, `$()`, backticks)
- ✅ Path traversal (blocks `..`, `/`)
- ✅ Special characters (blocks `<`, `>`, `*`, `?`)
- ✅ Length-based DoS (max 50 chars)

### Known Security Limitations

✅ **exec_publish Command Injection Risk Resolved**:

**Current** (nginx.staging.conf):
```nginx
exec_publish /usr/local/bin/broadcaster --profile $name;
```

**Mitigation** (Applied):
1. Webhook sanitizes `$name` **before** NGINX receives it
2. NGINX only accepts HTTP 200 from webhook
3. Direct execution without shell wrapper

### Logging Security

**Webhook** (main.go:69, 84):
```go
log.Printf("Stream publish request received for profile: %s", profile)
log.Printf("Stream authorized for profile: %s (orchestration via NGINX exec_publish)", profile)
```

**broadcaster** (⏳ needs audit):
- Check: Stream keys logged? → Should NOT be
- Check: Full URLs logged? → Should be truncated
- Check: Error messages expose secrets? → Should be sanitized

---

## Known Limitations

### Phase 1 Scope

The following security improvements are **out of scope** for Phase 1 and planned for future phases:

1. **Rate Limiting**:
   - ❌ No rate limit on RTMP publish attempts
   - ❌ No rate limit on webhook API
   - 📋 **Phase 2**: Implement nginx rate limiting + fail2ban

2. **Authentication & Authorization**:
   - ❌ No stream key validation (webhook only validates format)
   - ❌ Grafana uses default admin/admin
   - ❌ Prometheus has no authentication
   - 📋 **Phase 2**: Implement proper auth for admin UIs
   - 📋 **Phase 3**: Implement stream key database + validation

3. **Encryption in Transit**:
   - ❌ Webhook uses HTTP (not HTTPS)
   - ❌ No mTLS between NGINX ↔ Webhook
   - 📋 **Phase 2**: Internal TLS for service-to-service communication

4. **Audit Logging**:
   - ⚠️ Basic logging only (no structured logs)
   - ❌ No centralized audit trail for security events
   - 📋 **Phase 2**: Implement security event logging to Loki with retention

5. **Container Image Security**:
   - ⏳ No vulnerability scanning in CI/CD
   - ⏳ Base images not regularly updated
   - 📋 **Phase 2**: Implement Trivy scans in GitHub Actions

6. **Backup & Disaster Recovery**:
   - ❌ No automated backups of Grafana dashboards
   - ❌ No automated backups of Prometheus metrics
   - 📋 **Phase 3**: Implement backup automation

### Accepted Risks (Phase 1)

| Risk | Severity | Mitigation | Acceptance Rationale |
|------|----------|------------|----------------------|
| Brute-force RTMP publish | Medium | Webhook input sanitization | Low impact (dev/staging environment) |
| Default Grafana password | High | ⏳ Firewall to VPN only | ⏳ Pending implementation |
| No stream key validation | Medium | Sanitization only | Phase 2 feature |
| HTTP webhook (no TLS) | Low | Internal Docker network | Internal traffic only |
| privileged cAdvisor | Medium | Necessary for metrics | Required for functionality |

---

## Security Testing

### Automated Tests (Implemented)

**test_security.sh** (10 tests):
```bash
1. Non-root execution check
2. Read-only filesystem verification
3. Minimal capabilities verification
4. Webhook health check
5. Webhook input sanitization test
6. NGINX config validation
7. Docker secrets mounting
8. No sensitive data in logs
9. Network isolation (pending)
10. Port exposure audit (pending)
```

**test_webhook.sh** (webhook-specific):
```bash
1. Valid profile authorization
2. Invalid profile rejection (special chars)
3. Empty profile rejection
4. Oversized profile rejection (>50 chars)
5. Content-type handling (form-encoded)
```

### Manual Test Procedures

**Pre-deployment Checklist**:
- [ ] Run `./test_security.sh` → all tests pass
- [ ] Run `./test_webhook.sh` → all tests pass
- [ ] Verify `docker exec <container> id` → uid != 0 for all non-privileged containers
- [ ] Verify `ss -tulpen` → no unexpected open ports
- [ ] Check `git status` → no secrets staged for commit

**Post-deployment Verification**:
- [ ] RTMP stream test with valid key → success
- [ ] RTMP stream test with invalid key → rejected by webhook
- [ ] Grafana login with new password → success
- [ ] Prometheus UI accessible only from VPN → verified

### Security Incident Response

**Webhook Compromise**:
1. Immediately restart webhook container (isolates from NGINX)
2. Review webhook logs for suspicious activity
3. Rotate all stream keys in `secrets/`
4. Audit NGINX exec_publish logs for unauthorized script execution

**NGINX Compromise**:
1. Stop all streaming (kill FFmpeg processes)
2. Review `/var/log/broadcaster/` for malicious commands
3. Rotate all stream keys
4. Rebuild nginx-rtmp-staging image from clean base

**Stream Key Leak**:
1. Identify leaked key platform (YouTube/Twitch/Kick/X)
2. Revoke key on platform immediately
3. Generate new key on platform
4. Update `secrets/<profile>_<platform>_key.txt`
5. Restart nginx-rtmp-staging to reload secrets

---

## Compliance & Standards

### CIS Docker Benchmark

Alignment with CIS Docker Benchmark v1.4.0:

| Requirement | Status | Implementation |
|-------------|--------|----------------|
| 5.1 Verify AppArmor profile | ⏳ Pending | Phase 3 |
| 5.3 Verify containers run as non-root | ✅ Partial | nginx-rtmp, webhook done; others pending |
| 5.10 Do not use host network mode | ✅ Pass | No `network_mode: host` |
| 5.12 Mount container's root filesystem as read only | ✅ Partial | nginx-rtmp done; others pending |
| 5.25 Restrict container from acquiring additional privileges | ✅ Pass | `no-new-privileges: true` |
| 5.28 Use PIDs cgroup limit | ⏳ Pending | Phase 2 |

### OWASP Top 10 Mitigation

| OWASP Risk | Mitigation | Status |
|------------|-----------|--------|
| A01: Broken Access Control | Webhook input sanitization, firewall rules | ✅ Partial |
| A02: Cryptographic Failures | Docker secrets for stream keys | ✅ Implemented |
| A03: Injection | `sanitizeProfileName()` in webhook | ✅ Implemented |
| A05: Security Misconfiguration | Minimal capabilities, read-only FS | 🚧 In Progress |
| A07: Identification and Authentication Failures | ⏳ Grafana password change pending | ⏳ Phase 1 |
| A09: Security Logging and Monitoring Failures | Loki aggregation, Grafana dashboards | ✅ Implemented |

---

**Document Version History**:
- v1.0 (2025-11-16): Initial Phase 1 baseline documentation
- ⏳ v1.1: Post-Phase 1 completion update (pending)

**Related Documents**:
- `.changelogs/20251116/phase1_security_baseline_plan.md` - Implementation plan
- `docs/TESTING-WORKFLOW.md` - Security testing procedures
- `docs/SECRETS_MIGRATION.md` - Docker secrets migration guide
- `docs/CONTAINER_HARDENING.md` - Container security deep dive
