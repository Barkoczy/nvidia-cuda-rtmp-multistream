# Changelog

## [Unreleased] - 2025-12-24
### Security
- Removed shell wrappers from NGINX exec_publish and enforced webhook authorization.
- Added strict profile name validation in broadcaster and HLS scripts.
- Dropped Docker socket from promtail and locked observability ports to localhost.

### Stability
- Fixed FFmpeg exit code reporting and added safe redaction in logs.
- Improved webhook request parsing to support form and JSON payloads.

### Operations
- Added webhook file logging and updated promtail to ingest webhook/nginx logs.
- Hardened Dockerfile runtime dependencies (curl for healthcheck, stat.xsl from builder).
- Updated tests and documentation for UID 1001 and hardened production flow.
