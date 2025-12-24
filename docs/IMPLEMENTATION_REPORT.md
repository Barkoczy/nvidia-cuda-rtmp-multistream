# Implementační report

> Datum: 2025-12-24

## Shrnutí změn
- Odstraněn `/bin/bash -c` wrapper v `exec_publish` a sjednocena webhook autorizace pro produkci i staging.
- Přidána validace názvu profilu v `broadcaster` a `hls_transcode`.
- Opraveno měření exit kódu FFmpeg (`PIPESTATUS[0]`) a přidána redakce stream key v logu.
- Promtail přepnut na statické logy (bez Docker socketu) + přidán sběr logů webhook/NGINX.
- Hardened runtime upraven na `curl` healthcheck a `stat.xsl` z builder stage.
- Upravena dokumentace (README/CLAUDE/SECURITY-BASELINE) a přidán CHANGELOG.

## Testy
- `docker compose -f docker-compose.staging.yml up -d --build` → **prošlo** (stack nastartoval, lokální porty bez konfliktu po úpravě mapování).
- `./test_security.sh` → **prošlo** s varováním: GPU nebylo detekováno (NVENC v tomto prostředí nedostupné).
- `./test_webhook.sh` → **prošlo** (validace profilu funguje, publish/publish_done OK).

## Poznámky
- Pokud je potřeba NVENC, ověř dostupnost GPU a nvidia-container-runtime na hostu.
- Zátěžové testy (více paralelních RTMP streamů) nebyly spuštěny kvůli nedostupné GPU akceleraci v prostředí.
- `docker compose` hlásí chybějící `.env` (legacy fallback). Pro odstranění varování vytvoř prázdný `.env` nebo používej secrets-only flow.
