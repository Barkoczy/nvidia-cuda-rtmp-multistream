# Implementační plán: 100% produkční připravenost, NVENC a hardening

> Datum: 2025-12-24

## 0) Zdroje (ověřená dokumentace)
- Docker Compose GPU support (device reservations / capabilities).
- NVIDIA CUDA 12.8 release notes (minimální verze ovladačů a kompatibilita).

## 1) Cíle
1. **NVENC musí být funkční** na hostu i v kontejnerech (ověřeno testy).
2. **Odstranit veškeré legacy fallbacky** (žádné env klíče; pouze Docker secrets).
3. **Bezpečnost a stabilita**: read-only FS, minimal capabilities, validace profilu, žádné shell wrappery v NGINX.
4. **Observability bez Docker socketu** a s jednotným logováním.
5. **Dokumentace + testy**: jasné kroky, měřitelné výsledky, changelog.

## 2) NVENC – povinné ověření
### 2.1 Host ověření (musí projít)
1. `nvidia-smi -L` – GPU musí být dostupná.
2. `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi` – ověřit NVIDIA runtime.
3. Ověřit minimální driver kompatibilitu pro CUDA 12.x (dle release notes).

### 2.2 Container ověření (musí projít)
1. Do compose přidat `runtime: nvidia` + `deploy.resources.reservations.devices` pro služby s GPU.
2. V kontejneru spustit NVENC smoke test (FFmpeg testsrc + `h264_nvenc`).

## 3) Odstranění legacy fallbacků
1. `entrypoint.sh`: odstranit export do `/tmp/.env`.
2. `broadcaster`: odstranit env fallback; pouze `/run/secrets/*`.
3. `docker-compose.yml`: odstranit `env_file: .env`.
4. Dokumentace přepsat na **secrets-only**.

## 4) Bezpečnostní změny
1. `nginx.conf` + `nginx.staging.conf`: `on_publish` webhook + bezpečné `exec_publish` bez shell wrapperu.
2. Validace profilu v `broadcaster` i `hls_transcode`.
3. Přesné exit kódy FFmpeg (`PIPESTATUS[0]`).
4. Redakce stream key v logu.

## 5) Observability bez Docker socketu
1. Promtail na statické logy (broadcaster/nginx/webhook).
2. Log directories mountnout z hosta.
3. Exportéry pouze interně (bez veřejných portů).

## 6) Testy a zátěž
1. `docker compose -f docker-compose.staging.yml up -d --build`
2. `./test_security.sh` – **musí selhat**, pokud GPU/NVENC není dostupné.
3. `./test_webhook.sh`
4. Zátěžový test NVENC: `./scripts/load_test.sh`

## 7) Dokumentace a release
1. Update `README.md` (secrets-only + NVENC požadavky).
2. Update `SECURITY-BASELINE.md`, `SECRETS_MIGRATION.md`, `PHASE1_SUMMARY.md`, `PRODUCTION_MIGRATION.md`.
3. Update `CHANGELOG.md` a `docs/IMPLEMENTATION_REPORT.md`.
4. `git commit` + `git push`.

## 8) Akceptační kritéria
- NVENC dostupné v kontejneru (`nvidia-smi` + FFmpeg nvenc test).
- Všechny testy projdou bez varování.
- Secrets-only flow (žádné env fallbacky).
- Dokumentace aktuální a konzistentní.
