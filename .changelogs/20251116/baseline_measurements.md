# Baseline měření - Současný stav

**Datum:** 2025-01-16
**Profil:** gaming (YouTube + Twitch + Kick + X)

## Instrukce pro měření

1. Spustit produkční stack:
   ```bash
   docker compose up -d
   ```

2. Spustit typický stream z OBS (1080p60 @ 8 Mbps)

3. V samostatných terminálech spustit:

   **GPU metriky:**
   ```bash
   watch -n 1 'nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu --format=csv,noheader'
   ```

   **Počet FFmpeg procesů:**
   ```bash
   watch -n 1 'docker compose exec nginx-rtmp ps aux | grep ffmpeg | grep -v grep | wc -l'
   ```

   **CPU load:**
   ```bash
   htop
   ```

## Naměřené hodnoty (VYPLNIT RUČNĚ)

### GPU
- **Utilization:** __%
- **VRAM:** __ GB / 6 GB
- **Teplota:** __°C

### CPU
- **Load Average:** __
- **Top proces:** ffmpeg (__x instance)

### FFmpeg
- **Počet procesů:** __
- **RAM per proces:** ~__ MB

### Latence (změřeno stopkami)
- **OBS → YouTube:** ~__s
- **OBS → Twitch:** ~__s
- **OBS → Kick:** ~__s
- **OBS → X:** ~__s

### Pozorované problémy
- [ ] Frame drops
- [ ] Artifacts
- [ ] Buffering issues
- [ ] GPU throttling
- Další poznámky: __

---

## Poznámky
Tento baseline bude sloužit pro srovnání po implementaci Fáze 2 (single-process FFmpeg).
Očekávané zlepšení:
- GPU utilization: -40% až -60%
- Počet FFmpeg procesů: 4 → 1 (pro 4 služby)
- CPU load: -30% až -50%
