#!/bin/bash
# Helper script to initialize Docker secrets from .env file (Block 1.2)

set -e

SECRETS_DIR="./secrets"
ENV_FILE=".env"

echo "=== Docker Secrets Initialization ==="
echo ""

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found"
    echo "Please create .env file with your streaming keys first"
    exit 1
fi

# Create secrets directory if it doesn't exist
mkdir -p "$SECRETS_DIR"

# Function to extract and save secret
save_secret() {
    local env_var=$1
    local secret_file=$2

    # Extract value from .env
    local value=$(grep "^${env_var}=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

    if [ -z "$value" ]; then
        echo "⚠ Warning: $env_var not found in $ENV_FILE, skipping $secret_file"
        return
    fi

    # Save to secret file
    echo -n "$value" > "$SECRETS_DIR/$secret_file"
    chmod 600 "$SECRETS_DIR/$secret_file"
    echo "✓ Created $secret_file (from $env_var)"
}

echo "Converting environment variables to Docker secrets..."
echo ""

# Gaming profile
save_secret "GAMING_YOUTUBE_KEY" "gaming_youtube_key.txt"
save_secret "GAMING_TWITCH_KEY" "gaming_twitch_key.txt"
save_secret "GAMING_KICK_KEY" "gaming_kick_key.txt"
save_secret "GAMING_X_KEY" "gaming_x_key.txt"

# Events profile (if exists)
save_secret "EVENTS_YOUTUBE_KEY" "events_youtube_key.txt"

echo ""
echo "=== Secrets initialization complete ==="
echo ""
echo "Created secrets in $SECRETS_DIR/"
ls -lh "$SECRETS_DIR"/*.txt 2>/dev/null || echo "No secrets created"
echo ""
echo "Next steps:"
echo "1. Verify secret files: cat $SECRETS_DIR/gaming_youtube_key.txt"
echo "2. Test staging environment: docker compose -f docker-compose.staging.yml up -d"
echo "3. After successful testing, you can remove keys from .env file"
