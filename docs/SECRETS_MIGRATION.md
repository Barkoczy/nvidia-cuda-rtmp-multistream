# Migration Guide: Environment Variables → Docker Secrets

This document describes the migration from insecure environment variables to Docker secrets for stream keys. **Environment-variable fallback is no longer supported at runtime.**

## Why Migrate?

**Security issues with environment variables:**
- ✗ Visible in `docker inspect` output
- ✗ Visible in process listings (`ps aux`)
- ✗ Logged in debug outputs
- ✗ Stored in plaintext in `.env`

**Benefits of Docker secrets:**
- ✓ Mounted as read-only files in `/run/secrets/`
- ✓ Not visible in `docker inspect`
- ✓ Not exposed in environment
- ✓ Proper file permissions (owner read-only)
- ✓ Easy to rotate without rebuilding containers

## Migration Steps

### 1) Initialize secrets from .env (one-time helper)

```bash
# Optional: use the helper to convert .env -> secrets
cp .env.example .env
./init_secrets.sh
```

### 2) Or create secrets manually

```bash
echo "your-youtube-key" > secrets/gaming_youtube_key.txt
echo "your-twitch-key" > secrets/gaming_twitch_key.txt
chmod 600 secrets/*.txt
```

### 3) Verify secrets structure

```bash
ls -la secrets/
# Expected output:
# -rw------- 1 user user  32 Jan 16 10:00 gaming_youtube_key.txt
# -rw------- 1 user user  28 Jan 16 10:00 gaming_twitch_key.txt
```

### 4) Ensure Docker Compose uses secrets only

```yaml
services:
  nginx-rtmp:
    secrets:
      - gaming_youtube_key
      - gaming_twitch_key

secrets:
  gaming_youtube_key:
    file: ./secrets/gaming_youtube_key.txt
  gaming_twitch_key:
    file: ./secrets/gaming_twitch_key.txt
```

> Note: `env_file: .env` is intentionally removed. The runtime no longer reads stream keys from environment variables.

### 5) Test in staging

```bash
# Start staging environment
docker compose -f docker-compose.staging.yml up -d

# Verify secrets are mounted
docker compose exec nginx-rtmp-staging ls -la /run/secrets/
```

## How It Works (Runtime)

The broadcaster **only** reads Docker secrets:

```bash
key_file="/run/secrets/${profile}_${service}_key"
if [ -f "$key_file" ]; then
    stream_key=$(cat "$key_file")
else
    echo "Missing secret for ${profile}/${service}"
    exit 1
fi
```

## Security Best Practices

### File Permissions

```bash
chmod 700 secrets/
chmod 600 secrets/*.txt
```

### Secret Rotation

```bash
# 1. Update secret file
echo "new-key-value" > secrets/gaming_youtube_key.txt

# 2. Restart container (secrets are remounted)
docker compose restart nginx-rtmp
```

## Troubleshooting

### "Missing secret" error

Check:
1. Secret file exists: `ls -la secrets/gaming_youtube_key.txt`
2. File permissions: `chmod 600 secrets/gaming_youtube_key.txt`
3. Secret defined in `docker-compose.yml`
4. Container has secret mounted: `docker compose exec nginx-rtmp ls /run/secrets/`

## Rollback Policy

Rollback to environment variables is **not supported**. If secrets are missing or invalid, fix the secrets and restart the container.
