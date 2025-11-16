# Phase 1: Security Baseline – Implementation Plan

**Start Date**: 2025-11-16
**Target Completion**: 2025-11-17
**Status**: 🚧 IN PROGRESS

---

## Phase 1 Definition of Done

Fáze 1 je hotová, když:

1. ✅ **Webhook flow** je bezpečné, jednoznačně definované a otestované
2. ⏳ **Kontejnery nejsou zbytečně privilegované** (non-root, minimální capabilities, read-only)
3. ⏳ **Tajemství a konfigurace** jsou oddělené (secrets vs. non-secret config)
4. ⏳ **Síťová a přístupová vrstva** brání náhodnému/externímu přístupu
5. ⏳ Existují **testovací scénáře** a **dokumentovaný security baseline**

---

## Implementation Checklist

### Krok 0: Příprava dokumentace

- [x] Vytvořit `.changelogs/20251116/phase1_security_baseline_plan.md`
- [ ] Vytvořit `docs/SECURITY-BASELINE.md`
- [ ] Vytvořit `docs/TESTING-WORKFLOW.md` (security tests sekce)

### Krok 1: Inventarizace služeb a kontejnerů

**Cíl**: Mít přesný seznam toho, co je potřeba „ošéfovat" v této fázi.

- [ ] Vypsat všechny services z `docker-compose.staging.yml`
- [ ] U každé služby zapsat:
  - [ ] Jaký port/přístup má být povolen
  - [ ] Zda musí být přístupná zvenku
  - [ ] Zda musí psát na disk a kam
- [ ] Vytvořit tabulku v `docs/SECURITY-BASELINE.md` (Service inventory)

**Services to audit**:
```
✅ nginx-rtmp-staging       (RTMP 1936, HTTP 8081)
✅ webhook-staging          (HTTP 8090 - internal only)
⏳ prometheus-staging       (HTTP 9090 - admin access)
⏳ grafana-staging          (HTTP 3000 - admin access)
⏳ loki-staging             (HTTP 3100 - internal only)
⏳ promtail-staging         (internal only)
⏳ node-exporter-staging    (HTTP 9100 - internal only)
⏳ cadvisor-staging         (HTTP 8082 - internal only)
⏳ dcgm-exporter-staging    (HTTP 9400 - internal only)
⏳ nginx-vts-exporter-staging (HTTP 9913 - internal only)
```

### Krok 2: Konsolidace konfigurace a tajemství

**Cíl**: Mít jasně oddělené „config" vs „secrets", žádná hesla v gitu.

#### 2.1 Identifikace secrets
- [ ] Projít `docker-compose.staging.yml` pro secrets
- [ ] Projít `entrypoint.sh` pro hardcoded values
- [ ] Projít `broadcaster` script pro API keys
- [ ] Projít `webhook` config
- [ ] Projít `.env` soubory

**Identified secrets**:
```
✅ gaming_youtube_key (Docker secret)
✅ gaming_twitch_key (Docker secret)
✅ gaming_kick_key (Docker secret)
✅ gaming_x_key (Docker secret)
⏳ Grafana admin password (env var)
⏳ Další platformy stream keys (pokud jsou)
```

#### 2.2 Oddělení secrets
- [x] Streaming keys v `secrets/` directory (done)
- [ ] Grafana password v `.env.grafana` (ignorované)
- [ ] Vytvořit `.env.example` templates
- [ ] Aktualizovat `.gitignore`

#### 2.3 Git history kontrola
- [ ] `git log -p secrets/` → ověřit, že nejsou reálná hesla
- [ ] `git log -p .env` → ověřit historii
- [ ] Poznamenat findings do security doc

### Krok 3: Hardening Docker kontejnerů

**Cíl**: Minimalizovat škody v případě kompromitace (least privilege).

#### 3.1 Non-root uživatelé

**Status**:
- [x] nginx-rtmp-staging → `USER broadcaster` (UID 1000)
- [x] webhook-staging → `USER webhook` (UID 1000)
- [ ] prometheus-staging → audit
- [ ] grafana-staging → audit
- [ ] loki-staging → audit
- [ ] promtail-staging → audit
- [ ] node-exporter → audit (likely needs host access)
- [ ] cadvisor → audit (privileged by design)
- [ ] dcgm-exporter → audit (needs GPU access)
- [ ] nginx-vts-exporter → audit

**Tasks**:
- [ ] Pro každý image zkontrolovat `USER` directive
- [ ] Pokud běží jako root, přidat `groupadd/useradd`
- [ ] Nastavit `chown` pro relevantní adresáře
- [ ] Ověřit: `docker exec <container> id` → uid != 0

#### 3.2 Read-only filesystem + tmpfs

**Status**:
- [x] nginx-rtmp-staging → `read_only: true` + tmpfs
- [ ] webhook-staging → přidat `read_only: true`
- [ ] prometheus-staging → audit
- [ ] grafana-staging → audit (needs persistent storage)
- [ ] loki-staging → audit (needs persistent storage)
- [ ] promtail-staging → audit
- [ ] exporters → audit (většinou read-only safe)

**Tasks**:
- [ ] Pro každou službu určit, kam musí zapisovat
- [ ] Přidat `read_only: true` kde možné
- [ ] Přidat `tmpfs` pro `/tmp`, `/var/cache` apod.
- [ ] Ověřit: `docker inspect --format '{{.HostConfig.ReadonlyRootfs}}'`

#### 3.3 Capabilities, privileged a mounts

**Status**:
- [x] nginx-rtmp-staging → minimální caps (5 caps)
- [ ] webhook-staging → přidat `cap_drop: ALL`
- [ ] ostatní služby → audit

**Tasks**:
- [ ] Přidat `cap_drop: ALL` ke všem službám
- [ ] Jen pokud nutné, přidat `cap_add` (NET_BIND_SERVICE apod.)
- [ ] Ověřit `privileged: true` jen kde nutné (cadvisor, dcgm)
- [ ] Ověřit bind-mounty (žádné `/var/run/docker.sock` bez důvodu)

**Expected exceptions**:
```
cadvisor: privileged: true (needs host metrics)
dcgm-exporter: runtime: nvidia (needs GPU access)
node-exporter: volumes /proc, /sys (host metrics)
```

### Krok 4: Zabezpečení NGINX + webhook flow

**Cíl**: Webhook jako auth-only, exec_publish orchestrace, vše bezpečně.

#### 4.1 Webhook security audit

**Status**:
- [x] Parsuje `application/x-www-form-urlencoded`
- [x] Validuje vstup (`sanitizeProfileName`)
- [x] HTTP 4xx při chybě (ne stack traces)
- [ ] Loguje jen non-sensitive data
- [ ] Síť: internal only (žádné `ports` ven)

**Tasks**:
- [x] Audit `webhook/main.go` validace
- [ ] Zkontrolovat logging (žádné stream keys v plaintext)
- [ ] Odstranit `ports: "8090:8090"` z docker-compose (internal only)
- [ ] (Fáze 2) Připravit plán na HTTPS/mTLS

#### 4.2 NGINX RTMP + exec_publish security

**Status**:
- [x] `on_publish` → webhook URL (internal)
- [x] `exec_publish` → lokální skripty
- [ ] Sanitizace argumentů v skriptech
- [ ] Logging bez citlivých údajů

**Tasks**:
- [ ] Audit `broadcaster` script: quoted expansions
- [ ] Audit `hls_transcode` script: quoted expansions
- [ ] Odstranit/přehodnotit jakékoli `eval` použití
- [ ] Zkontrolovat logy: žádné tokeny v plainu

#### 4.3 Testovací scénáře

- [ ] Test: publish s chybným stream key → webhook 4xx
- [ ] Test: brute-force 5× špatný key → logy viditelné
- [ ] Test: valid key → stream úspěšný, exec_publish spuštěno
- [ ] Dokumentovat do `docs/TESTING-WORKFLOW.md`

### Krok 5: Síťová a přístupová vrstva

**Cíl**: Jen nutné porty ven, striktní přístup k admin nástrojům.

#### 5.1 Host firewall (UFW)

- [ ] Zjistit aktuální stav: `sudo ufw status`
- [ ] Povolit RTMP: `sudo ufw allow 1936/tcp`
- [ ] Povolit HTTP status (staging): `sudo ufw allow 8081/tcp`
- [ ] Admin porty (Grafana, Prometheus) jen z vybraných IP:
  - [ ] `sudo ufw allow from <VPN_IP> to any port 3000`
  - [ ] `sudo ufw allow from <VPN_IP> to any port 9090`
- [ ] Default deny: `sudo ufw default deny incoming`
- [ ] Enable: `sudo ufw enable`

#### 5.2 Docker networks

**Current state**:
```yaml
networks:
  streaming:
    driver: bridge
```

**Tasks**:
- [ ] Rozdělit na `streaming-public` a `streaming-internal`
- [ ] NGINX RTMP + webhook na obou sítích
- [ ] Observability stack jen na `streaming-internal`
- [ ] Aktualizovat docker-compose.staging.yml

#### 5.3 Zabezpečení admin UI

**Grafana**:
- [ ] Změnit default `admin/admin` heslo
- [ ] Nastavit v `.env.grafana`: `GF_SECURITY_ADMIN_PASSWORD`
- [ ] Disable sign-up: `GF_USERS_ALLOW_SIGN_UP=false` (done)

**Prometheus**:
- [ ] Zjistit, zda má auth (default: ne)
- [ ] Dokumentovat: přístup jen přes VPN/SSH tunel
- [ ] (Fáze 2) Implementovat basic auth / reverse proxy

### Krok 6: Security testy Fáze 1

**Cíl**: Opakovatelné testy potvrzující splnění Fáze 1.

#### 6.1 Kontrola non-root a read-only

- [ ] Test: `docker exec nginx-rtmp-staging id` → uid != 0
- [ ] Test: `docker exec webhook-staging id` → uid != 0
- [ ] Test: `docker inspect nginx-rtmp-staging --format '{{.HostConfig.ReadonlyRootfs}}'` → true
- [ ] Test: `docker inspect webhook-staging --format '{{.HostConfig.ReadonlyRootfs}}'` → true

#### 6.2 Kontrola otevřených portů

- [ ] Test: `ss -tulpen | grep -E '1936|8081|3000|9090'`
- [ ] Ověřit: jen očekávané porty, žádné neznámé

#### 6.3 Webhook negative tests

- [ ] Test: publish s chybným key → HTTP 400
- [ ] Test: NGINX logy obsahují odmítnutí
- [ ] Test: webhook logy obsahují sanitizovanou chybu
- [ ] Zapsat výsledky do reportu

#### 6.4 Container image scan

- [ ] Nainstalovat `trivy` (pokud není)
- [ ] Scan: `trivy image nvidia-cuda-rtmp-multistream-nginx-rtmp-staging:latest`
- [ ] Scan: `trivy image nvidia-cuda-rtmp-multistream-webhook:latest`
- [ ] Zaznamenat findings (nemusí se hned řešit)

### Krok 7: Dokumentace a Definition of Done

#### 7.1 Vytvořit/doplnit docs/SECURITY-BASELINE.md

- [ ] Přehled služeb (inventář)
- [ ] Secrets management (jak jsou řešené)
- [ ] Povolené porty a sítě
- [ ] Webhook + exec_publish flow diagram
- [ ] Známá omezení (rate-limit, 2FA, apod.)

#### 7.2 Changelog a final report

- [ ] `.changelogs/20251116/phase1_security_tests.md` s výsledky
- [ ] `.changelogs/20251116/phase1_done.md` se sumárem
- [ ] Odkazy na commity a soubory
- [ ] Update `CLAUDE.md` → Phase 1 status

#### 7.3 Mark Phase 1 as DONE

- [ ] Všechny checklisty ✅
- [ ] Security tests prošly
- [ ] Dokumentace kompletní
- [ ] Commit: `feat: complete Phase 1 - Security Baseline`

---

## Progress Tracking

**Legend**:
- ✅ = Completed
- 🚧 = In Progress
- ⏳ = Pending
- ❌ = Blocked/Issue

### Current Status (2025-11-16)

| Krok | Status | Notes |
|------|--------|-------|
| 0. Příprava dokumentace | 🚧 | Plan created |
| 1. Inventarizace služeb | ⏳ | |
| 2. Konsolidace secrets | 🚧 | Docker secrets done, Grafana pending |
| 3. Container hardening | 🚧 | nginx-rtmp/webhook done, others pending |
| 4. Webhook flow security | ✅ | Auth-only implemented |
| 5. Síťová vrstva | ⏳ | |
| 6. Security testy | ⏳ | |
| 7. Dokumentace | ⏳ | |

**Completion**: ~30% (webhook flow + partial hardening)

---

## Risk & Blockers

1. **Non-root pro system containers**: node-exporter, cadvisor vyžadují privilegovaný přístup → dokumentovat jako known limitation
2. **Grafana persistent storage**: read-only FS není kompatibilní → použít named volume s RW
3. **RTMP port exposure**: 1936 musí být veřejný pro příjem streamu → firewall rate-limit

---

**Next Steps**:
1. Dokončit Krok 1: Service inventory
2. Implementovat Krok 3.1: Non-root audit pro zbývající služby
3. Implementovat Krok 5.2: Docker network separation
