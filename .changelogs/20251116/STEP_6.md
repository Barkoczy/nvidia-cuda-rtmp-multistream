## 1. Stabilizace po Phase 1 a příprava na Phase 2

1. **Ověření produkčního stavu po nasazení Phase 1**

    - Spustit produkční stack podle `docs/PRODUCTION_MIGRATION.md`.

    - Zkontrolovat:

        - běh všech služeb (`docker ps`, stav RTMP, webhook/orchestrator),

        - funkčnost ingestu z OBS → RTMP endpoint,

        - funkčnost restreamu na všechny aktivní platformy.

    - Zapsat aktuální metriky (GPU, CPU, počet `ffmpeg` procesů, latence) do `baseline_measurements.md` jako „post-Phase1 baseline“.

2. **Uzavření Phase 1 v Gitu**

    - Vytvořit finální commit pro Phase 1 (pokud ještě není).

    - Vytvořit tag např. `v1.0-phase1-complete` pro jednoznačný návratový bod.

    - Ujistit se, že `docs/PHASE1_SUMMARY.md`, `docs/SECRETS_MIGRATION.md`, `docs/CONTAINER_HARDENING.md`, `docs/PRODUCTION_MIGRATION.md` jsou aktuální vůči reálné konfiguraci.

3. **Vyčištění a sjednocení konfigurace**

    - Zajistit, aby staging i produkce:

        - používaly stejný image (tag/Digest),

        - měly konzistentní `nginx.conf`/`nginx.staging.conf` (liší se pouze porty, ne bezpečnostní logika),

        - používaly dokonalou shodu v oblasti Docker Secrets a hardening nastavení.


---

## 2. Phase 2 – Observabilita (monitoring, logování, metriky)

### 2.1 Základní observability stack (Prometheus + Grafana + Loki)

4. **Nasazení Prometheus**

    - Přidat službu `prometheus` do `docker-compose.staging.yml`:

        - bind mount pro `prometheus.yml`,

        - persistentní volume pro data.

    - Do `prometheus.yml` přidat scrape joby:

        - pro samotný orchestrátor/webhook (pokud exportuje `/metrics`),

        - pro node-exporter/cadvisor nebo ekvivalentní exporter pro hostitele. ([prometheus.io](https://prometheus.io/docs/introduction/first_steps/?utm_source=chatgpt.com "First steps with Prometheus"))

5. **Nasazení Grafana**

    - Přidat službu `grafana` do `docker-compose.staging.yml`.

    - Nastavit Prometheus jako primary data source.

    - Vytvořit základní dashboard:

        - CPU load hostitele,

        - RAM usage,

        - počet běžících kontejnerů,

        - jednoduchý panel pro „počet běžících streamů“ (pokud existuje metrika).

6. **Nasazení Loki + Promtail (nebo ekvivalentního log collectoru)**

    - Přidat služby `loki` a `promtail` (nebo obdobný stack).

    - Konfigurovat promtail:

        - sběr logů z Docker socketu nebo z konkrétních log files (NGINX, orchestrátor, broadcaster),

        - přidat labels: `service`, `profile`, `env` (staging/production).

    - V Grafaně:

        - nakonfigurovat Loki data source,

        - vytvořit základní log dashboard (filtrování podle služby/profilu).


### 2.2 GPU metriky

7. **Implementace GPU exportéru**

    - Nasadit DCGM exporter nebo jiný NVIDIA exporter jako kontejner:

        - mount GPU zařízení,

        - přidat scrape job do Promethea.

    - Monitorovat:

        - `gpu_utilization`, `memory_used`, `encoder/decoder utilization` (podle exportéru),

        - teplotu GPU.

8. **Kontrolní dashboard pro GPU**

    - V Grafaně vytvořit dashboard:

        - časová řada využití GPU v čase,

        - VRAM usage,

        - teplota,

        - počet aktivních FFmpeg procesů (kombinace GPU + procesů z jiné metriky).


### 2.3 NGINX/RTMP metriky

9. **NGINX statistiky**

    - Aktivovat vhodný status modul (např. VTS nebo stub_status) v NGINX build/config.

    - Přidat NGINX exporter, který:

        - čte metriky z NGINX status endpointu,

        - vystavuje je pro Prometheus (RTMP connections, traffic, HTTP requests).

10. **Dashboard pro RTMP/HTTP**

    - Vytvořit panel:

        - počet současných RTMP publisherů,

        - bitrate/traffic per application,

        - HTTP request rate pro health-check a HLS/HTTP endpointy (pokud jsou relevantní).


### 2.4 FFmpeg metriky

11. **Zavedení FFmpeg metrik**

    - Upravit spouštění FFmpeg procesů (broadcaster/orchestrátor):

        - přidat `-progress` na lokální TCP/UNIX socket nebo pipe,

        - použít FFmpeg exporter, který tento výstup parsuje a generuje Prometheus metriky.

    - Pro každý výstup označit metriky labels:

        - `profile`,

        - `service` (youtube/twitch/…),

        - příp. `resolution`.

12. **Performance dashboard FFmpeg**

    - Grafana panely:

        - FPS per stream,

        - aktuální video bitrate per stream,

        - dropnuté snímky (pokud jsou dostupné),

        - počet aktivních FFmpeg procesů vs. počet aktivních profilů.


### 2.5 Alerting

13. **Prometheus alert rules**

    - Definovat základní alerty:

        - GPU utilization > X % po dobu Y minut,

        - žádný běžící FFmpeg pro aktivní profil (možný pád procesu),

        - žádné RTS/RTMP connection v produkci delší dobu (podle use-casu),

        - nízký disk space pro logy/HLS (pokud relevantní).

    - Integrovat Alertmanager s notifikačním kanálem (e-mail, Slack, atd.).

14. **Test alertů**

    - Uměle vyvolat situace (např. kill jednoho FFmpeg procesu, zastavit ingest) a ověřit, že alerty reagují dle očekávání.


---

## 3. Phase 2 – Výkon (optimalizace pipeline a NVENC)

### 3.1 Analýza současné pipeline

15. **Korelace baseline s novými metrikami**

    - Porovnat data z `baseline_measurements.md` s metrikami z Promethea:

        - skutečná GPU load při typickém streamu,

        - počet FFmpeg procesů na profil,

        - latence obs → cílová platforma.

16. **Identifikace bottlenecků**

    - Zjistit:

        - zda je limitujícím faktorem GPU (NVENC/VRAM) nebo CPU,

        - které profily/služby mají největší dopad na zdroje.


### 3.2 Single-process FFmpeg pipeline (multi-output)

17. **Pilotní profil se single-process pipeline**

    - Na stagingu vybrat jeden profil (např. `gaming`).

    - V broadcasteru/orchestrátoru upravit pipeline:

        - jeden `ffmpeg` vstup: `-hwaccel cuda -i rtmp://..../$profile`,

        - `-filter_complex` se `split` + `scale_cuda`/`scale_npp` pro různá rozlišení,

        - více `-map` výstupů pro jednotlivé služby (YouTube, Twitch, …),

        - nastavit parametry NVENC (preset, bitrate, rc mód) podle doporučení NVIDIA pro daný use-case. ([prometheus.io](https://prometheus.io/docs/introduction/first_steps/?utm_source=chatgpt.com "First steps with Prometheus"))

18. **Validační test pilotního profilu**

    - Spustit dlouhodobější test (např. 1–2 hodiny).

    - Vyhodnotit:

        - využití GPU/CPU vs. původní stav,

        - stabilitu (pády ffmpeg procesů),

        - kvalitu výstupu (subjektivně + bitrate z metrik),

        - latenci.

19. **Rozšíření na další profily**

    - Postupně aplikovat single-process pipeline na další profily.

    - U každého profilu provést základní test:

        - stresový test s plným počtem aktivních platforem,

        - hlídání hardwarových limitů (počet NVENC sessions, VRAM).


### 3.3 Optimalizace HLS transkódování

20. **Revize HLS profilu**

    - V `hls_transcode` (nebo v Go orchestrátoru, pokud se HLS přesune tam) upravit:

        - video filtry na `scale_npp` (případně zůstat u `scale_cuda`, pokud je výkon akceptovatelný),

        - přechod z CBR na VBR (lepší kvalita při stejném průměrném bitrate),

        - odstranění zbytečných `-threads` parametrů u NVENC (hardware enkodér).

21. **Test HLS pipeline**

    - Ověřit:

        - segment time, playlist latenci,

        - kompatibilitu s hráči (HLS klienti),

        - dopad na GPU load.


### 3.4 RTMP/NGINX tuning

22. **Snížení latence**

    - Upravit NGINX RTMP parametry:

        - snížit buffer,

        - případně upravit `drop_idle_publisher` a další timeouty.

    - Změřit latenci end-to-end po úpravě.

23. **Zátěžové testy**

    - Simulovat více současných ingestů (např. několik OBS instancí nebo replay test).

    - Ověřit stabilitu a chování systému pod vyšší zátěží.


---

## 4. Phase 3 – Re-platforming (Go orchestrátor + MediaMTX + moderní protokoly)

### 4.1 Go orchestrátor – plnohodnotná náhrada bash skriptů

24. **Rozšíření stávajícího Go webhooku na orchestrátor**

    - Navrhnout v Go:

        - struktury pro profily (načítání z `profiles.yml`),

        - správu procesů (start/stop/restart FFmpeg),

        - in-memory state mapu (`profile → běžící proces`),

        - `/metrics` endpoint pro Prometheus (počty streamů, restarty, chyby).

    - Integrovat čtení Docker Secrets přímo v Go (čtení z `/run/secrets/...`).

25. **Migrace logiky z bash do Go**

    - Postupně přesunout:

        - generování FFmpeg argumentů,

        - single-process multi-output logiku,

        - error-handling (restart s backoffem).

    - Bash skripty ponechat pouze jako fallback/legacy pro případný rollback.

26. **Plné přepnutí na Go orchestrátor**

    - V NGINX RTMP konfiguraci používat výhradně `on_publish` → Go orchestrátor.

    - Zajistit, aby žádný `exec_publish` už nespouštěl bash skripty (kromě případného dočasného fallbacku v legacy režimu).


### 4.2 Integrace MediaMTX

27. **Nasazení MediaMTX jako paralelního media serveru**

    - Přidat `mediamtx` službu do docker-compose:

        - základní config s podporou RTMP, SRT, LL-HLS, WebRTC. ([app.daily.dev](https://app.daily.dev/posts/ercyflehj?utm_source=chatgpt.com "bluenviron/mediamtx: Ready-to-use SRT / WebRTC / RTSP ..."))

    - Zpočátku používat MediaMTX pouze jako mirror/experimentální ingest vedle NGINX RTMP.

28. **Postupný přechod ingestu na MediaMTX**

    - Nastavit OBS ingest na SRT→MediaMTX nebo RTMP→MediaMTX.

    - Přizpůsobit Go orchestrátor, aby jako zdroj používal stream z MediaMTX (RTSP/RTMP/SRT podle designu).

    - Ověřit kompatibilitu a latenci.

29. **Decommission NGINX RTMP (po stabilizaci MediaMTX)**

    - Po delším období stabilního provozu:

        - odstranit závislost na NGINX RTMP,

        - nechat NGINX případně jen jako HTTP reverse proxy / TLS terminátor (pokud je potřeba).


### 4.3 Low-latency výstupy (LL-HLS / WebRTC)

30. **Aktivace LL-HLS / WebRTC v MediaMTX**

    - V konfiguraci MediaMTX povolit LL-HLS a/nebo WebRTC.

    - Připravit testovací player (HTML stránka s HLS.js / WebRTC klientem).

31. **Měření latence a kvality**

    - Porovnat:

        - latenci RTMP→YouTube/Twitch (klasický model),

        - latenci SRT→LL-HLS / WebRTC pro vlastní přehrávač.

    - Vyhodnotit, pro jaké use-casy je LL-HLS/WebRTC vhodné (např. interaktivní streamy, interní monitoring).


### 4.4 CI/CD a automatizace

32. **CI/CD pipeline**

    - Vytvořit pipeline (např. GitHub Actions/GitLab CI) pro:

        - build Docker image (multi-stage, hardened),

        - security scanning (container image scan),

        - automatizované testy (lint, základní integrační test).

33. **Automatizované nasazení**

    - Připravit skripty nebo pipeline joby pro:

        - nasazení na staging,

        - smoke testy (včetně bezpečnostních testů z Phase 1),

        - řízené nasazení na produkci (s možností rollbacku na předchozí tag).


---

## 5. Shrnutí logiky pořadí kroků

1. **Stabilizovat a uzavřít Phase 1** (validace, baseline, tagy).

2. **Vybudovat observabilitu** (Phase 2 – monitoring/logy/FFmpeg/GPU/alerting).

3. **Optimalizovat výkon** (single-process pipeline, HLS tuning, RTMP/NGINX tuning).

4. **Re-platformovat orchestraci a media server** (Go orchestrátor + MediaMTX, moderní protokoly, low-latency výstup).

5. **Zautomatizovat nasazení a testy** (CI/CD, security scanning, opakovatelný deployment).


Každý blok by měl být dokončen a ověřen (funkčně i metrikami) před přechodem na další blok.
