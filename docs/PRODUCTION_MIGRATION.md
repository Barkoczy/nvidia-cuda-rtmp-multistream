# Production Migration Guide - Phase 1 Security Hardening

This guide provides step-by-step instructions for migrating the security hardening changes from staging to production.

## Pre-Migration Checklist

- [ ] All staging tests passed (`test_security.sh` and `test_webhook.sh`)
- [ ] Baseline measurements recorded (`baseline_measurements.md`)
- [ ] Full backup created (see Backup section)
- [ ] Maintenance window scheduled
- [ ] Rollback plan reviewed
- [ ] Team notified of deployment

## Migration Overview

**Estimated Downtime**: 5-10 minutes (for container restart)

**Changes Being Deployed**:
1. Webhook server replacing exec_publish
2. Docker secrets replacing environment variables
3. Hardened container with read-only filesystem
4. Non-root user execution
5. Minimal Linux capabilities

## Step-by-Step Migration

### 1. Create Full Backup

```bash
# Backup all critical files
BACKUP_DIR="backup/$(date +%Y%m%d_%H%M%S)_pre-phase1"
mkdir -p "$BACKUP_DIR"

# Backup configuration
cp docker-compose.yml "$BACKUP_DIR/"
cp nginx.conf "$BACKUP_DIR/"
cp Dockerfile "$BACKUP_DIR/"
cp .env "$BACKUP_DIR/.env.backup"

# Backup application files
cp broadcaster "$BACKUP_DIR/"
cp hls_transcode "$BACKUP_DIR/"
cp entrypoint.sh "$BACKUP_DIR/"

# Create git tag for rollback point
git tag -a v0.1-pre-phase1-prod -m "Production snapshot before Phase 1 migration"
git push origin v0.1-pre-phase1-prod

echo "Backup created in $BACKUP_DIR"
```

### 2. Initialize Production Secrets

```bash
# Convert environment variables to Docker secrets
./init_secrets.sh

# Verify secrets were created
ls -la secrets/
# Expected: gaming_youtube_key.txt, gaming_twitch_key.txt, etc.

# Verify permissions
find secrets/ -name "*.txt" -exec ls -l {} \;
# Expected: -rw------- (600)
```

### 3. Update Production docker-compose.yml

```bash
# Copy hardened configuration
cp docker-compose.staging.yml docker-compose.yml

# Update ports to production values
sed -i 's/1936:1935/1935:1935/' docker-compose.yml
sed -i 's/8081:8080/8080:8080/' docker-compose.yml

# Update container name
sed -i 's/nginx-rtmp-staging/nginx-rtmp/' docker-compose.yml
sed -i 's/webhook-staging/webhook/' docker-compose.yml

# Update log directory
sed -i 's/logs-staging/logs/' docker-compose.yml
```

### 4. Update NGINX Configuration

```bash
# Copy staging nginx config to production
cp nginx.staging.conf nginx.conf

# Verify webhook URL is correct
grep "on_publish" nginx.conf
# Expected: http://webhook:8090/api/v1/publish
```

### 5. Stop Current Production

```bash
# Gracefully stop existing streams
# (if broadcaster has active streams, stop them first)

# Stop production containers
docker compose down

# Verify containers are stopped
docker ps | grep nginx-rtmp
# Should return nothing
```

### 6. Deploy New Configuration

```bash
# Build hardened image
docker compose build --no-cache

# Verify build succeeded
docker images | grep nvidia-cuda-rtmp-multistream

# Start services
docker compose up -d

# Wait for containers to be healthy
sleep 10

# Check container status
docker compose ps
# Expected: Both nginx-rtmp and webhook showing "Up" and "healthy"
```

### 7. Verify Deployment

```bash
# Run security tests
./test_security.sh

# Run webhook tests
./test_webhook.sh

# Check logs for errors
docker compose logs --tail=50 nginx-rtmp
docker compose logs --tail=50 webhook

# Verify NGINX is listening
curl http://localhost:8080/stat
```

### 8. Functional Testing

```bash
# Test RTMP ingestion
ffmpeg -re -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=1000:duration=30 \
    -c:v libx264 -preset ultrafast -b:v 3000k \
    -c:a aac -b:a 128k \
    -f flv rtmp://localhost:1935/live/gaming

# Monitor in separate terminal:
# docker compose logs -f nginx-rtmp
# docker compose logs -f webhook

# Verify HLS output
curl http://localhost:8080/hls/gaming.m3u8

# Check broadcaster processes
docker compose exec nginx-rtmp ps aux | grep broadcaster
```

### 9. Post-Deployment Verification

```bash
# Verify security features
echo "Checking security features..."

# 1. Read-only filesystem
docker compose exec nginx-rtmp touch /test 2>&1 | grep "Read-only file system"

# 2. Non-root user
docker compose exec nginx-rtmp whoami
# Expected: broadcaster

# 3. Secrets mounted
docker compose exec nginx-rtmp ls -la /run/secrets/

# 4. Webhook responding
curl http://localhost:8090/health
# Expected: {"status":"healthy"}
```

### 10. Clean Up Environment Variables

```bash
# After confirming secrets work, remove from .env

# Backup .env first
cp .env .env.with-keys

# Remove stream keys (they're now in secrets/)
sed -i '/GAMING_YOUTUBE_KEY/d' .env
sed -i '/GAMING_TWITCH_KEY/d' .env
sed -i '/GAMING_KICK_KEY/d' .env
sed -i '/GAMING_X_KEY/d' .env

# Verify .env no longer contains keys
grep -i "_KEY" .env
# Should return nothing or only non-secret keys
```

### 11. Update Documentation

```bash
# Update README if needed
# Update any internal runbooks
# Notify team of new secret management process
```

## Rollback Procedure

If issues occur, rollback using this procedure:

### Quick Rollback (5 minutes)

```bash
# 1. Stop new containers
docker compose down

# 2. Restore old configuration
BACKUP_DIR="backup/20251116_022802_pre-phase1"  # Use your backup timestamp
cp "$BACKUP_DIR/docker-compose.yml" .
cp "$BACKUP_DIR/nginx.conf" .
cp "$BACKUP_DIR/Dockerfile" .
cp "$BACKUP_DIR/.env.backup" .env

# 3. Rebuild with old configuration
docker compose build

# 4. Start old version
docker compose up -d

# 5. Verify
curl http://localhost:8080/stat
```

### Git Rollback

```bash
# Rollback code to previous state
git checkout v0.1-pre-phase1-prod

# Rebuild and restart
docker compose down
docker compose build
docker compose up -d
```

## Monitoring Post-Migration

### Key Metrics to Watch

1. **GPU Utilization**
   ```bash
   watch -n 1 'nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used --format=csv,noheader'
   ```

2. **FFmpeg Process Count**
   ```bash
   watch -n 1 'docker compose exec nginx-rtmp ps aux | grep ffmpeg | grep -v grep | wc -l'
   ```

3. **Container Resource Usage**
   ```bash
   docker stats nginx-rtmp webhook
   ```

4. **Logs**
   ```bash
   docker compose logs -f --tail=100
   ```

### Expected Behavior

✅ **Normal**:
- Webhook receives publish/publish_done events
- Broadcaster spawns FFmpeg processes for each service
- GPU utilization 40-60% during streaming
- No permission errors in logs
- HLS segments generated in /tmp/hls/

❌ **Issues to Watch For**:
- "Permission denied" errors → Check volume ownership
- "Read-only file system" errors → Check tmpfs mounts
- "No key found" errors → Check secrets are mounted
- Webhook connection refused → Check webhook container health

## Performance Comparison

Record metrics before and after migration:

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| GPU Utilization | __% | __% | __ |
| VRAM Usage | __ GB | __ GB | __ |
| FFmpeg Processes | __ | __ | __ |
| CPU Load Average | __ | __ | __ |
| Stream Latency | __s | __s | __ |

Use `baseline_measurements.md` to fill in "Before" values.

## Troubleshooting

### Issue: Secrets not found

**Symptoms**: "No key found for service" in logs

**Solution**:
```bash
# 1. Verify secrets exist
ls -la secrets/

# 2. Check docker-compose.yml has secrets defined
grep -A 10 "^secrets:" docker-compose.yml

# 3. Recreate container to remount secrets
docker compose up -d --force-recreate nginx-rtmp
```

### Issue: Permission errors

**Symptoms**: "Permission denied" writing to logs

**Solution**:
```bash
# Fix ownership on host
sudo chown -R 1000:1000 logs/
sudo chmod -R 755 logs/

# Restart container
docker compose restart nginx-rtmp
```

### Issue: GPU not accessible

**Symptoms**: "Cannot load nvcuvid" or NVENC errors

**Solution**:
```bash
# Verify nvidia-container-runtime is installed
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi

# Check docker-compose.yml has proper GPU config
grep -A 5 "devices:" docker-compose.yml

# Restart with GPU properly configured
docker compose down
docker compose up -d
```

### Issue: Webhook not responding

**Symptoms**: "Connection refused" to webhook:8090

**Solution**:
```bash
# Check webhook container
docker compose ps webhook

# Check webhook logs
docker compose logs webhook

# Restart webhook
docker compose restart webhook

# Verify webhook is healthy
curl http://localhost:8090/health
```

## Success Criteria

Migration is successful when:

- ✅ All security tests pass (`./test_security.sh`)
- ✅ Webhook tests pass (`./test_webhook.sh`)
- ✅ Real stream works end-to-end (OBS → RTMP → platforms)
- ✅ No "permission denied" errors in logs
- ✅ GPU utilization is normal (40-60% during streaming)
- ✅ HLS playback works
- ✅ No environment variables contain secrets
- ✅ All secrets readable from /run/secrets/

## Post-Migration Tasks

- [ ] Update monitoring dashboards (if any)
- [ ] Update deployment documentation
- [ ] Document any issues encountered
- [ ] Review logs after 24 hours
- [ ] Compare performance metrics with baseline
- [ ] Archive old .env with keys securely
- [ ] Clean up old Docker images: `docker image prune -a`

## Support

If issues persist after following this guide:

1. Check logs: `docker compose logs --tail=200`
2. Review security test output: `./test_security.sh`
3. Compare with staging: `docker compose -f docker-compose.staging.yml ps`
4. Rollback if critical issues: See "Rollback Procedure" above

## Next Phase

After successful Phase 1 migration, prepare for Phase 2:
- Performance optimization (single-process FFmpeg)
- Observability stack (Prometheus, Grafana, Loki)
- Advanced monitoring and alerting
