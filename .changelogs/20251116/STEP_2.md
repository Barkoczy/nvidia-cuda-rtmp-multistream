Perfektní – to, co jsi poslal, je už v podstatě **hotový detailní návod pro Blok 0 a Blok 1.1**.
Nebudu ti to jen přepisovat, ale **navážu na stejný styl** a rozepíšu ti **další kroky Fáze 1** (1.2, 1.3, 1.4) stejně konkrétně krok za krokem.

👉 Tuhle odpověď ber jako pokračování:

* Ty máš **Blok 0 + 1.1** už rozpracované (staging, backup, baseline, webhook).
* Já teď doplním **Blok 1.2 (Docker Secrets)**, **1.3 (Hardening)** a **1.4 (Smoke testy + přenos do produkce)** ve stejné úrovni detailu.
* Další odpovědi pak můžeme věnovat Fázi 2 a 3.

---

## BLOK 1.2 – Docker Secrets (bezpečné uložení stream klíčů)

**Cíl:**
Dostat stream klíče z `.env` / `environment:` proměnných do **Docker secrets**, aby:

* nebyly vidět v `docker inspect` / `env`,
* neležely na disku v plain-text `.env`,
* nebyly v logách ani v `ps aux`.

### 1.2.1: Připrav adresář pro secrets (⏱️ 5–10 minut)

V rootu projektu (např. `/home/ubuntu/services/nvidia-cuda-rtmp-multistream`):

```bash
mkdir -p secrets
chmod 700 secrets
```

Vytvoř soubory pro jednotlivé platformy:

```bash
echo "TVUJ_YOUTUBE_KEY" > secrets/youtube_key.txt
echo "TVUJ_TWITCH_KEY"  > secrets/twitch_key.txt
echo "TVUJ_KICK_KEY"    > secrets/kick_key.txt
echo "TVUJ_X_KEY"       > secrets/x_key.txt
```

> ✏️ Do těch souborů napiš **jen samotný klíč** (bez uvozovek, bez `KEY=`).

Zajisti, že `secrets/` nebude commitnutý do Gitu:

```bash
echo "secrets/" >> .gitignore
```

✅ **Checkpoint 1.2.A:**
Adresář `secrets/` existuje, obsahuje `*_key.txt`, je v `.gitignore`.

---

### 1.2.2: Přidej secrets do `docker-compose.staging.yml` (⏱️ 10–15 minut)

V `docker-compose.staging.yml` najdi definici `nginx-rtmp-staging` a doplň tam blok `secrets:`:

```yaml
services:
  nginx-rtmp-staging:
    build:
      context: .
      args:
        - USE_NVIDIA=true
    ports:
      - "1936:1935"
      - "8081:8080"
    container_name: nginx-rtmp-staging
    # env_file:      # postupně budeš odstraňovat stream klíče z env
    #   - .env
    environment:
      NVIDIA_VISIBLE_DEVICES: all
      NVIDIA_DRIVER_CAPABILITIES: all
    volumes:
      - ./logs-staging:/var/log/broadcaster
      - ./profiles.yml:/etc/broadcaster/profiles.yml
      - ./nginx.staging.conf:/usr/local/nginx/conf/nginx.conf
    secrets:
      - youtube_key
      - twitch_key
      - kick_key
      - x_key
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped

secrets:
  youtube_key:
    file: ./secrets/youtube_key.txt
  twitch_key:
    file: ./secrets/twitch_key.txt
  kick_key:
    file: ./secrets/kick_key.txt
  x_key:
    file: ./secrets/x_key.txt
```

> Poznámka: u Docker Compose (v2) se `secrets:` chová podobně jako ve Swarmu – uvnitř kontejneru se objeví jako soubory v `/run/secrets/...`.

✅ **Checkpoint 1.2.B:**
`docker-compose.staging.yml` obsahuje blok `secrets:` u služby i globálně dole.

---

### 1.2.3: Úprava `entrypoint.sh` / `broadcaster`, aby četly secrets (⏱️ 20–30 minut)

Teď potřebuješ **nahradit čtení klíčů z env** za čtení souborů v `/run/secrets`.

Najdi v `entrypoint.sh` nebo `broadcaster` logiku typu:

```bash
# Příklad – něco jako:
YOUTUBE_KEY="${YOUTUBE_KEY:-}"
TWITCH_KEY="${TWITCH_KEY:-}"
# nebo generování /etc/broadcaster/.env z env proměnných
```

Tu část nech jako fallback, ale pro staging přidej explicitní čtení z secrets:

```bash
# Čtení streaming klíčů z Docker Secrets (pokud existují)
if [ -f "/run/secrets/youtube_key" ]; then
  YOUTUBE_KEY="$(cat /run/secrets/youtube_key)"
fi

if [ -f "/run/secrets/twitch_key" ]; then
  TWITCH_KEY="$(cat /run/secrets/twitch_key)"
fi

if [ -f "/run/secrets/kick_key" ]; then
  KICK_KEY="$(cat /run/secrets/kick_key)"
fi

if [ -f "/run/secrets/x_key" ]; then
  X_KEY="$(cat /run/secrets/x_key)"
fi
```

Důležité:

* NELOGUJ hodnoty těch proměnných.
* V logu můžeš maximálně logovat, že klíč byl načten („YouTube key loaded from secret“), ale ne jeho hodnotu.

Pak zkontroluj, zda se tyto proměnné používají při skládání výstupních RTMP URL, např. něco jako:

```bash
OUTPUT_URL_YT="rtmp://a.rtmp.youtube.com/live2/${YOUTUBE_KEY}"
```

✅ **Checkpoint 1.2.C:**
Kód FFMPEG / broadcasteru používá klíče z proměnných, které se naplňují z `/run/secrets`.

---

### 1.2.4: Otestuj staging a ověř, že klíče nejsou vidět (⏱️ 20–30 minut)

1. Restartuj staging stack:

```bash
docker compose -f docker-compose.staging.yml down
docker compose -f docker-compose.staging.yml up --build -d
```

2. Ověř, že se secrets mountují:

```bash
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging ls /run/secrets
# Očekáváš: youtube_key, twitch_key, kick_key, x_key
```

3. Ověř, že nejsou v env:

```bash
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging env | grep -i key
# Ideálně nic nenajde, nebo jen jiné technické proměnné, ne stream klíče
```

4. Spusť testovací stream ze staging OBS (RTMP na port 1936) a ověř:

   * YouTube/Twitch atd. dostanou stream,
   * v logu broadcasteru / orchestrátoru vidíš, že se připojil.

✅ **Checkpoint 1.2.D:**
Staging funguje, stream klíče jsou jen v `/run/secrets`, nejsou v `env` ani v `docker inspect`.

> Až bude staging stabilní, stejný postup můžeš přenést do produkčního `docker-compose.yml`.

---

## BLOK 1.3 – Hardening kontejneru

**Cíl:**
I když se někdo dostane do kontejneru, bude mít **co nejméně možností** (princip least privilege, best practices pro container security).

### 1.3.1: Ověř, jakého uživatele kontejner používá teď (⏱️ 5 minut)

Na stagingu:

```bash
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging id
```

Pokud vidíš něco jako `uid=0(root) gid=0(root)`, běžíš jako root → špatně.

Z Dockerfile / docker-compose zjisti, jestli už nějaký `USER` je nastavený (např. `broadcaster`).

---

### 1.3.2: Nastav non-root uživatele (⏱️ 15–30 minut)

**Varianta A – už v image máš usera** (např. v Dockerfile):

```dockerfile
RUN groupadd -r broadcaster && useradd -r -g broadcaster broadcaster
USER broadcaster:broadcaster
```

Pak stačí v `docker-compose.staging.yml` nic nenastavovat, nebo explicitně uvést:

```yaml
user: "broadcaster"
```

**Varianta B – raději použiješ UID/GID**:

```yaml
user: "1000:1000"
```

> Důležité: non-root user musí mít práva zápisu na logy, HLS output atd. → proto je fajn použít volume/tmpfs s vlastními vlastníky nebo `chown` ve startu.

Otestuj:

```bash
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging id
# Musíš vidět ne-root uživatele
```

✅ **Checkpoint 1.3.A:**
Kontejner neběží jako root.

---

### 1.3.3: Read-only root filesystem + tmpfs (⏱️ 20–30 minut)

V `docker-compose.staging.yml` pro `nginx-rtmp-staging` přidej:

```yaml
    read_only: true
    tmpfs:
      - /tmp
      - /var/log/broadcaster
      - /var/www/hls
```

* `read_only: true` → root FS je jen pro čtení.
* Všechno, kam se zapisuje (logy, HLS segmenty), musí být buď:

  * volume (např. `./logs-staging:/var/log/broadcaster`), nebo
  * tmpfs (jak výše).

Pokud už mapuješ `./logs-staging:/var/log/broadcaster`, nepotřebuješ tmpfs pro logy, ale nesmí to být uvnitř read-only části.

Otestuj:

```bash
docker compose -f docker-compose.staging.yml up -d
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging touch /testfile
# -> očekáváš Permission denied (na root FS)
```

✅ **Checkpoint 1.3.B:**
Root FS je read-only, ale logy a HLS soubory se stále zapisují (odebírají se z příslušných volumes/tmpfs).

---

### 1.3.4: Drop capabilities + no-new-privileges (⏱️ 10–15 minut)

Doplň k `nginx-rtmp-staging`:

```yaml
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
```

* `cap_drop: ALL` → odstraníš všechny Linux capabilities.
* `NET_BIND_SERVICE` → potřebuješ pro poslouchání na portech < 1024 (pokud je používáš; když budeš mít jen 1935, 8080, tak to není nutné, ale neuškodí).
* `no-new-privileges:true` → zabrání získání nových privilegií (např. setuid binárky).

Otestuj, že se kontejner spouští a NGINX normálně naslouchá na portech.

✅ **Checkpoint 1.3.C:**
Kontejner běží se `cap_drop: ALL`, případně `NET_BIND_SERVICE` a `no-new-privileges:true`.

---

## BLOK 1.4 – Smoke testy + přenesení změn do produkce

Až staging:

* používá `on_publish`,
* klíče ze secrets,
* běží jako non-root, s read-only FS a omezenými capabilities,

pak je čas to **ověřit** a **opatrně přenést do produkce**.

### 1.4.1: End-to-end test na stagingu (⏱️ 30–45 minut)

1. Proveď kompletní restart:

```bash
docker compose -f docker-compose.staging.yml down
docker compose -f docker-compose.staging.yml up --build -d
```

2. Sleduj logy:

```bash
docker compose -f docker-compose.staging.yml logs -f nginx-rtmp-staging orchestrator
```

3. Z OBS:

* Server: `rtmp://TVOJE_IP:1936/live`
* Stream key: `gaming` (nebo jiný existující profil)

4. Zkontroluj:

* Orchestrator loguje `on_publish` a `on_publish_done` eventy.
* ffmpeg procesy běží (`ps aux | grep ffmpeg`).
* Testovací YouTube/Twitch key dostává stream.
* V logách **nejsou** žádné chybové hlášky kvůli read-only FS nebo právům.

5. Ještě jednou ověř, že:

```bash
docker compose -f docker-compose.staging.yml exec nginx-rtmp-staging env | grep -i key
# nic
```

✅ **Checkpoint 1.4.A:**
Staging je stabilní, stream jede, žádné zjevné chyby.

---

### 1.4.2: Přenos do produkce (⏱️ 1–2 hodiny, opatrně)

Postupuj **stejně jako u stagingu, ale po menších krocích**:

1. Vytvoř z produkčního `docker-compose.yml` a `nginx.conf` kopii (už ji máš v `backup/`).
2. Aplikuj změny **po krocích**:

   * nejdřív `on_publish` webhook (bez změny secrets),
   * potom Docker secrets,
   * potom hardening (non-root, read_only, capabilities).
3. Po každém kroku:

   * spusť krátký test streamu,
   * sleduj logy, jestli se něco nerozbilo.

> Ideální je dělat to ve „wartime“ okně, kdy ti nevadí, že stream 5–10 minut nepoběží.

✅ **Checkpoint 1.4.B:**
Produkce má:

* žádné `exec_publish` s shell příkazem,
* stream klíče v Docker secrets,
* kontejner běží jako non-root, read-only FS, drop capabilities,
* stream funguje jako dřív.

---

## Co ti nabídnu dál

Teď máš:

* detailní implementaci **Bloku 0**,
* detailní implementaci **Bloku 1.1**,
* a v této odpovědi **Blok 1.2–1.4**.

V další odpovědi ti můžu stejně detailně rozepsat:

* **Fázi 2 – Blok 2.1–2.4**

  * nasazení Prometheus + Grafana + Loki,
  * přidání GPU/NGINX/FFmpeg metrik,
  * refaktor FFmpeg na single-process pipeline.

Nebo:

* **Fázi 3 – Go orchestrátor a MediaMTX** (architektonicky větší věc).

Pokud chceš držet původní postup „krok za krokem“, logický další krok je:

> Až budeš mít Fázi 1 (1.1–1.4) hotovou na stagingu, můžeme jako další rozebrat **Blok 2.1 – observabilita stack (Prometheus + Grafana + Loki)** v podobné úrovni detailu (adresáře, docker-compose snippet, první dashboard, test scénáře).
