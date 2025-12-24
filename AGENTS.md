# Repository Guidelines

## Project Structure & Module Organization
- `docker-compose.yml`, `docker-compose.staging.yml`, `docker-compose.test.yml` define runtime stacks.
- NGINX RTMP config lives in `nginx.conf` and `nginx.staging.conf`.
- Core runtime scripts are `broadcaster`, `hls_transcode`, and `entrypoint.sh` (GPU/FFmpeg orchestration).
- Webhook service is in `webhook/` (Go module).
- Observability stack config is under `observability/` with helper scripts in `scripts/observability/`.
- Documentation and runbooks are in `docs/`.
- Secrets templates and guidance are in `secrets/` (actual secrets are gitignored).

## Build, Test, and Development Commands
- `docker compose up -d` starts the main stack.
- `docker compose -f docker-compose.staging.yml up -d` runs the hardened staging stack.
- `docker compose build` rebuilds images (use `Dockerfile.hardened` via staging compose).
- `./init_secrets.sh` converts `.env` keys into `secrets/*.txt` files.
- `./test_security.sh` runs container hardening smoke tests.
- `./test_webhook.sh` runs webhook integration tests.

## Coding Style & Naming Conventions
- Go code follows `gofmt` (tabs, standard Go style) in `webhook/`.
- Bash scripts should remain POSIX/Bash compatible and keep `set -e` behavior where present.
- YAML uses 2‑space indentation; keep file keys lowercase unless required by external tools.
- Secrets follow `{profile}_{service}_key.txt` (e.g., `gaming_youtube_key.txt`).

## Testing Guidelines
- Tests are shell-based integration/smoke scripts in the repo root.
- Run tests after starting the relevant compose stack, preferably staging.
- If you add tests, follow the existing naming pattern `test_*.sh` and keep them idempotent.

## Commit & Pull Request Guidelines
- Follow conventional-style subjects (e.g., `feat:`, `fix:`, `docs:`) with concise, imperative summaries.
- PRs should include: scope summary, config changes (compose/nginx/profiles), and tests run with command output references.
- Link related issues and call out any required secret or migration steps.

## Security & Configuration Tips
- Never commit real secrets; use `secrets/*.txt` and mount at `/run/secrets/`.
- Use `profiles.yml.example` as the base for new profiles and keep stream keys out of YAML.
- For production changes, align with `docs/PRODUCTION_MIGRATION.md` and run the security tests.
