# Implementační report

> Datum: 2025-12-24

## Shrnutí změn
- NVENC je povinný: `entrypoint.sh` nyní ověřuje GPU a spouští FFmpeg NVENC smoke test (hard fail při chybě).
- Odstraněn runtime fallback na env klíče (`/tmp/.env` pryč, `broadcaster` pouze `/run/secrets/*`).
- Compose GPU runtime sjednocen na `runtime: nvidia` + device reservations.
- Doplněna runtime závislost `libva-x11-2` pro FFmpeg.
- Přidán zátěžový skript `scripts/load_test.sh` a aktualizována dokumentace (secrets-only).
- Aktualizován `docs/GPU.md` dle aktuálního hostu.

## Testy
- `docker compose -f docker-compose.staging.yml up -d --build` → **OK**
- `docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi` → **OK**
- `./test_security.sh` → **OK** (NVENC encode test prošel)
- `./test_webhook.sh` → **OK**
- `./scripts/load_test.sh` → **FAIL** při defaultu (3×720p) kvůli obsazené VRAM (`/app/llama-server`, ~5847/6144 MiB)
- `STREAMS=1 RESOLUTION=640x360 DURATION=10 ./scripts/load_test.sh` → **OK**

## Poznámky
- Pro plný zátěžový test uvolni VRAM (zastavit `/app/llama-server`) nebo sniž `STREAMS/RESOLUTION`.
- Compose schema v tomto prostředí odmítá `device_requests`; GPU je vynucena přes `runtime: nvidia` + `deploy.resources.reservations.devices`.
