# Changelog

## [Unreleased] - 2025-12-24
### Security
- Removed shell wrappers from NGINX exec_publish and enforced webhook authorization.
- Added strict profile name validation in broadcaster and HLS scripts.
- Dropped Docker socket from promtail and locked observability ports to localhost.
- Removed all environment-variable stream key fallbacks (secrets-only runtime).

### Stability
- Fixed FFmpeg exit code reporting and added safe redaction in logs.
- Improved webhook request parsing to support form and JSON payloads.
- Enforced NVENC availability at startup with FFmpeg smoke test and hard failure if missing.

### Operations
- Added webhook file logging and updated promtail to ingest webhook/nginx logs.
- Hardened Dockerfile runtime dependencies (curl for healthcheck, stat.xsl from builder).
- Updated tests and documentation for UID 1001 and hardened production flow.
- Added NVENC load test script and GPU/NVENC validation in security tests.
- Updated Compose GPU configuration (runtime + device reservations) and secrets-only docs.
