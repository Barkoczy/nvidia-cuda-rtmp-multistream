# Container Security Hardening Guide

This document explains the security hardening measures implemented in the RTMP multistreaming server.

## Security Improvements Summary

| Feature | Before | After | Security Benefit |
|---------|--------|-------|------------------|
| Root Filesystem | Read-Write | **Read-Only** | Prevents runtime modifications |
| User | root | **broadcaster (UID 1000)** | Principle of least privilege |
| Capabilities | All | **Minimal set** | Reduces attack surface |
| New Privileges | Allowed | **Blocked** | Prevents privilege escalation |
| Secrets | Environment vars | **Docker secrets** | Secure key management |
| Command Execution | exec_publish | **Webhook** | No command injection |

## Read-Only Root Filesystem

### What It Does

The container's root filesystem (`/`) is mounted as read-only, preventing any modifications to system files at runtime.

```yaml
read_only: true
```

### Required Tmpfs Volumes

Since some paths need to be writable, we use in-memory tmpfs volumes:

```yaml
tmpfs:
  - /tmp                  # FFmpeg temporary files
  - /var/run              # Runtime files (PIDs, sockets)
  - /var/cache/nginx      # NGINX cache
```

### Persistent Storage

Mounted volumes for data that must persist:

```yaml
volumes:
  - ./logs-staging:/var/log/broadcaster  # Application logs
  - /tmp/hls:/tmp/hls                    # HLS stream segments
```

## Capability Dropping

### Minimal Capabilities Model

By default, Docker grants many Linux capabilities. We drop all and add only what's needed:

```yaml
cap_drop:
  - ALL

cap_add:
  - CHOWN             # Change file ownership
  - DAC_OVERRIDE      # Bypass file permission checks
  - SETGID            # Set group ID
  - SETUID            # Set user ID
  - NET_BIND_SERVICE  # Bind to ports < 1024
```

### Why Each Capability Is Needed

| Capability | Required For | Example |
|------------|--------------|---------|
| `CHOWN` | Setting log file ownership | `chown broadcaster:broadcaster /var/log/broadcaster/*.log` |
| `DAC_OVERRIDE` | Writing to mounted volumes | Writing logs despite file permissions |
| `SETGID` | Switching to broadcaster group | `setgid(1000)` in entrypoint |
| `SETUID` | Switching to broadcaster user | `setuid(1000)` in entrypoint |
| `NET_BIND_SERVICE` | Binding NGINX to port 1935/8080 | RTMP and HTTP servers |

### Capabilities NOT Needed

These are explicitly dropped for security:

- `SYS_ADMIN` - No system administration needed
- `SYS_PTRACE` - No process tracing
- `SYS_MODULE` - No kernel module loading
- `NET_ADMIN` - No network configuration changes
- `NET_RAW` - No raw sockets

## Non-Root User Execution

### User Configuration

```yaml
user: "1000:1000"  # broadcaster:broadcaster
```

The container runs as the `broadcaster` user (UID 1000, GID 1000), created in the Dockerfile:

```dockerfile
RUN groupadd -g 1000 broadcaster && \
    useradd -u 1000 -g broadcaster -s /bin/bash -m broadcaster
```

### Entrypoint Behavior

The entrypoint script runs as root initially (for GPU setup), then drops to broadcaster:

```bash
#!/bin/bash
# Initial setup as root
if [ "$(id -u)" = "0" ]; then
    # Setup NVIDIA symlinks
    # ...

    # Drop to broadcaster user
    exec su-exec broadcaster "$0" "$@"
fi

# Rest runs as broadcaster
nginx -g "daemon off;"
```

## No New Privileges

```yaml
security_opt:
  - no-new-privileges:true
```

This prevents processes from gaining additional privileges via:
- setuid/setgid binaries
- File capabilities
- execve() calls

Example attack blocked:
```bash
# Even if attacker finds a setuid binary, it won't work
chmod u+s /usr/bin/malicious
./malicious  # Won't execute with elevated privileges
```

## Multi-Stage Build Security

### Build vs Runtime Separation

```dockerfile
# Build stage - includes compilers and dev tools
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS builder
RUN apt-get install build-essential gcc make ...

# Runtime stage - minimal dependencies only
FROM nvidia/cuda:12.8.0-runtime-ubuntu24.04
COPY --from=builder /usr/local/bin/ffmpeg /usr/bin/ffmpeg
# No compilers, no dev tools in final image
```

### Benefits

- **Smaller attack surface**: No compilers in runtime image
- **Smaller image size**: Only runtime libraries, not build tools
- **Clear separation**: Build dependencies don't leak into production

## File Permissions

### Principle of Least Privilege

```bash
# Configuration files: read-only
chmod 644 /etc/broadcaster/profiles.yml

# Executables: owner can execute
chmod 755 /usr/local/bin/broadcaster

# Secrets: owner read-only
chmod 600 /run/secrets/gaming_youtube_key

# Log directories: owner can write
chmod 755 /var/log/broadcaster
```

### Ownership Structure

```
/etc/broadcaster/
├── profiles.yml       (broadcaster:broadcaster, 644)

/usr/local/bin/
├── broadcaster        (broadcaster:broadcaster, 755)
└── hls_transcode      (broadcaster:broadcaster, 755)

/run/secrets/
├── gaming_youtube_key (broadcaster:broadcaster, 600)
└── gaming_twitch_key  (broadcaster:broadcaster, 600)

/var/log/broadcaster/
└── *.log              (broadcaster:broadcaster, 644)
```

## Security Testing

### Verify Read-Only Filesystem

```bash
# This should fail
docker compose exec nginx-rtmp-staging touch /test
# Error: Read-only file system

# Tmpfs should work
docker compose exec nginx-rtmp-staging touch /tmp/test
# Success
```

### Verify User Context

```bash
# Check current user
docker compose exec nginx-rtmp-staging whoami
# Expected: broadcaster

docker compose exec nginx-rtmp-staging id
# Expected: uid=1000(broadcaster) gid=1000(broadcaster) groups=1000(broadcaster),44(video)
```

### Verify Capabilities

```bash
# Check process capabilities
docker compose exec nginx-rtmp-staging grep Cap /proc/1/status

# Compare with capsh
docker run --rm -it --cap-drop=ALL --cap-add=CHOWN,DAC_OVERRIDE \
    alpine capsh --print
```

### Verify No New Privileges

```bash
# Try to escalate privileges (should fail)
docker compose exec nginx-rtmp-staging su root
# Expected: su: Authentication failure
```

## Security Audit Checklist

- [ ] Container runs as non-root user (UID 1000)
- [ ] Root filesystem is read-only
- [ ] Tmpfs volumes exist for writable paths
- [ ] Only minimal capabilities granted
- [ ] no-new-privileges enabled
- [ ] Secrets not in environment variables
- [ ] No compilers in runtime image
- [ ] File permissions follow least privilege
- [ ] Health check endpoint works
- [ ] NVIDIA GPU access works with restrictions

## Troubleshooting

### "Permission denied" errors

**Symptom**: Container can't write to logs

**Solution**: Check volume ownership

```bash
# On host
ls -la logs-staging/
chown -R 1000:1000 logs-staging/
```

### "Read-only file system" errors

**Symptom**: Process tries to write to non-tmpfs path

**Solution**: Add path to tmpfs or mount as volume

```yaml
tmpfs:
  - /path/that/needs/writes
```

### "Operation not permitted" capability errors

**Symptom**: Container can't perform specific operation

**Solution**: Check if capability is needed

```bash
# See what capabilities process needs
strace -e trace=capset,capget nginx

# Add to cap_add if legitimate
cap_add:
  - REQUIRED_CAPABILITY
```

### GPU not accessible

**Symptom**: NVENC encoding fails

**Solution**: Ensure video capability is granted

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          capabilities: [gpu, video]  # video is required
```

## Performance Impact

| Feature | Performance Impact | Justification |
|---------|-------------------|---------------|
| Read-only filesystem | **None** | In-memory tmpfs as fast as RAM |
| Capability dropping | **Negligible** | Only syscall checks |
| Non-root user | **None** | No performance difference |
| Multi-stage build | **Positive** | Smaller image = faster pulls |

## Comparison with Industry Standards

### CIS Docker Benchmark Compliance

| CIS Control | Status | Implementation |
|-------------|--------|----------------|
| 5.1 - No root user | ✅ | `user: "1000:1000"` |
| 5.3 - Read-only filesystem | ✅ | `read_only: true` |
| 5.15 - No new privileges | ✅ | `no-new-privileges:true` |
| 5.24 - cgroup limits | ⚠️ | GPU limits set |
| 5.25 - Restrict capabilities | ✅ | Minimal cap set |

### NIST Guidelines Compliance

Follows NIST SP 800-190 (Application Container Security Guide):

- ✅ Immutable infrastructure (read-only root)
- ✅ Least privilege (minimal capabilities)
- ✅ Secrets management (Docker secrets)
- ✅ Image scanning (multi-stage minimal base)

## Future Enhancements

Potential additional hardening (Phase 2):

1. **AppArmor/SELinux profile**: Custom security policy
2. **Seccomp profile**: Syscall filtering
3. **Network policies**: Restrict egress/ingress
4. **Image signing**: Verify image integrity
5. **Runtime scanning**: Detect anomalies
