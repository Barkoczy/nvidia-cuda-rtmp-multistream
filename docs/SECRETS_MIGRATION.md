# Migration Guide: Environment Variables → Docker Secrets

This document describes the migration from insecure environment variables to secure Docker secrets for stream keys.

## Why Migrate?

**Security Issues with Environment Variables:**
- ✗ Visible in `docker inspect` output
- ✗ Visible in process listings (`ps aux`)
- ✗ Logged in debug outputs
- ✗ Stored in plaintext in `.env` file
- ✗ Easy to accidentally commit to git

**Benefits of Docker Secrets:**
- ✓ Mounted as read-only files in `/run/secrets/`
- ✓ Not visible in `docker inspect`
- ✓ Not exposed in environment
- ✓ Proper file permissions (owner read-only)
- ✓ Easy to rotate without rebuilding containers

## Migration Steps

### 1. Initialize Secrets from .env

```bash
# Automatic conversion
./init_secrets.sh

# Manual creation (if needed)
echo "your-youtube-key" > secrets/gaming_youtube_key.txt
echo "your-twitch-key" > secrets/gaming_twitch_key.txt
chmod 600 secrets/*.txt
```

### 2. Verify Secrets Structure

```bash
ls -la secrets/
# Expected output:
# -rw------- 1 user user  32 Jan 16 10:00 gaming_youtube_key.txt
# -rw------- 1 user user  28 Jan 16 10:00 gaming_twitch_key.txt
```

### 3. Update docker-compose.yml

Add secrets configuration:

```yaml
services:
  nginx-rtmp:
    secrets:
      - gaming_youtube_key
      - gaming_twitch_key
    # Remove env_file if migrating fully

secrets:
  gaming_youtube_key:
    file: ./secrets/gaming_youtube_key.txt
  gaming_twitch_key:
    file: ./secrets/gaming_twitch_key.txt
```

### 4. Test in Staging

```bash
# Start staging environment
docker compose -f docker-compose.staging.yml up -d

# Verify secrets are mounted
docker compose exec nginx-rtmp-staging ls -la /run/secrets/

# Check broadcaster can read secrets
docker compose exec nginx-rtmp-staging cat /run/secrets/gaming_youtube_key
```

### 5. Clean Up Old Environment Variables

After successful migration:

```bash
# Backup .env
cp .env .env.backup

# Remove stream keys from .env
sed -i '/GAMING_YOUTUBE_KEY/d' .env
sed -i '/GAMING_TWITCH_KEY/d' .env
```

## How It Works

### Broadcaster Script Logic

The broadcaster script uses this priority order:

1. **Docker Secret** (preferred): `/run/secrets/PROFILE_SERVICE_key`
2. **Environment Variable** (fallback): `$PROFILE_SERVICE_KEY`
3. **Legacy Variables** (last resort): `$YOUTUBE_KEY`, `$TWITCH_KEY`

Example for gaming profile + YouTube:

```bash
# 1. Check Docker secret
if [ -f /run/secrets/gaming_youtube_key ]; then
    key=$(cat /run/secrets/gaming_youtube_key)

# 2. Fallback to environment
elif [ -n "$GAMING_YOUTUBE_KEY" ]; then
    key="$GAMING_YOUTUBE_KEY"

# 3. Legacy fallback
elif [ -n "$YOUTUBE_KEY" ]; then
    key="$YOUTUBE_KEY"
fi
```

### File Naming Convention

Docker secrets use **lowercase with underscores**:

- Profile: `gaming` → `gaming_`
- Service: `youtube` → `youtube_`
- Suffix: always `_key`
- Extension: `.txt`

Examples:
- `gaming_youtube_key.txt`
- `gaming_twitch_key.txt`
- `events_youtube_key.txt`

## Security Best Practices

### File Permissions

```bash
# Secrets directory
chmod 700 secrets/

# Individual secrets
chmod 600 secrets/*.txt
```

### Git Configuration

The `secrets/.gitignore` ensures:
- All `*.txt` files are ignored
- Only templates (`*.txt.example`) are tracked

### Secret Rotation

To rotate a key:

```bash
# 1. Update secret file
echo "new-key-value" > secrets/gaming_youtube_key.txt

# 2. Restart container (secrets are remounted)
docker compose restart nginx-rtmp

# 3. Verify new key is loaded
docker compose logs nginx-rtmp | grep "Loading key from Docker secret"
```

## Troubleshooting

### "No key found for service"

Check:
1. Secret file exists: `ls -la secrets/gaming_youtube_key.txt`
2. File permissions: `chmod 600 secrets/gaming_youtube_key.txt`
3. Secret defined in docker-compose.yml
4. Container has secret mounted: `docker exec nginx-rtmp ls /run/secrets/`

### "Permission denied" reading secret

```bash
# Fix ownership
chown $(whoami):$(whoami) secrets/*.txt
chmod 600 secrets/*.txt
```

### Secret not updated after change

```bash
# Secrets are mounted at container start
docker compose restart nginx-rtmp

# Or recreate container
docker compose up -d --force-recreate nginx-rtmp
```

## Rollback Plan

If issues occur, revert to environment variables:

```bash
# 1. Restore .env from backup
cp .env.backup .env

# 2. Use old docker-compose.yml
git checkout HEAD^ docker-compose.yml

# 3. Restart
docker compose restart
```

## Production Migration Checklist

- [ ] Backup current .env file
- [ ] Run `init_secrets.sh` to create secret files
- [ ] Verify secret file permissions (600)
- [ ] Test in staging environment
- [ ] Verify streams start correctly in staging
- [ ] Update production docker-compose.yml
- [ ] Deploy to production with zero downtime
- [ ] Verify production streams
- [ ] Clean up .env file (remove migrated keys)
- [ ] Update documentation
