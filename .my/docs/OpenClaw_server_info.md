# OpenClaw - Server Info

## Hetzner Cloud VPS

| Parametr | Hodnota |
|---|---|
| **IP adresa** | 46.225.142.130 |
| **SSH port** | 2222 |
| **Uživatel** | deploy |
| **SSH klíč** | `~/.ssh/id_ed25519_myclaw-hetzner` |
| **OS** | Ubuntu 22.04/24.04 |
| **RAM** | 3.7 GB |
| **Swap** | 2 GB (swappiness=10) |
| **Disk** | 38 GB SSD |
| **Tarif** | Hetzner CX23 |
| **Chromium** | Playwright headless v kontejneru |

## Připojení

```bash
# Pouze SSH shell (bez tunelů)
ssh myclaw

# SSH s tunely pro OpenClaw (port 18789 + 18790)
ssh openclaw

# Jen tunely na pozadí (bez shellu)
ssh -N openclaw
```

Po připojení přes `ssh openclaw` je webové rozhraní dostupné na:
**http://localhost:18789**

SSH konfigurace: `~/.ssh/config`

## Tailscale VPN

| Parametr | Hodnota |
|---|---|
| **Tailscale IP serveru** | `100.115.228.96` |
| **Tailscale IP telefon (Pixel 8a)** | `100.69.103.68` |
| **Účet** | tomis1626@ |

Tailscale umožňuje přístup k aplikacím z mobilu bez SSH tunelu.
Porty 3800–3810 jsou dostupné přes Tailscale IP.

## Kontejnery na serveru

| Kontejner | Image | Port (localhost) | Účel |
|---|---|---|---|
| `myclaw` | myclaw-myclaw | 8080 | myClaw instance |
| `openclaw-openclaw-gateway-1` | openclaw:local | 18789, 18790, 3800-3810 | OpenClaw Gateway |
| `openclaw-pii-proxy-1` | openclaw-pii-proxy | 3001 (jen Docker síť) | PII anonymizační proxy |

## Porty pro Claudiiny webové aplikace

Rozsah **3800–3810** je pre-alokován v `docker-compose.override.yml`.
Vystaveny na `127.0.0.1` (SSH tunel) i `100.115.228.96` (Tailscale).

| Port | Aplikace |
|---|---|
| 3800 | Velké kameny (nocni-projekt) |
| 3801–3810 | Volné |

Přístup z mobilu: `http://100.115.228.96:38XX`
Přístup z PC: `ssh -L 38XX:localhost:38XX openclaw -N` → `http://localhost:38XX`

## OpenClaw - cesty na serveru

| Co | Cesta |
|---|---|
| **Zdrojový kód (fork)** | `/home/deploy/openclaw/` |
| **Docker Compose** | `/home/deploy/openclaw/docker-compose.yml` |
| **Env konfigurace** | `/home/deploy/openclaw/.env` |
| **Gateway konfigurace** | `/home/deploy/.openclaw-gw/openclaw.json` |
| **Data (SQLite, logy)** | `/home/deploy/.openclaw-gw/` |
| **Workspace** | `/home/deploy/.openclaw-gw/workspace/` |
| **PII proxy kód** | `/home/deploy/openclaw/pii-proxy/proxy.py` |
| **PII příjmení (volitelné)** | `/home/deploy/openclaw/pii-proxy/surnames.txt` |

## OpenClaw - přístupové údaje

| Údaj | Hodnota |
|---|---|
| **Gateway token** | `e09827b725998431a32baeac1a2b7e639951dfea0714b428877c5b5fa19c4729` |
| **LLM provider** | Anthropic (Claude) |
| **Auth metoda** | OAuth token (Bearer) přes Claude Code CLI |
| **Anthropic konzole** | https://console.anthropic.com |

## Anthropic OAuth — Token Broker (setup-token)

### Jak to funguje

OpenClaw používá OAuth token z Claude Code CLI (`claude setup-token`).
Token je **dlouhodobý (1 rok)** a nevyžaduje automatický refresh.

```
Claude Code CLI ──[setup-token]──> ~/.claude/.credentials.json
                                          │
                            sync-claude-token.cjs (cron)
                                          │
                                          ▼
                            auth-profiles.json (OpenClaw)
                                          │
                            OpenClaw Gateway (pi-ai)
                                          │  Authorization: Bearer <token>
                                          │  anthropic-beta: oauth-2025-04-20
                                          ▼
                            pii-proxy ──> api.anthropic.com
```

### Klíčové detaily

- Token prefix: `sk-ant-oat01-...` (OAuth token)
- OpenClaw automaticky detekuje OAuth token (`sk-ant-oat-*` prefix)
- Posílá jako `Authorization: Bearer` (NE `x-api-key`!)
- Přidává povinný header `anthropic-beta: oauth-2025-04-20`
- Detekce + headery: `src/agents/pi-embedded-runner/extra-params.ts:422-456`
- pii-proxy forwarduje oba headery (`authorization`, `anthropic-beta`)
- Auth profil: `mode: "token"` v `openclaw.json`

### Soubory

| Co | Cesta |
|---|---|
| Claude Code credentials | `~/.claude/.credentials.json` |
| OpenClaw auth profily | `~/.openclaw-gw/agents/main/agent/auth-profiles.json` |
| Sync skript | `/home/deploy/openclaw/sync-claude-token.cjs` |
| Claude Code CLI | `/usr/local/lib/node_modules/@anthropic-ai/claude-code/` |

### Cron

```
# Kontrola tokenu 1× denně (jen sync + warning při < 30 dnech do expirace)
0 6 * * * /usr/bin/node /home/deploy/openclaw/sync-claude-token.cjs >> /home/deploy/openclaw/sync-claude-token.log 2>&1
```

### Obnova tokenu (když vyprší nebo přestane fungovat)

1. **Aktualizuj Claude Code CLI:**
   ```bash
   # Přes nsenter (root potřeba):
   docker run --rm --privileged --pid=host alpine nsenter -t 1 -m -u -i -n -- \
     /usr/bin/npm install -g @anthropic-ai/claude-code@latest
   claude --version  # ověř
   ```

2. **Vytvoř nový token (interaktivně přes tmux):**
   ```bash
   tmux new-session -s auth 'claude setup-token'
   # Počkej na URL → otevři v prohlížeči → autorizuj jako tomis@kvados.cz
   # Kód z prohlížeče vlož přes tmux:
   tmux send-keys -t auth '<KÓD>' Enter
   ```

3. **Zapiš token do credentials:**
   ```bash
   # Token se zobrazí na obrazovce (sk-ant-oat01-...)
   # Zapiš ho do ~/.claude/.credentials.json (accessToken + expiresAt za 1 rok)
   ```

4. **Spusť sync:**
   ```bash
   node /home/deploy/openclaw/sync-claude-token.cjs
   # Ověř: Token synced, Gateway restarted
   ```

### Časté chyby

| Chyba | Příčina | Řešení |
|---|---|---|
| `invalid x-api-key` | Token posílán jako x-api-key místo Bearer | Ověř, že OpenClaw detekuje `sk-ant-oat-*` prefix |
| `OAuth authentication is currently not supported` | Chybí `anthropic-beta: oauth-2025-04-20` header | Ověř extra-params.ts a pii-proxy FORWARD_HEADERS |
| `OAuth token has expired` | Token/refresh token vypršel | Nový `claude setup-token` (viz postup výše) |
| `claude -p ping` selže s 401 | Credentials mají expirovaný token | Nový `claude setup-token` |

## GitHub fork

| Údaj | Hodnota |
|---|---|
| **Fork URL** | https://github.com/Martin1626/openclaw |
| **Uživatel** | Martin1626 |
| **Upstream** | `https://github.com/openclaw/openclaw.git` (remote `upstream` na lokálním PC) |

Fork je plně pod vaší kontrolou — změny z upstreamu se nepropagují automaticky.
Na serveru je nastaven pouze remote `origin` (fork). Upstream remote je na lokálním PC.

## Správa OpenClaw (příkazy na serveru)

```bash
cd ~/openclaw

# Logy
docker compose logs -f openclaw-gateway

# Restart
docker compose restart openclaw-gateway

# Zastavení
docker compose down

# Spuštění
docker compose up -d openclaw-gateway

# Stav všech kontejnerů
docker ps
docker stats --no-stream
```

## Aktualizace OpenClaw

### Rychlá aktualizace (z forku)

```bash
cd ~/openclaw
bash update-client.sh
```

Skript provede: git pull → docker build → docker compose restart → health check.

### Merge z upstreamu (na lokálním PC)

```bash
cd ~/GitHub/OpenClaw
bash scripts/upgrade-from-upstream.sh v2026.X.Y
# Skript: tag zálohy → fetch upstream → merge → tag výsledku
# Při konfliktech: vyřešit ručně, commitnout, pak tag + push
git push origin main --tags
```

### Deploy na server (po merge)

```bash
ssh myclaw
cd ~/openclaw
git pull
docker compose build
docker compose down && docker compose up -d
curl -f http://localhost:18789/healthz   # health check
```

**Architektura docker-compose:**
- `docker-compose.yml` = čistá upstream verze (nemodifikovat!)
- `docker-compose.override.yml` = vlastní služby (pii-proxy, GROQ env)
- Docker Compose automaticky merguje oba soubory

## Záloha před aktualizací

```bash
docker compose down
tar czf ~/openclaw-backup-$(date +%Y%m%d).tar.gz \
  /home/deploy/.openclaw-gw/
```

## Bezpečnostní architektura

```
Váš počítač                          Hetzner VPS
+---------------+    SSH tunel     +----------------------------------+
| localhost:    | ===============> | sshd :2222                       |
|  18789 -------+--tunnel---------+-> 127.0.0.1:18789 -> [OpenClaw]   |
|  18790 -------+--tunnel---------+-> 127.0.0.1:18790 -> [OpenClaw]   |
|  8080  -------+--tunnel---------+-> 127.0.0.1:8080  -> [myClaw]     |
+---------------+                  |                                  |
                                   | Tailscale VPN (100.115.228.96):  |
Mobil (Pixel 8a)                   |  3800-3810 -> [Claudie appky]    |
+---------------+    Tailscale     |                                  |
| 100.69.103.68 | ==============>  | Docker sítě (oddělené):          |
| http://100.   |                  |   openclaw_default: [OpenClaw]   |
|  115.228.96:  |                  |   myclaw_default:   [myClaw]     |
|  38XX         |                  +----------------------------------+
+---------------+
```

- Všechny porty bindované na `127.0.0.1` + Tailscale IP (ne veřejně)
- Porty 3800–3810 dostupné i přes Tailscale VPN (pro mobilní přístup)
- Kontejnery na oddělených Docker sítích (nevidí se navzájem)
- PII proxy port 3001 dostupný jen uvnitř Docker sítě (ne z hostu)
- Přístup přes SSH tunel s klíčem nebo Tailscale VPN
- Gateway chráněný tokenem
- Root SSH zakázán (`PermitRootLogin no`)

## Verze a historie

| Datum | Verze | Poznámka |
|---|---|---|
| 2026-02-21 | v2026.2.21 | Počáteční instalace |
| 2026-02-27 | v2026.2.26 | Update z upstreamu, nové: `controlUi.dangerouslyAllowHostHeaderOriginFallback` |
| 2026-03-02 | v2026.3.1 | Merge z upstreamu, nové: gateway healthcheck, CLI security hardening, docker-compose.override.yml |
