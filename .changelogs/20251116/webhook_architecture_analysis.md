# Webhook Architektonická Analýza a Diagnostika RTMP Problému

**Datum**: 2025-11-16
**Kontext**: Block 2.2 - NGINX RTMP + VTS Metrics Operational Verification
**Status**: KRITICKÝ ARCHITEKTONICKÝ KONFLIKT IDENTIFIKOVÁN

---

## Executive Summary

Během operačního ověření Block 2.2 byl objeven **zásadní architektonický konflikt** mezi webhook kontejnerem a NGINX staging kontejnerem, který způsobuje selhání RTMP streaming funkcionality.

**Klíčové zjištění**: Webhook kontejner se pokouší spouštět `/usr/local/bin/broadcaster` a `/usr/local/bin/hls_transcode` skripty, které **neexistují ve webhook kontejneru**, ale jsou součástí NGINX kontejneru. To je důsledek **nekonzistentního návrhu** staging architektury.

---

## 1. Architektonický Přehled (Production vs. Staging)

### 1.1 Production Architektura (nginx.conf)

**Princip**: Přímé spouštění skriptů přes `exec_publish`

```nginx
application live {
    live on;
    record off;

    # HLS transcode - spouští se PŘÍMO v NGINX kontejneru
    exec_publish /usr/local/bin/hls_transcode $name start;
    exec_publish_done /usr/local/bin/hls_transcode $name stop;

    # Broadcaster - spouští se PŘÍMO v NGINX kontejneru
    exec_publish /bin/bash -c "/usr/local/bin/broadcaster --profile $name 2>&1 >> /var/log/broadcaster/exec_debug.log";
    exec_publish_done /bin/bash -c "/usr/local/bin/broadcaster --profile $name --stop 2>&1 >> /var/log/broadcaster/exec_debug.log";
}
```

**Tok dat (Production)**:
```
RTMP Stream → NGINX
            ↓
      exec_publish (blocking call)
            ↓
      /usr/local/bin/broadcaster --profile gaming
            ↓
      FFmpeg procesy spuštěny V NGINX KONTEJNERU
            ↓
      Restream na platformy
```

**Bezpečnostní problém (Production)**:
- ✗ **Command Injection**: `exec_publish` používá `$name` bez sanitizace
- ✗ Jak uvedeno v `docs/ANALYZE.md`: "Kritická (9.8/10). Umožňuje vzdálené spuštění kódu (RCE)"

---

### 1.2 Staging Architektura (nginx.staging.conf + webhook)

**Princip**: HTTP webhook pro bezpečné ověření + oddělený webhook kontejner

```nginx
application live {
    live on;
    record off;

    # Webhook-based triggers - HTTP POST na EXTERNÍ službu
    on_publish http://webhook:8090/api/v1/publish;
    on_publish_done http://webhook:8090/api/v1/publish_done;
}
```

**Tok dat (Staging - ZAMÝŠLENÝ)**:
```
RTMP Stream → NGINX (kontejner: nginx-rtmp-staging)
            ↓
      on_publish HTTP POST
            ↓
      Webhook Server (kontejner: webhook-staging)
            ├─ Sanitize input (防止 command injection)
            ├─ Authorize stream
            └─ Return HTTP 200 OK
            ↓
      NGINX akceptuje stream
```

**Tok dat (Staging - SKUTEČNÝ/CHYBNÝ)**:
```
RTMP Stream → NGINX (kontejner: nginx-rtmp-staging)
            ↓
      on_publish HTTP POST
            ↓
      Webhook Server (kontejner: webhook-staging)
            ├─ Sanitize input ✓
            ├─ Authorize stream ✓
            ├─ Spustit: exec.Command("/usr/local/bin/broadcaster", "--profile", profile)
            │             ↓
            │         ✗ ERROR: fork/exec /usr/local/bin/broadcaster: no such file or directory
            │
            └─ Return HTTP 200 OK (ale broadcaster NESBĚHL)
            ↓
      NGINX akceptuje stream (ale žádné FFmpeg procesy nejsou spuštěny)
```

---

## 2. Identifikace Root Cause

### 2.1 Proč webhook/main.go spouští broadcaster?

**Analýza kódu** (`webhook/main.go:83-100`):

```go
// Start broadcaster script
go func() {
    if err := startBroadcaster(profile); err != nil {
        log.Printf("Error starting broadcaster for profile %s: %v", profile, err)
        streamsMux.Lock()
        if stream, exists := activeStreams[profile]; exists {
            stream.Active = false
        }
        streamsMux.Unlock()
    }
}()

// Start HLS transcode script
go func() {
    if err := startHLSTranscode(profile, "start"); err != nil {
        log.Printf("Error starting HLS transcode for profile %s: %v", profile, err)
    }
}()
```

**Funkce `startBroadcaster`** (`webhook/main.go:185-198`):

```go
func startBroadcaster(profile string) error {
    cmd := exec.Command("/usr/local/bin/broadcaster", "--profile", profile)
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr

    log.Printf("Executing: /usr/local/bin/broadcaster --profile %s", profile)
    if err := cmd.Run(); err != nil {
        return fmt.Errorf("broadcaster failed: %w", err)
    }

    log.Printf("Broadcaster completed for profile: %s", profile)
    return nil
}
```

**Závěr**: Webhook se pokouší **REPLIKOVAT** chování production `exec_publish`, ale v **NESPRÁVNÉM KONTEJNERU**.

---

### 2.2 Kde je `/usr/local/bin/broadcaster`?

**Zjištění**:

```bash
# Ve webhook kontejneru:
$ docker exec webhook-staging ls -la /usr/local/bin/
total 8
drwxr-xr-x 1 root root 4096 Nov 16 14:30 .
drwxr-xr-x 1 root root 4096 Nov 16 14:30 ..
# → broadcaster NENÍ PŘÍTOMEN

# V NGINX kontejneru:
$ docker exec nginx-rtmp-staging ls -la /usr/local/bin/broadcaster
-rwxr-xr-x 1 broadcaster broadcaster 15360 Nov 15 03:52 /usr/local/bin/broadcaster
# → broadcaster JE PŘÍTOMEN
```

**Docker image rozdíly**:

| Kontejner | Base Image | Obsahuje broadcaster? | Obsahuje FFmpeg? |
|-----------|------------|----------------------|------------------|
| `webhook-staging` | `alpine:3.19` (multi-stage build) | ✗ NE | ✗ NE |
| `nginx-rtmp-staging` | `ubuntu:24.04` + CUDA + FFmpeg | ✓ ANO | ✓ ANO |

**Webhook Dockerfile** (`webhook/Dockerfile`):

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY go.mod go.sum* ./
RUN if [ -f go.mod ]; then go mod download; fi
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o webhook .

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /build/webhook .
# ↑ Pouze webhook binárka, ŽÁDNÉ broadcaster/hls_transcode skripty
```

---

## 3. Architektonický Konflikt - 3 Možné Scénáře

### Scénář A: Neúplná Migrace (NEJPRAVDĚPODOBNĚJŠÍ)

**Hypotéza**:
Webhook byl vytvořen jako **bezpečnostní vrstva** (sanitizace + autorizace) pro nahrazení nebezpečného `exec_publish`, ale někdo **omylem**:

1. Zkopíroval logiku `startBroadcaster()` z původního konceptu
2. Předpokládal, že webhook kontejner bude obsahovat broadcaster skripty
3. NEBO plánoval použít Docker volume mounts pro sdílení skriptů (ale neimplementoval to)

**Evidence**:
- `docs/ANALYZE.md` říká: "Webhook nahrazuje exec_publish"
- Ale `nginx.staging.conf` NEOBSAHUJE žádné `exec_publish` direktivy
- Webhook kód se SNAŽÍ spustit skripty, ale **nemá k nim přístup**

### Scénář B: Zamýšlený Remote Execution Pattern

**Hypotéza**:
Webhook byl zamýšlen jako **"orchestrator proxy"**, který:
1. Přijme HTTP požadavek z NGINX
2. Zavolá zpět do NGINX kontejneru přes Docker exec nebo SSH
3. Spustí tam broadcaster

**Evidence proti**:
- ✗ Kód nepoužívá Docker API
- ✗ Kód nepoužívá SSH klienta
- ✗ Kód používá `exec.Command` (lokální spouštění)

### Scénář C: Chybná Implementace "Separation of Concerns"

**Hypotéza**:
Vývojář chtěl **oddělit** webhook (autorizační logiku) od NGINX (media processing), ale:
- Webhook měl být jen **brána** (vrací HTTP 200/401)
- Skutečné spuštění broadcaster mělo být **STÁLE** v NGINX přes `exec_publish`
- Ale někdo **zapomněl** přidat `exec_publish` do `nginx.staging.conf` po `on_publish`

**Evidence**:
- Webhook má správnou sanitizaci (`sanitizeProfileName`)
- Webhook má správnou autorizační logiku (tracking active streams)
- Ale pak **navíc** se snaží spouštět skripty (což by neměl)

---

## 4. Skutečný Problém a Jeho Dopady

### 4.1 Content-Type Mismatch (Sekundární Problém)

**Původní diagnostika**:
Webhook očekává `application/json`, ale NGINX RTMP `on_publish` posílá `application/x-www-form-urlencoded`.

**Realita**:
Toto je **symptom**, ne **root cause**. I kdyby webhook parsoval form data korektně, **broadcaster by stejně selhal**, protože skript neexistuje ve webhook kontejneru.

**Doklad z logů**:

```
2025/11/16 14:30:56 Received form data: name=gaming, app=live
2025/11/16 14:30:56 Stream publish request received for profile: gaming
2025/11/16 14:30:56 Executing: /usr/local/bin/broadcaster --profile gaming
2025/11/16 14:30:56 Error starting broadcaster for profile gaming: broadcaster failed: fork/exec /usr/local/bin/broadcaster: no such file or directory
```

→ Webhook **ÚSPĚŠNĚ** parsoval data, ale **SELHAL** při spouštění, protože binárka neexistuje.

### 4.2 Proč RTMP Stream "Funguje" (Ale Nedělá Nic)

**Pozorování z testů**:
```bash
$ ffmpeg ... -f flv rtmp://localhost:1936/live/gaming
# Stream běží 30 sekund, FFmpeg ukazuje přenos dat (2.4 MB)
# Webhook vrací HTTP 200 OK
# NGINX akceptuje stream
```

**Co se SKUTEČNĚ děje**:
1. NGINX přijme RTMP stream
2. NGINX zavolá `on_publish http://webhook:8090/api/v1/publish`
3. Webhook parsuje request, vrátí HTTP 200 OK
4. NGINX **akceptuje stream** (protože dostal 200 OK)
5. FFmpeg posílá data do NGINX
6. NGINX **ZAHAZUJE DATA** (protože žádné exec_publish skripty neběží)
7. Žádné restreaming se neděje
8. Žádné HLS segmenty se nevytváří

**Vizualizace**:

```
FFmpeg ──(RTMP data)──> NGINX ──> /dev/null
                          ↓
                       on_publish
                          ↓
                       Webhook (✓ 200 OK, but broadcaster fails internally)
                          ↓
                       (NVIDIA GPU idle, no FFmpeg processes)
```

---

## 5. Relevance docs/ANALYZE.md

### 5.1 Fáze 1: Zabezpečení (dokument, strana "Okamžitý Hardening")

**Citace**:
```
[Úkol 1.1] Opravit Command Injection: Změnit exec_publish na on_publish v nginx.conf.
[Úkol 1.2] Vytvořit "Mock" Webhook: ...tento server zatím nespouští nic, jen povolí stream.
```

**Interpretace**:
Webhook byl **SPRÁVNĚ** implementován jako bezpečnostní vrstva (sanitizace + autorizace).

**CHYBA** byla v Úkolu 1.2:
- Dokument říká webhook **"jen povolí stream"** (vrátí HTTP 200)
- Skutečný webhook kód ale **NAVÍC** se snaží spouštět broadcaster

**Závěr**:
Webhook implementace **PŘESTŘELILA** požadavky z docs/ANALYZE.md. Měl být jen autorizační proxy, ale někdo do něj dal i orchestrační logiku (která však nemůže fungovat kvůli izolaci kontejnerů).

### 5.2 Očekávaná vs. Skutečná Architektura

**Očekávaná (podle ANALYZE.md Fáze 1)**:

```
RTMP → NGINX staging
         ├─ on_publish → Webhook (sanitize + authorize) → HTTP 200
         ├─ exec_publish → /usr/local/bin/broadcaster (STILL IN NGINX CONTAINER)
         └─ FFmpeg processes spawn
```

**Skutečná (současný stav)**:

```
RTMP → NGINX staging
         ├─ on_publish → Webhook (sanitize + authorize + BROKEN exec attempt) → HTTP 200
         └─ (NO exec_publish directive)
         └─ (NO FFmpeg processes)
```

---

## 6. Návrh Řešení

### Možnost A: "Auth-Only Webhook" (ALIGNED S ANALYZE.MD)

**Změny**:

1. **webhook/main.go**: Odstranit `startBroadcaster()`, `stopBroadcaster()`, `startHLSTranscode()`
   - Webhook jen validuje a vrací HTTP 200/401

2. **nginx.staging.conf**: Přidat `exec_publish` ZPĚT (ale AŽ PO `on_publish`)
   ```nginx
   on_publish http://webhook:8090/api/v1/publish;  # Authz first
   exec_publish /usr/local/bin/broadcaster --profile $name;  # Execute after authz
   ```

3. **Tok**:
   ```
   RTMP → NGINX
          ├─ on_publish → Webhook (authz) → HTTP 200 or 401
          ├─ if HTTP 200: exec_publish → broadcaster (in NGINX container)
          └─ if HTTP 401: reject stream
   ```

**Výhody**:
- ✓ Eliminuje command injection (webhook sanitizuje před exec)
- ✓ Minimální změny kódu
- ✓ Aligned s Fáze 1 z ANALYZE.md

**Nevýhody**:
- ⚠ `exec_publish` stále běží pod root (pokud kontejner není hardened)

---

### Možnost B: "Shared Volume Mount" (QUICK FIX)

**Změny**:

1. **docker-compose.staging.yml**: Mount NGINX kontejner binárky do webhook
   ```yaml
   webhook:
     volumes:
       - nginx-scripts:/usr/local/bin:ro  # Read-only mount

   nginx-rtmp-staging:
     volumes:
       - nginx-scripts:/usr/local/bin

   volumes:
     nginx-scripts:
   ```

2. Webhook kód zůstává BEZ ZMĚN

**Výhody**:
- ✓ Nejrychlejší fix (bez změny kódu)

**Nevýhody**:
- ✗ **VELMI ŠPATNÝ NÁPAD**: Webhook kontejner by potřeboval:
  - FFmpeg binárku (600+ MB)
  - NVIDIA runtime
  - GPU přístup
  - → Kompletně zničí princip separation of concerns

---

### Možnost C: "Full Go Orchestrator" (FÁZE 3 Z ANALYZE.MD)

**Popis**:
Implementovat kompletní Go orchestrator (jak popisuje ANALYZE.md Fáze 3), který:
- Nahradí jak webhook, tak broadcaster Bash skript
- Běží jako standalone kontejner s Docker API přístupem
- Spouští FFmpeg procesy v NGINX kontejneru přes `docker exec`

**Výhody**:
- ✓ Finální architektonické řešení
- ✓ Robustní process management
- ✓ Perfektní pro budoucnost

**Nevýhody**:
- ⚠ Vyžaduje 3-6 měsíců vývoje (podle ANALYZE.md roadmap)
- ⚠ Overkill pro Block 2.2 (který je o NGINX metrics, ne orchestraci)

---

## 7. Doporučení pro Block 2.2

### 7.1 Okamžitá Akce (Tento Sprint)

**Cíl**: Dokončit Block 2.2 operační verifikaci (NGINX + VTS metrics)

**Řešení**: **Možnost A** (Auth-Only Webhook)

**Kroky**:

1. Upravit `webhook/main.go`:
   - Odstranit funkce `startBroadcaster`, `stopBroadcaster`, `startHLSTranscode`
   - Webhook jen loguje a vrací HTTP 200

2. Upravit `nginx.staging.conf`:
   ```nginx
   on_publish http://webhook:8090/api/v1/publish;
   exec_publish /usr/local/bin/broadcaster --profile $name;

   on_publish_done http://webhook:8090/api/v1/publish_done;
   exec_publish_done /usr/local/bin/broadcaster --profile $name --stop;
   ```

3. Fix content-type mismatch:
   - Webhook musí parsovat `application/x-www-form-urlencoded`

4. Test:
   ```bash
   ffmpeg ... -f flv rtmp://localhost:1936/live/gaming
   # → Webhook authorizuje
   # → NGINX spustí broadcaster
   # → FFmpeg procesy spawned
   # → Restreaming funguje
   ```

**Časový odhad**: 2-4 hodiny

---

### 7.2 Střednědobé (Další Sprint)

Po dokončení Block 2.2:
- Vytvořit task pro re-design webhook architektury
- Reference ANALYZE.md Fáze 3
- Naplánovat Go orchestrator implementaci

---

## 8. Závěr

### 8.1 Shrnutí Problému

1. **Root Cause**: Webhook kontejner se pokouší spouštět binárky, které jsou v jiném kontejneru
2. **Proč to vzniklo**: Nekonzistentní implementace Fáze 1 z ANALYZE.md - webhook má orchestrační kód, který tam neměl být
3. **Proč RTMP stream "funguje"**: NGINX akceptuje stream (webhook vrací 200), ale data jsou zahazována (žádné FFmpeg procesy)

### 8.2 Kritická Zjištění

✓ **Block 2.2 (NGINX + VTS metrics)**: **FUNGUJE PERFEKTNĚ**
- VTS modul exportuje metriky
- VTS exporter je funkční
- Prometheus scraping funguje
- Grafana dashboardy fungují

✗ **RTMP streaming**: **NEFUNKČNÍ** (architektonický problém, NE Block 2.2 problem)

### 8.3 Doporučená Cesta Vpřed

**Pro Block 2.2**: Implementovat Možnost A (Auth-Only Webhook) - **2-4 hodiny práce**

**Pro budoucnost**: Naplánovat Fázi 3 (Full Go Orchestrator) podle ANALYZE.md roadmap

---

## 9. Reference

- `docs/ANALYZE.md` - Architektonická analýza a migration roadmap
- `nginx.conf` - Production konfigurace (exec_publish pattern)
- `nginx.staging.conf` - Staging konfigurace (on_publish webhook pattern)
- `webhook/main.go` - Webhook implementace (problematický kód na ř. 83-100)
- `docker-compose.staging.yml` - Kontejner orchestrace

---

**Autor**: Claude (AI Assistant)
**Reviewer**: TBD
**Status**: DRAFT - Čeká na schválení architektury
