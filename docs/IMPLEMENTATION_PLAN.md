# Implementační plán: produkční hardening, bezpečnost, výkon a stabilita

> Datum: 2025-12-24

## 1) Cíle a rozsah
- Odstranit kritické bezpečnostní riziko spouštění shellu v `exec_publish` a sjednotit autorizaci přes webhook.
- Zajistit konzistentní provozní identitu uživatele (UID/GID) a přesné bezpečnostní testy.
- Zpřesnit logging a telemetrii (správný exit code, redakce stream key v logu).
- Omezit zbytečné exponované porty a snížit privilegia observability.
- Sjednotit produkční a staging konfiguraci (Dockerfile.hardened, secrets, read-only FS).
- Aktualizovat dokumentaci, README a CHANGELOG.

## 2) Bezpečnostní a architektonické změny (kritické → nízké)
1. **Odstranit shell v `exec_publish`**
   - V `nginx.conf` a `nginx.staging.conf` odstranit `/bin/bash -c` wrapper.
   - Spouštět `broadcaster` a `hls_transcode` přímo jako executable s argumenty.
2. **Webhook autorizace i pro produkci**
   - Doplnit `on_publish` a `on_publish_done` do `nginx.conf`.
   - Přidat `webhook` službu do `docker-compose.yml` s read-only FS a healthcheckem.
3. **Validace profilu a tvrdé odmítnutí neplatných názvů**
   - Přidat sanitizaci profilu do `broadcaster` a `hls_transcode` (regex: `[A-Za-z0-9_-]{1,50}`).
4. **Správné exit kódy FFmpeg**
   - Zapnout `pipefail` a číst `PIPESTATUS[0]`.
5. **Redakce stream keys v logu**
   - Redigovat výstup URL z FFmpeg logů v `broadcaster`.
6. **Observability bez Docker socketu**
   - Upravit `promtail` konfiguraci na statické logy.
   - Přidat mount logů NGINX a webhooku.
7. **Zamknout porty na localhost**
   - U interních služeb (Prometheus, Loki, Grafana, node-exporter, cAdvisor, exporters) použít `127.0.0.1:PORT:PORT`.
8. **Konzistence UID/GID a testů**
   - Nastavit `test_security.sh` tak, aby ověřoval NGINX worker uživatele (UID 1001).
9. **Reproducibilita buildů a runtime**
   - Opravit `Dockerfile.hardened` (curl v runtime, stat.xsl z builder stage, bez wget runtime).
   - Aktualizovat `Dockerfile` (FFmpeg release branch, VTS modul, konzistence).
10. **Dokumentace a README**
   - Přidat požadavek na driver pro CUDA 12.x (>=525.60.13).
   - Popsat secrets, webhook flow a bezpečnostní defaults.

## 3) Implementační kroky (detailní instrukce)
### Krok 3.1: Konfigurace NGINX
- Uprav `nginx.conf`:
  - Přidej `on_publish` a `on_publish_done` na webhook.
  - Odstraň `/bin/bash -c` u `exec_publish`.
- Uprav `nginx.staging.conf` obdobně.

### Krok 3.2: Docker Compose (produkce + staging)
- `docker-compose.yml`:
  - Přidej `webhook` službu (read-only, cap_drop, healthcheck, internal port).
  - Přepni `nginx-rtmp` build na `Dockerfile.hardened`.
  - Zapni `read_only`, `tmpfs`, `cap_drop`/`cap_add`, `no-new-privileges`.
  - Přidej `secrets` definice.
  - Přidej mount `/var/log/nginx` (např. `./logs/nginx`).
- `docker-compose.staging.yml`:
  - Odeber `docker.sock` z `promtail`.
  - Přidej mount pro `logs-staging/nginx` a `logs-staging/webhook`.
  - Uprav mapování portů observability na `127.0.0.1`.

### Krok 3.3: Skripty a logika
- `broadcaster`:
  - Přidej sanitizaci profilu.
  - `set -o pipefail` a čti `PIPESTATUS[0]`.
  - Rediguj output URL z FFmpeg logů.
- `hls_transcode`:
  - Přidej sanitizaci profilu.
  - `set -o pipefail` a čti `PIPESTATUS[0]`.
  - Zvaž `-map 0:a?` pro video‑only vstupy.
- `webhook/main.go`:
  - Akceptuj `application/json` i form-urlencoded.
  - Přidej volitelný log file output (`WEBHOOK_LOG_FILE`).

### Krok 3.4: Dockerfile hardening
- `Dockerfile.hardened`:
  - Přidej `curl` do runtime balíčků.
  - Přesuň `stat.xsl` download do builder stage a kopíruj do runtime.
  - Odstraň runtime `wget` instalaci.
- `Dockerfile`:
  - Přepni FFmpeg na release branch (např. `release/7.1`).
  - Přidej build NGINX VTS modul.

### Krok 3.5: Testy a ověření
- Spusť:
  - `./test_security.sh`
  - `./test_webhook.sh`
- Funkční test RTMP:
  - `ffmpeg -re -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 -f lavfi -i sine=frequency=1000:duration=30 -c:v h264_nvenc -c:a aac -f flv rtmp://localhost:1935/live/gaming`
- Load test (staging):
  - Paralelně spustit 3–5 streamů s různými profily a ověřit stabilitu NVENC/NVDEC.

### Krok 3.6: Dokumentace
- Aktualizovat `README.md` (driver requirements, secrets, webhook flow).
- Aktualizovat `CLAUDE.md` (UID 1001, produkční flow).
- Vytvořit/aktualizovat `CHANGELOG.md`.
- Přidat stručný report změn v `docs/IMPLEMENTATION_REPORT.md`.

## 4) Akceptační kritéria
- `exec_publish` nepoužívá shell; webhook autorizuje před spuštěním.
- Testy `test_security.sh` a `test_webhook.sh` projdou.
- NGINX worker běží jako `broadcaster` (UID 1001).
- Promtail bez Docker socketu a logy se sbírají z host volume.
- README a CLAUDE odpovídají realitě.

## 5) Rollback postup
- Vrátit `nginx.conf`/`docker-compose.yml` z předchozího commitu.
- Znovu spustit `docker compose up -d --build`.
