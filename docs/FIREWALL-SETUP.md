# Firewall Setup Guide

**Purpose**: Configure host firewall to restrict access to services
**Status**: Documentation only (UFW not installed on this host)
**Phase**: Phase 1 - Security Baseline

---

## Prerequisites

Install UFW (if not present):
```bash
sudo apt update
sudo apt install ufw -y
```

---

## Basic UFW Configuration

### 1. Set Default Policies

```bash
# Deny all incoming by default
sudo ufw default deny incoming

# Allow all outgoing
sudo ufw default allow outgoing
```

### 2. Allow SSH (CRITICAL - do this first!)

```bash
# Allow SSH to prevent lockout
sudo ufw allow 22/tcp comment 'SSH access'
```

### 3. RTMP Services (Public Access)

```bash
# RTMP ingress port (staging)
sudo ufw allow 1936/tcp comment 'RTMP staging ingress'

# Production RTMP (when deployed)
# sudo ufw allow 1935/tcp comment 'RTMP production ingress'
```

### 4. HTTP Status Page (Internal/VPN Only)

**Option A: Restrict to specific IP** (recommended):
```bash
# Replace <VPN_IP> with your VPN/trusted IP
sudo ufw allow from <VPN_IP> to any port 8081 proto tcp comment 'NGINX HTTP staging'
```

**Option B: Allow from local network only**:
```bash
sudo ufw allow from 192.168.0.0/16 to any port 8081 proto tcp comment 'NGINX HTTP staging - LAN'
```

**Option C: Public access** (NOT recommended):
```bash
# Only use if absolutely necessary
sudo ufw allow 8081/tcp comment 'NGINX HTTP staging - PUBLIC'
```

### 5. Admin UI Access (VPN/Localhost Only)

**Grafana**:
```bash
# Localhost only (SSH tunnel required)
sudo ufw allow from 127.0.0.1 to any port 3000 proto tcp comment 'Grafana - localhost'

# OR from VPN IP
sudo ufw allow from <VPN_IP> to any port 3000 proto tcp comment 'Grafana - VPN'
```

**Prometheus**:
```bash
# Localhost only (SSH tunnel required)
sudo ufw allow from 127.0.0.1 to any port 9090 proto tcp comment 'Prometheus - localhost'

# OR from VPN IP
sudo ufw allow from <VPN_IP> to any port 9090 proto tcp comment 'Prometheus - VPN'
```

### 6. Enable Firewall

```bash
# Enable UFW
sudo ufw enable

# Verify status
sudo ufw status verbose
```

---

## Firewall Rules Matrix

| Port | Service | Public | VPN/Trusted | Localhost | Recommendation |
|------|---------|--------|-------------|-----------|----------------|
| 22 | SSH | ✅ | ✅ | ✅ | Allow (with key auth) |
| 1935 | RTMP Production | ✅ | ✅ | ✅ | Allow (when prod deployed) |
| 1936 | RTMP Staging | ✅ | ✅ | ✅ | Allow (for testing) |
| 8080 | NGINX Status (prod) | ❌ | ✅ | ✅ | VPN/Localhost only |
| 8081 | NGINX Status (staging) | ❌ | ✅ | ✅ | VPN/Localhost only |
| 3000 | Grafana | ❌ | ✅ | ✅ | VPN/Localhost only |
| 9090 | Prometheus | ❌ | ✅ | ✅ | VPN/Localhost only |
| 8090 | Webhook | ❌ | ❌ | ❌ | Internal Docker network only (no firewall rule needed) |
| 3100 | Loki | ❌ | ❌ | ❌ | Internal Docker network only |
| 9100 | Node Exporter | ❌ | ❌ | ❌ | Internal Docker network only |
| 8082 | cAdvisor | ❌ | ❌ | ❌ | Internal Docker network only |
| 9400 | DCGM Exporter | ❌ | ❌ | ❌ | Internal Docker network only |
| 9913 | VTS Exporter | ❌ | ❌ | ❌ | Internal Docker network only |

---

## SSH Tunnel Access (for Admin UIs)

If firewall is configured for localhost-only access, use SSH tunnels:

### Grafana via SSH Tunnel

```bash
# On your local machine
ssh -L 3000:localhost:3000 ubuntu@<server-ip>

# Then access Grafana at http://localhost:3000
```

### Prometheus via SSH Tunnel

```bash
# On your local machine
ssh -L 9090:localhost:9090 ubuntu@<server-ip>

# Then access Prometheus at http://localhost:9090
```

### Multiple Services in One Tunnel

```bash
ssh -L 3000:localhost:3000 -L 9090:localhost:9090 -L 8081:localhost:8081 ubuntu@<server-ip>
```

---

## Verification

### Check Open Ports

```bash
# List all listening ports
sudo ss -tulpen | grep LISTEN

# Check specific port
sudo ss -tulpen | grep :3000
```

### Check UFW Rules

```bash
# Verbose status
sudo ufw status verbose

# Numbered list (for deletion)
sudo ufw status numbered
```

### Test from External Machine

```bash
# Should succeed (RTMP port)
telnet <server-ip> 1936

# Should fail (Grafana, if restricted)
telnet <server-ip> 3000
```

---

## Advanced: Rate Limiting (Phase 2)

UFW can implement basic rate limiting for brute-force protection:

```bash
# Limit SSH connection attempts
sudo ufw limit 22/tcp comment 'SSH rate limit'

# Limit RTMP publish attempts (10 conn/min)
sudo ufw limit 1936/tcp comment 'RTMP rate limit'
```

**Note**: This is basic protection. Phase 2 should implement application-level rate limiting (nginx `limit_req`, fail2ban).

---

## Troubleshooting

### Locked Out After Enabling UFW

If you accidentally locked yourself out:

1. **Via console access** (if available):
   ```bash
   sudo ufw disable
   sudo ufw allow 22/tcp
   sudo ufw enable
   ```

2. **Via cloud provider console**:
   - AWS EC2: Use EC2 Instance Connect or Session Manager
   - DigitalOcean: Use Droplet Console
   - Add SSH rule, then re-enable UFW

### UFW Blocks Docker Ports

UFW can interfere with Docker's iptables rules. If experiencing issues:

```bash
# Check Docker iptables
sudo iptables -L DOCKER -n

# Reload Docker after UFW changes
sudo systemctl restart docker
```

### Verify UFW Doesn't Block Internal Docker Network

```bash
# Test webhook from nginx container
docker exec nginx-rtmp-staging wget -q -O- http://webhook:8090/health

# Should return: {"status":"healthy"}
```

---

## Current Status

- ❌ UFW not installed on this host
- ✅ Documentation created for manual setup
- 📋 **Action Required**: Install UFW and apply rules before production deployment

---

**Related Documents**:
- `docs/SECURITY-BASELINE.md` - Overall security documentation
- `.changelogs/20251116/phase1_security_baseline_plan.md` - Implementation plan
