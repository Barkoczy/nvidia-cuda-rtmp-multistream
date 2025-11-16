Začnu tím, že ti dám **celý roadmap** v jedné odpovědi, ale rozsekám ho na „bloky“, které můžeš brát jako jednotlivé sezení / sprinty.
Ty sis mezitím udělal výborný výzkum (Analýza + ANALYZE.md), takže teď jde hlavně o **organizaci práce** krok za krokem.

---

## 0. Cíl a jak s plánem pracovat

**Hlavní cíl:**
Dostat se z PoC stavu k **bezpečnému, výkonnému a modernímu** streamovacímu backendu (NVENC, SRT, LL-HLS, MediaMTX, Go orchestrátor) v **3 fázích**:

1. **Fáze 1 – Zabezpečení a stabilizace** (P0)
2. **Fáze 2 – Výkon a observabilita**
3. **Fáze 3 – Re-platforming (MediaMTX + Go orchestrátor)**

👉 Doporučuji reálně dělat **jen jeden blok za druhým** (0.x → 1.x → 2.x → 3.x) a brát to jako checklist.

---

# BLOK 0 – PŘÍPRAVA (ještě nic neměníš „naostro“)

### 0.1 Vytvoř staging větev a staging stack

**Cíl:** Mít místo, kde můžeš dělat změny bez rizika pro „produkci“.

Kroky:

1. V repozitáři:

   * vytvoř větev, např.
     `feature/phase1-security`.
2. Zkopíruj `docker-compose.yml` na:

   * `docker-compose.staging.yml`
3. V `docker-compose.staging.yml`:

   * změň názvy služeb, např. `nginx-rtmp-staging`
   * změň mapování portů (RTMP, HTTP) – třeba:

     * `1936:1935` místo `1935:1935`
     * případně jiný HTTP port pro náhled.

✅ **Hotovo, když:**
Máš spuštěný staging stack `docker compose -f docker-compose.staging.yml up -d` a jsi schopný z OBS streamovat na staging RTMP URL.

---

### 0.2 Záloha současného stavu

**Cíl:** Když něco rozbiješ, vrátíš se jednoduše zpět.

Kroky:

1. Vytvoř si adresář `backup/YYYYMMDD`.
2. Zkopíruj do něj minimálně:

   * `nginx.conf`
   * `docker-compose.yml`
   * `Dockerfile`
   * `broadcaster`
   * `hls_transcode`
   * `entrypoint.sh`
   * `profiles.yml` / `profiles.yml.example`

✅ **Hotovo, když:**
Máš jeden adresář s kompletním snapshotem konfigurace, který se dá kdykoli vrátit.

---

### 0.3 Změř si baseline (výkon a chování „teď“)

**Cíl:** Ať později vidíš, že změny opravdu pomohly.

Kroky:

1. Na **aktuální produkční verzi** spusť typický stream (např. 1080p60 @ 8 Mbps).
2. Změř / zapiš:

   * `nvidia-smi` – vytížení GPU, VRAM, teplota
   * počet běžících `ffmpeg` procesů (`ps aux | grep ffmpeg | wc -l`)
   * CPU load
   * přibližnou end-to-end latenci (OBS → YouTube/Twitch).
3. Zapiš do `notes.md` v repu (klidně jen prostý text).

✅ **Hotovo, když:**
Máš pár konkrétních čísel (GPU %, počet ffmpeg procesů, latence).
Tyhle hodnoty budeš porovnávat po Fázi 2.

---

# BLOK 1 – FÁZE 1: ZABEZPEČENÍ A STABILIZACE

Cíl Fáze 1:

* **Zabít command injection** přes `exec_publish`.
* **Schovat stream klíče** do secrets.
* **Utáhnout kontejner** (read-only FS, drop capabilities).([OWASP Cheat Sheet Series][1])

---

## 1.1 Nahradit `exec_publish` → `on_publish` (webhook)

Tohle je **nejdůležitější krok** – opravuje kritickou RCE zranitelnost.

### Co uděláš:

1. Ve **staging** verzi `nginx.conf`:

   * najdi RTMP `application live { ... }`, kde je `exec_publish`/`exec_publish_done`.
   * tyto řádky **zakomentuj** (ale nemaž, ať je máš pro referenci).

2. Do stejné `application` sekce přidej:

   ```nginx
   application live {
       live on;

       # původní věci nech
       # ...

       on_publish      http://orchestrator:8080/api/v1/publish;
       on_publish_done http://orchestrator:8080/api/v1/publish_done;
   }
   ```

   (jméno hosta `orchestrator` bude název nové služby v docker-compose.)

3. Připrav **minimální Go webhook** (MVP) – zatím jen loguje a vrací 200:

   * Go server s handlerem:

     * `POST /api/v1/publish` → vypíše form data, vrátí 200
     * `POST /api/v1/publish_done` → taky 200

4. Přidej tento webhook jako **novou službu** do `docker-compose.staging.yml`:

   * image z vlastního Dockerfile (malý binary v Go)
   * expose port 8080 jen v interní síti (nepouštět ven).

👉 Inspiraci na jednoduchý Go HTTP server máš i v Analýze (část s orchestrátorem).

✅ **Hotovo, když:**

* Na stagingu při startu streamu vidíš v logu webhooku požadavky na `/publish`.
* RTMP stream funguje **i přesto**, že už nepoužíváš `exec_publish`.

> V této chvíli je command injection přes `$name` pryč – nginx žádný shell už nespouští.

---

## 1.2 Přesun stream klíčů do Docker Secrets

Cíl: **žádné klíče v env, žádné v .env souborech, žádné v ps aux.** ([Docker Documentation][2])

### Co uděláš:

1. V `docker-compose.staging.yml`:

   * odeber `environment:`, kde máš `_YOUTUBE_KEY`, `_TWITCH_KEY` atd.
2. Vytvoř adresář `secrets/` v repu.

   * uvnitř soubory: `youtube_key.txt`, `twitch_key.txt`, `kick_key.txt`, `x_key.txt`…
   * v každém souboru bude **jen samotný key**, nic víc.
3. Do `docker-compose.staging.yml` přidej:

   ```yaml
   services:
     nginx-rtmp-staging:
       # ...
       secrets:
         - youtube_key
         - twitch_key
         - x_key
         - kick_key

   secrets:
     youtube_key:
       file: ./secrets/youtube_key.txt
     twitch_key:
       file: ./secrets/twitch_key.txt
     x_key:
       file: ./secrets/x_key.txt
     kick_key:
       file: ./secrets/kick_key.txt
   ```
4. V `entrypoint.sh` / `broadcaster` (staging varianta):

   * místo práce s env a `.env`:

     ```bash
     YOUTUBE_KEY="$(cat /run/secrets/youtube_key)"
     ```
   * podobně pro ostatní služby.

✅ **Hotovo, když:**

* Staging běží, stream funguje a klíče se čtou ze `/run/secrets/...`.
* V `docker inspect` ani v `env` uvnitř kontejneru není vidět žádný stream key.

---

## 1.3 Hardening kontejneru (minimální, ale efektivní)

Best-practice z Docker/OWASP:

* běžet jako non-root,
* dropnout všechny capabilities kromě nutných,
* root FS read-only,
* secrets v dedikovaném mechanismu.([OWASP Cheat Sheet Series][1])

### Co uděláš:

1. V `docker-compose.staging.yml` u `nginx-rtmp-staging`:

   ```yaml
   read_only: true
   tmpfs:
     - /tmp
     - /var/log/broadcaster
     - /var/www/hls
   cap_drop:
     - ALL
   cap_add:
     - NET_BIND_SERVICE
   security_opt:
     - no-new-privileges:true
   user: "1000:1000"   # nebo uživatel 'broadcaster', pokud ho máš v image
   ```
2. Ověř, že:

   * všechna místa, kam něco zapisuješ (logy, HLS segmenty), jsou buď `tmpfs`, nebo explicitní volume.
3. Dlouhodobě: upravíš Dockerfile tak, aby finální image byla **co nejmenší** a neběžela jako root (můžeš se řídit Docker Security Cheat Sheet + best practices).([Docker Documentation][2])

✅ **Hotovo, když:**

* Kontejner na stagingu startuje s read-only root FS.
* Logy a HLS se normálně generují do tmpfs/volumes.
* `id` uvnitř kontejneru ukazuje non-root uživatele.

---

## 1.4 Smoke testy Fáze 1

**Cíl:** Ověřit, že bezpečnostní změny nerozbily základní funkci.

Kroky:

1. Na stagingu:

   * spusť stream z OBS na nový RTMP endpoint,
   * ověř, že se restreamuje na všechny aktivní platformy,
   * podívej se do logů:

     * nginx (error/access)
     * webhook (Go),
     * případně broadcaster/ffmpeg.
2. Pokud vše běží OK **na stagingu**, opakuj změny:

   * v produkčním `docker-compose.yml` a `nginx.conf`
     (stejný postup, ale raději po menších částech – nejdřív on_publish, potom secrets, potom hardening).

✅ **Hotovo, když:**
Produkcí prochází stream jako dřív, ale:

* neexistuje žádný `exec_publish`,
* klíče jsou jen v Docker Secrets,
* kontejner je zharděný.

Tím je **Fáze 1 splněná**.

---

# BLOK 2 – FÁZE 2: VÝKON A OBSERVABILITA

Teď jsi bezpečnější. Další krok:

* vidět, co se děje (observabilita),
* přestat dělat N-násobné dekódování (single-process ffmpeg).

---

## 2.1 Základní observabilita stack (Prometheus + Grafana + Loki)

Standardní kombinace pro logs/metrics: **Prometheus + Grafana + Loki**.([Medium][3])

### Co uděláš:

1. Do `docker-compose.staging.yml` přidej:

   * `prometheus`
   * `grafana`
   * `loki`
   * `promtail`/Alloy pro sběr logů z kontejnerů.
2. Přesměruj logy:

   * NGINX, webhook, ffmpeg (stdout/stderr) → do Loki.
3. V Grafaně:

   * vytvoř první dashboard:

     * CPU/RAM hosta,
     * logy z nginx a webhooku.

✅ **Hotovo, když:**
Otevřeš Grafanu a vidíš:

* metriky systému,
* logy stream serveru.

---

## 2.2 GPU a NGINX metriky

Cíl:

* sledovat NVENC/NVDEC, VRAM, teplotu,
* počet RTMP připojení, bitrate apod.

### Co uděláš:

1. Přidáš **dcgm-exporter** (NVIDIA DCGM) jako container – poskytuje GPU metriky pro Prometheus.([NVIDIA Developer][4])
2. Do NGINX build procesu doplníš `nginx-module-vts` a **nginx-vts-exporter**, který převede NGINX statistiky na Prometheus metriky.([packages.altlinux.org][5])

✅ **Hotovo, když:**
Na Grafaně vidíš:

* využití GPU (vč. NVENC/NVDEC, pokud to driver/DCGM ukazuje),
* počet RTMP připojení / traffic.

---

## 2.3 FFmpeg metriky

Cíl: vědět, **kolik ffmpeg procesů běží, jaké mají FPS, bitrate, drop frames**.

### Co uděláš:

1. Integruješ `ffmpeg-exporter` (viz Analýza + GitHub).([Scribd][6])
2. Upravíš spouštění ffmpeg tak, aby posílal `-progress` výstup:

   * exporter ten výstup parsuje a publikuje metriky do Promethea.

✅ **Hotovo, když:**
V Grafaně máš dashboard, kde vidíš:

* na profil/službu FPS, bitrate, případně drop frames.

---

## 2.4 Refaktoring FFmpeg na „single-process pipeline“

Tohle je **největší výkonnostní win** – eliminuješ N-násobné dekódování na jediném NVDEC.

### Co uděláš (staging, jeden profil jako pilot):

1. V `broadcaster` najdi místo, kde:

   * pro každý service děláš samostatný `ffmpeg ... &`.

2. Připrav jeden nový **ffmpeg příkaz** pro pilotní profil (např. `gaming`):

   * jednou bere `-hwaccel cuda -hwaccel_output_format cuda -i rtmp://localhost:1935/live/$PROFILE`,([NVIDIA Docs][7])
   * `-filter_complex` se `split` + `scale_cuda` pro různé rozlišení,
   * `-map` pro více výstupů (YouTube/Twitch/Kick/X),
   * NVENC parametry podle doporučení z Video Codec SDK (rozumný preset, bitrate, `-tune ll`).([NVIDIA Docs][8])

3. Otestuj to na stagingu jen pro tento jeden profil.

4. Sleduj v Grafaně:

   * GPU utilization,
   * počet ffmpeg procesů (teď by měl být 1 na profil),
   * FPS a stabilitu.

5. Když to funguje, rozšiř na další profily.

✅ **Hotovo, když:**

* Pro každý profil běží jen **jeden ffmpeg proces**,
* GPU vytížení klesne (oproti baseline z Bloku 0),
* streamy jsou stabilní.

---

# BLOK 3 – FÁZE 3: RE-PLATFORMING (Go orchestrátor + MediaMTX)

Tady už jde o **architektonický redesign** (větší projekt).

---

## 3.1 Go orchestrátor (plnohodnotný supervisor)

Cíl: Nahradit Bash logiku robustní Go službou, která:

* obsluhuje `on_publish` / `on_publish_done`,
* spouští ffmpeg příkazy (single-process pipeline),
* restartuje procesy při chybách,
* exportuje metriky do Promethea.

### Co má orchestrátor umět (MVP → plná verze):

1. HTTP API:

   * `POST /api/v1/publish`
   * `POST /api/v1/publish_done`
2. Čtení profilů z `profiles.yml` + klíčů z `/run/secrets/...`.
3. Sestavení ffmpeg příkazu pro konkrétní profil.
4. Spuštění ffmpeg přes `exec.CommandContext` + goroutine.
5. Evidence běžících procesů v mapě `map[profile]*Cmd`.
6. Restart logika (např. exponenciální backoff).
7. `/metrics` endpoint pro Prometheus (počet streamů, restarty…).

✅ **Hotovo, když:**
Na stagingu běží stream bez Bash `broadcaster`/`hls_transcode` – vše řeší Go orchestrátor.

---

## 3.2 Odstranění Bash skriptů

Když je orchestrátor stabilní:

1. V `entrypoint.sh` a dalších skriptech:

   * odstraň (nebo označ jako deprecated) volání `broadcaster`, `hls_transcode`.
2. V repozitáři:

   * přesuneš je třeba do `legacy/` složky.

✅ **Hotovo, když:**
Kontejner běží i bez těchto skriptů, a neexistuje žádná cesta, která by je používala.

---

## 3.3 Nasazení MediaMTX místo nginx-rtmp

MediaMTX = lehký „media router“: SRT / WebRTC / RTSP / RTMP / LL-HLS v jednom, napsaný v Go.([GitHub][9])

### Co uděláš:

1. Přidej MediaMTX jako novou službu do `docker-compose.staging.yml`.
2. Konfiguruj:

   * ingest: SRT + RTMP,
   * výstup: LL-HLS/WebRTC (základní config podle jejich README / návodů).([GitHub][9])
3. Nejprve: nech RTMP ingest pořád přes nginx-rtmp, ale MediaMTX použij pro experimentální ingest/zrcadlení.
4. Postupně:

   * přepni OBS ingest na SRT → MediaMTX,
   * uprav orchestrátor, aby četl stream z MediaMTX (např. přes RTSP) místo nginx-rtmp.

✅ **Hotovo, když:**

* NGINX-RTMP už není nutný pro ingest, vše jde přes MediaMTX.

---

## 3.4 LL-HLS / WebRTC pro diváky

Cíl: Zmenšit latenci pro diváky (1–4 s místo 10–15 s).([Aikido][10])

### Co uděláš:

1. V MediaMTX povolíš:

   * LL-HLS,
   * případně WebRTC.
2. Připravíš jednoduchý testovací player (HTML stránka s HLS.js / WebRTC klientem).
3. Změříš:

   * latence RTMP → HLS (starý stav),
   * SRT → LL-HLS,
   * SRT → WebRTC.

✅ **Hotovo, když:**
Máš funkční LL-HLS/WebRTC stream a reálně nižší latenci.

---

# ZÁVĚR – Co dělat „hned teď“

Abys nemusel přemýšlet, kde začít, tady je **mini-checklist na nejbližší dny**:

1. **Blok 0**

   * [ ] Větev `feature/phase1-security`
   * [ ] `docker-compose.staging.yml` + staging stack
   * [ ] Backup konfigurace
   * [ ] Změřený baseline (GPU, počet ffmpeg, latence)

2. **Fáze 1 (Blok 1) – jen staging**

   * [ ] `exec_publish` → `on_publish` + jednoduchý Go webhook
   * [ ] Docker Secrets pro klíče
   * [ ] Hardening kontejneru (read_only, drop capabilities, non-root)
   * [ ] Smoke test na stagingu
   * [ ] Až pak opatrně přenést na produkci

3. **Teprve potom Fáze 2 a 3** – na ty už máš roadmapu výše, a můžeš se na ně vrhnout, jakmile budeš mít bezpečnost stabilně hotovou.

---

Kdykoli budeš chtít, můžeme vzít **konkrétní krok** (např. „1.1 on_publish webhook“ nebo „2.4 single-process ffmpeg“) a já ti ho rozepíšu úplně do detailu: jak přesně může vypadat Go kód, docker-compose bloky, testovací scénáře atd. Stačí napsat, na který blok se chceš zaměřit jako první v praxi.

[1]: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html?utm_source=chatgpt.com "Docker Security Cheat Sheet"
[2]: https://docs.docker.com/engine/security/?utm_source=chatgpt.com "Docker Engine security"
[3]: https://medium.com/%40neamulkabiremon/production-ready-observability-with-prometheus-loki-grafana-2ce1ba9f7423?utm_source=chatgpt.com "Production-Ready Observability with Prometheus, Loki & ..."
[4]: https://developer.nvidia.com/video-codec-sdk?utm_source=chatgpt.com "NVIDIA Video Codec SDK"
[5]: https://packages.altlinux.org/en/sisyphus/srpms/mediamtx/?utm_source=chatgpt.com "Package mediamtx: Information"
[6]: https://www.scribd.com/document/520086359/Using-FFmpeg-with-NVIDIA-GPU-Hardware-Acceleration-v01-4?utm_source=chatgpt.com "Using Ffmpeg With Nvidia Gpu Hardware Acceleration"
[7]: https://docs.nvidia.com/video-technologies/video-codec-sdk/12.0/ffmpeg-with-nvidia-gpu/index.html?utm_source=chatgpt.com "Using FFmpeg with NVIDIA GPU Hardware Acceleration"
[8]: https://docs.nvidia.com/video-technologies/video-codec-sdk/12.2/index.html?utm_source=chatgpt.com "NVIDIA Video Codec SDK v12.2"
[9]: https://github.com/bluenviron/mediamtx?utm_source=chatgpt.com "bluenviron/mediamtx: Ready-to-use SRT / WebRTC / RTSP ..."
[10]: https://www.aikido.dev/blog/container-security-best-practices?utm_source=chatgpt.com "Container Security Best Practices & Checklist"
