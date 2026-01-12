# Block 2.0: UFW & VPN/SSH Tunnel - Analysis Report

**Date**: 2025-11-16
**Block**: 2.0 - Before Production (Phase 1 Closure)
**Status**: Planning / Analysis

---

## Executive Summary

**Problem**: Admin services (Grafana, Prometheus, Loki) are currently accessible from the public internet on their published ports. This is a **security risk** - anyone can attempt to access dashboards, even if they need authentication.

**Solution**: Use firewall (UFW) to block public access + SSH tunnels for legitimate admin access.

**Impact**: Zero functional change for RTMP streaming, but admin UIs only accessible via secure tunnel.

---

## Current State (INSECURE)

### Port Exposure

```yaml
# docker-compose.staging.yml (current)
grafana:
  ports:
    - "3000:3000"  # ❌ PUBLIC - anyone can connect

prometheus:
  ports:
    - "9090:9090"  # ❌ PUBLIC - anyone can connect

loki:
  ports:
    - "3100:3100"  # ❌ PUBLIC - anyone can connect

nginx-rtmp:
  ports:
    - "1936:1935"  # ✅ PUBLIC - needed for RTMP ingress
    - "8081:8080"  # ⚠️ PUBLIC - HTTP status page
```

### What This Means

**From any computer on the internet**:
```bash
# Anyone can try to access Grafana
curl http://<your-server-ip>:3000

# Anyone can query Prometheus
curl http://<your-server-ip>:9090/api/v1/query?query=up

# Anyone can query Loki
curl http://<your-server-ip>:3100/loki/api/v1/labels
```

**Risk**:
- Brute force attacks on Grafana login
- Information disclosure (metrics reveal system details)
- DoS attacks on Prometheus/Loki query endpoints
- Even with strong passwords, exposing admin tools is bad practice

---

## Target State (SECURE)

### 1. UFW Firewall Configuration

**Goal**: Block all incoming traffic except:
- SSH (port 22) - for remote administration
- RTMP (port 1936) - for stream ingress (public service)

**Block**:
- Grafana (port 3000)
- Prometheus (port 9090)
- Loki (port 3100)
- NGINX HTTP status (port 8081)
- All exporters (9100, 9400, 9913, 8082)

**Implementation**:
```bash
# Install UFW
sudo apt install ufw -y

# Default policies
sudo ufw default deny incoming   # Block everything by default
sudo ufw default allow outgoing  # Allow outgoing connections

# Allow SSH (CRITICAL - do this first!)
sudo ufw allow 22/tcp comment 'SSH access'

# Allow RTMP (public service)
sudo ufw allow 1936/tcp comment 'RTMP staging ingress'

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status verbose
```

**Result**:
```
Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere          # SSH access
1936/tcp                   ALLOW       Anywhere          # RTMP staging ingress
```

**Test from external machine**:
```bash
telnet <server-ip> 1936  # ✅ Should succeed (RTMP)
telnet <server-ip> 3000  # ❌ Should timeout (Grafana blocked)
telnet <server-ip> 9090  # ❌ Should timeout (Prometheus blocked)
```

---

### 2. SSH Tunnel for Admin Access

**Problem**: With UFW enabled, how do admins access Grafana/Prometheus?

**Solution**: SSH tunnel - creates encrypted connection from your laptop to server.

**How It Works**:

```
┌─────────────┐                    ┌─────────────┐
│ Your Laptop │                    │   Server    │
│             │                    │             │
│ localhost:  │  SSH Tunnel (22)   │   Docker:   │
│   3000 ────────────────────────────> 3000      │
│   9090 ────────────────────────────> 9090      │
│   8081 ────────────────────────────> 8081      │
└─────────────┘                    └─────────────┘
```

**Usage**:

```bash
# On your laptop
ssh -L 3000:localhost:3000 \
    -L 9090:localhost:9090 \
    -L 8081:localhost:8081 \
    -L 3100:localhost:3100 \
    ubuntu@<server-ip>

# This creates secure tunnels:
# laptop:3000 → server:3000 (Grafana)
# laptop:9090 → server:9090 (Prometheus)
# laptop:8081 → server:8081 (NGINX status)
# laptop:3100 → server:3100 (Loki)
```

**Then in your browser**:
- Open `http://localhost:3000` → connects to server's Grafana
- Open `http://localhost:9090` → connects to server's Prometheus
- Open `http://localhost:8081/stat` → connects to NGINX status page

**Security Benefits**:
- ✅ All traffic encrypted via SSH
- ✅ No public exposure of admin services
- ✅ Requires SSH key authentication to server
- ✅ No additional passwords needed (reuses SSH auth)

---

### 3. Helper Script for Easy Access

**Create**: `scripts/admin_tunnel.sh`

```bash
#!/bin/bash
# Quick admin access via SSH tunnel

SERVER_IP="${1:-<your-server-ip>}"
SERVER_USER="${2:-ubuntu}"

echo "Creating SSH tunnels to $SERVER_USER@$SERVER_IP..."
echo ""
echo "Access services at:"
echo "  Grafana:    http://localhost:3000"
echo "  Prometheus: http://localhost:9090"
echo "  Loki:       http://localhost:3100"
echo "  NGINX:      http://localhost:8081/stat"
echo ""
echo "Press Ctrl+C to close tunnels"
echo ""

ssh -N \
  -L 3000:localhost:3000 \
  -L 9090:localhost:9090 \
  -L 8081:localhost:8081 \
  -L 3100:localhost:3100 \
  $SERVER_USER@$SERVER_IP
```

**Usage**:
```bash
# On your laptop
chmod +x scripts/admin_tunnel.sh
./scripts/admin_tunnel.sh

# Leave terminal open, use browser to access services
# Press Ctrl+C when done
```

---

## Alternative: VPN (Optional)

**If you have VPN infrastructure**:

Instead of SSH tunnels, restrict UFW to VPN subnet:

```bash
# Allow admin services only from VPN subnet
sudo ufw allow from 10.8.0.0/24 to any port 3000 proto tcp comment 'Grafana - VPN'
sudo ufw allow from 10.8.0.0/24 to any port 9090 proto tcp comment 'Prometheus - VPN'
sudo ufw allow from 10.8.0.0/24 to any port 3100 proto tcp comment 'Loki - VPN'
```

**When to use VPN instead of SSH tunnel**:
- You already have VPN infrastructure (OpenVPN, WireGuard)
- Multiple admins need concurrent access
- Need persistent access without keeping SSH session open

**When to use SSH tunnel**:
- No VPN infrastructure
- Single admin or occasional access
- Simpler setup (no VPN server needed)

**Recommendation**: Start with SSH tunnel (simpler), add VPN later if needed.

---

## What We're NOT Changing

**Docker configuration**: We're NOT changing `docker-compose.staging.yml` ports.

**Why**?
- Ports still bind to `0.0.0.0:3000` (all interfaces)
- UFW handles blocking at host firewall level
- This allows SSH tunnel to work (tunnels connect to localhost)

**Alternative approach** (more restrictive):
```yaml
# Could change to localhost-only binding
grafana:
  ports:
    - "127.0.0.1:3000:3000"  # Only localhost can connect
```

**Trade-off**:
- ✅ More secure (even if UFW fails)
- ❌ More complex (need to change docker-compose)
- ❌ May break some Docker networking scenarios

**Decision**: Use UFW first (simpler), consider localhost binding in Phase 3.

---

## Implementation Steps (Summary)

### Step 1: Install UFW (1 minute)
```bash
sudo apt update && sudo apt install ufw -y
```

### Step 2: Configure UFW Rules (2 minutes)
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 1936/tcp comment 'RTMP'
```

### Step 3: Enable UFW (1 minute)
```bash
sudo ufw enable
sudo ufw status verbose
```

### Step 4: Test Access (2 minutes)
```bash
# From external machine
telnet <server-ip> 1936  # Should work
telnet <server-ip> 3000  # Should timeout

# From server itself
curl http://localhost:3000  # Should still work (localhost bypass)
```

### Step 5: Create SSH Tunnel Script (2 minutes)
```bash
# On your laptop
cat > scripts/admin_tunnel.sh << 'EOF'
#!/bin/bash
ssh -N -L 3000:localhost:3000 -L 9090:localhost:9090 ubuntu@<server-ip>
EOF
chmod +x scripts/admin_tunnel.sh
```

### Step 6: Test SSH Tunnel (2 minutes)
```bash
# On your laptop
./scripts/admin_tunnel.sh

# In browser: http://localhost:3000 → should load Grafana
```

**Total Time**: ~10 minutes

---

## Risks & Mitigation

### Risk 1: Locked Out of SSH
**Scenario**: UFW blocks SSH accidentally

**Mitigation**:
1. Always enable SSH rule BEFORE enabling UFW
2. Test SSH connection after enabling UFW
3. Keep existing SSH session open while testing
4. If locked out: Use cloud provider console (AWS Session Manager, DigitalOcean Console)

### Risk 2: UFW Interferes with Docker
**Scenario**: UFW blocks Docker internal networking

**Mitigation**:
1. UFW only affects incoming connections from external hosts
2. Docker containers can still communicate internally
3. Test webhook → nginx connectivity after enabling UFW
4. If issues: `sudo systemctl restart docker` after UFW changes

### Risk 3: Forgot to Create SSH Tunnel
**Scenario**: Admin tries to access Grafana, gets timeout

**Solution**:
1. Document SSH tunnel requirement in README
2. Create helper script for easy access
3. Add reminder to CLAUDE.md

---

## Success Criteria

Block 2.0 is complete when:

- [x] UFW installed and enabled
- [x] Only ports 22 (SSH) and 1936 (RTMP) publicly accessible
- [x] Grafana/Prometheus/Loki blocked from external access
- [x] SSH tunnel script created and tested
- [x] Admin can access Grafana via `http://localhost:3000` through tunnel
- [x] RTMP streaming still functional
- [x] Webhook → NGINX communication still works (Docker internal)

---

## Why This Matters

**Security Benefits**:
1. **Reduced Attack Surface**: 8 ports → 2 ports exposed
2. **Brute Force Protection**: Can't attack Grafana login from internet
3. **Information Hiding**: Metrics/logs not publicly queryable
4. **Defense in Depth**: Even if Grafana has vulnerability, not directly exploitable

**Compliance**:
- Aligns with **CIS Benchmark** best practices
- Required for **SOC 2** / **ISO 27001** compliance
- Industry standard for production deployments

**Real-World Example**:
- Grafana login page publicly exposed → common target for botnets
- Prometheus `/api/v1/query` → can leak sensitive infrastructure details
- Better to require SSH key auth first (SSH tunnel) than rely only on application passwords

---

## Summary

**What**: Install UFW firewall, block admin services, use SSH tunnels for access

**Why**: Reduce attack surface, follow security best practices, comply with standards

**How**: 10 minutes of setup, zero functional impact on RTMP streaming

**Result**: Admin services only accessible via secure SSH tunnel, public access only to RTMP

---

**Next Block**: 2.1 - Prometheus Hardening (CIS compliance, read-only FS, rate limiting)
