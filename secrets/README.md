# Docker Secrets for Stream Keys

This directory contains template files for Docker secrets management.

## Setup Instructions

1. Create actual secret files from templates:
   ```bash
   # Example for gaming profile
   echo "your-youtube-key" > secrets/gaming_youtube_key.txt
   echo "your-twitch-key" > secrets/gaming_twitch_key.txt
   echo "your-kick-key" > secrets/gaming_kick_key.txt
   echo "your-x-key" > secrets/gaming_x_key.txt

   # Set proper permissions
   chmod 600 secrets/*.txt
   ```

2. Secrets will be mounted in containers at `/run/secrets/`

3. The broadcaster script will read keys from:
   - `/run/secrets/PROFILE_SERVICE_key` (e.g., `/run/secrets/gaming_youtube_key`)

## Security Notes

- **DO NOT** commit actual secret files to git
- All `*.txt` files are gitignored except templates
- Secrets are mounted as read-only in containers
- File permissions should be 600 (owner read/write only)

## Migration from Environment Variables

Old approach (insecure):
```bash
# .env file
GAMING_YOUTUBE_KEY=sk-xxx
GAMING_TWITCH_KEY=live_xxx
```

New approach (secure):
```bash
# secrets/gaming_youtube_key.txt
sk-xxx

# secrets/gaming_twitch_key.txt
live_xxx
```

## Secrets Naming Convention

Format: `{profile}_{service}_key.txt`

Examples:
- `gaming_youtube_key.txt`
- `gaming_twitch_key.txt`
- `events_youtube_key.txt`
- `irl_kick_key.txt`

All lowercase, underscores for separators.
