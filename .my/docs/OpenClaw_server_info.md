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

## WireGuard VPN (přístup z mobilu + notebooku)

| Parametr | Hodnota |
|---|---|
| **VPS veřejná IP** | `46.225.142.130` |
| **VPS WireGuard IP** | `10.10.0.1` |
| **VPS public key** | `rqDf0OGFvr9ls94SIQ2sfBi4JVOCy1ddFCpfZzG620A=` |
| **Server config** | `/etc/wireguard/wg0.conf` |
| **Port** | `51820/udp` |
| **Subnet** | `10.10.0.0/24` |

### Peery (klienti)

| Zařízení | WG IP | Public key | UFW 3800–3810 |
|---|---|---|---|
| Mobil (Pixel 8a) | `10.1.3.2` | `vyxESQG6X+N9MCeiJFfIyUXleOt6dKQronCZi7oNQ2c=` | ✅ |
| Notebook (Martin) | `10.10.0.10` | `eXTYKYbdI7p17NouhMQNSyckmESuSBkod8yidrF6XmI=` | ✅ (přidáno 2026-04-13) |

WireGuard server na VPS umožňuje přístup k aplikacím bez SSH tunelu.
Oba klienti mají WireGuard profil "HA" se dvěma peery — domácí router (Home Assistant) + OpenClaw VPS.
Porty 3800–3810 jsou dostupné přes WireGuard IP (`10.10.0.1`).

**Poznámka:** Tailscale byl odinstalován (2026-04-03), nahrazen WireGuard.

## Kontejnery na serveru

| Kontejner | Image | Port (localhost) | Účel |
|---|---|---|---|
| `myclaw` | myclaw-myclaw | 8080 | myClaw instance |
| `openclaw-openclaw-gateway-1` | openclaw:local | 18789, 18790, 3800-3810 | OpenClaw Gateway |
| `openclaw-pii-proxy-1` | openclaw-pii-proxy | 3001 (jen Docker síť) | PII anonymizační proxy |

## Porty pro Claudiiny webové aplikace

Rozsah **3800–3810** je pre-alokován v `docker-compose.override.yml`.
Vystaveny na `127.0.0.1` (SSH tunel) i `10.10.0.1` (WireGuard VPN).

| Port | Aplikace | Správa |
|---|---|---|
| 3800 | Velké kameny (nocni-projekt) | manuální |
| 3801 | Brainbox (vault-viewer) | systemd (`openclaw-brainbox`) |
| 3802–3810 | Volné | — |

Přístup z mobilu: `http://10.10.0.1:38XX` (WireGuard)
Přístup z notebooku: `http://10.10.0.1:38XX` (WireGuard) nebo `ssh -L 38XX:localhost:38XX openclaw -N` → `http://localhost:38XX`

## Systemd služby pro webapps (od 2026-04-09)

Host-level systemd platforma pro správu Node.js webapps běžících uvnitř OpenClaw kontejneru.
Claudie může přidávat/odebírat služby přes JSON requesty v workspace — bez SSH přístupu.

### Architektura

```
📱 Martin (Telegram): "Zapni službu X"
   → Claudie zapíše JSON do workspace/services/requests/
   → systemd .path watcher detekuje soubor
   → processor validuje (port 3800-3810, cesta v workspace, bezpečný název)
   → vytvoří systemd unit + start
   → výsledek v workspace/services/results/
```

### Soubory na hostu

| Soubor | Účel |
|---|---|
| `/home/deploy/services/openclaw-app-ctl.sh` | Runtime: start/stop/wait/cleanup (univerzální) |
| `/home/deploy/services/openclaw-app-processor.sh` | Request processor (validace, generování units) |
| `~/.config/systemd/user/openclaw-app-request.path` | Watcher na requesty |
| `~/.config/systemd/user/openclaw-app-request.service` | Trigger pro processor |
| `~/.config/systemd/user/openclaw-brainbox.service` | Brainbox unit |
| `workspace/services/` | Sdílený prostor (requests, results, status.json) |

### Správa

```bash
# Status
systemctl --user status openclaw-brainbox

# Restart
systemctl --user restart openclaw-brainbox

# Logy
journalctl --user -u openclaw-brainbox -n 50 --no-pager

# Stav všech služeb
cat ~/.openclaw-gw/workspace/services/status.json
```

### Přidání nové služby (Claudie nebo manuálně)

```bash
# Manuálně přes JSON request:
cat > ~/.openclaw-gw/workspace/services/requests/install-foo.json << 'EOF'
{"action":"install","name":"foo","dir":"/home/node/.openclaw/workspace/projekty/foo","entry":"server.js","port":3802}
EOF
# Watcher automaticky zpracuje → výsledek v results/install-foo.json
```

### Bezpečnostní záruky

- Porty jen 3800–3810
- Cesta musí začínat `/home/node/.openclaw/workspace/`
- Název: `[a-z0-9-]`, max 30 znaků
- Entry soubor musí existovat v kontejneru
- ExecStart je vždy šablona (`openclaw-app-ctl.sh`), žádný arbitrary exec

### Technické detaily

- **User-level systemd** (deploy, `Linger=yes`) — bez sudo
- Node v24 v kontejneru přejmenuje proces na `MainThread` → `pgrep -f` (ne `-x`)
- `ss` neexistuje v kontejneru → port check přes `node -e net.createServer().listen()`
- Restart: `always`, `RestartSec=10`, `StartLimitBurst=10/300s`

### Deaktivovaný cron watchdog

Původní LLM cron watchdog pro Brainbox (ID `86cd92f5-901a-4b66-a479-d0faff1e9a4b`)
byl deaktivován 2026-04-09. Script `ensure-brainbox.sh` stále existuje, ale nepoužívá se.

Pro rollback: v `jobs.json` nastavit `enabled: true` pro daný ID.

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
| **Primární LLM provider** | OpenAI Codex (GPT-5.4, ChatGPT Plus subscription) |
| **Auth metoda (OpenAI)** | Codex OAuth (`openai-codex:default`, automatický refresh) |
| **Záložní LLM provider** | Anthropic Claude (pozastaveno od 4.4.2026) |
| **Auth metoda (Anthropic)** | OAuth token (Bearer) — blokováno pro third-party |
| **OpenAI účet** | ChatGPT Plus, 499 Kč/měs |
| **Anthropic konzole** | https://console.anthropic.com |

## OpenAI Codex — primární LLM provider (od 2026-04-05)

### Jak to funguje

OpenClaw používá OpenAI Codex OAuth (ChatGPT Plus subscription).
OpenAI **explicitně povoluje** Codex OAuth v third-party nástrojích.

```
OpenClaw Gateway
       │
       │  openai-codex/gpt-5.4
       │  OAuth (automatický refresh)
       ▼
 api.openai.com (Codex endpoint)
```

### Klíčové detaily

- Model: `openai-codex/gpt-5.4`
- Auth profil: `openai-codex:default` (mode: "oauth")
- OAuth refresh: automatický (spravuje OpenClaw)
- Rate limity: 160 msg/3h (Plus), 3000 msg/týden (GPT-5.4 Thinking)
- PII proxy: NEPOUŽÍVÁ SE (jen pro Anthropic)

### Nastavení / obnova OAuth

```bash
# V tmux (headless server):
tmux new-session -d -s codex \
  "cd /home/deploy/openclaw && docker compose exec openclaw-gateway \
   npx openclaw models auth login --provider openai-codex --set-default 2>&1; \
   echo EXIT_CODE=\$?; sleep 120"

# Přečti URL:
tmux capture-pane -t codex -p -S -50
# Otevři URL v prohlížeči → přihlas se OpenAI účtem
# Prohlížeč přesměruje na localhost:XXXX/auth/callback?code=...
# Zkopíruj CELOU URL z adresního řádku a vlož:
tmux send-keys -t codex '<CELÁ_REDIRECT_URL>' Enter
# Ověř: "Auth profile: openai-codex:default"
```

### Přepnutí modelu

V `/home/deploy/.openclaw-gw/openclaw.json`:
```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai-codex/gpt-5.4"
      }
    }
  }
}
```

## Anthropic OAuth — Token Broker (záložní, pozastaveno od 2026-04-05)

> **POZOR:** Od 4.4.2026 Anthropic blokuje subscription OAuth tokeny pro
> third-party nástroje. Volání z OpenClaw se účtují z Extra Usage (pay-per-token),
> ne z Max subscription. Primární provider je nyní OpenAI Codex (viz výše).

### Jak to funguje (pokud se rozhodneš reaktivovat)

OpenClaw používá OAuth token z Claude Code CLI (`claude setup-token`).
Token je **dlouhodobý (1 rok)**, scope `user:inference`, bez refresh tokenu.

```
claude setup-token ──> token na obrazovce (sk-ant-oat01-...)
                              │
                       ručně uložit do ~/.claude/.credentials.json
                              │
                       sync-claude-token.cjs (cron 1×/den)
                              │
                              ▼
                       auth-profiles.json (OpenClaw)
                              │
                       OpenClaw Gateway (pi-ai)
                              │  Authorization: Bearer <token>
                              │  anthropic-beta: claude-code-20250219,oauth-2025-04-20
                              ▼
                       pii-proxy ──> api.anthropic.com
```

### Klíčové detaily

- Token prefix: `sk-ant-oat01-...` (OAuth token)
- OpenClaw automaticky detekuje OAuth token (`sk-ant-oat-*` prefix)
- Posílá jako `Authorization: Bearer` (NE `x-api-key`!)
- Přidává povinné headery: `anthropic-beta: claude-code-20250219,oauth-2025-04-20`
- **Bez `claude-code-20250219`** Anthropic token odmítne (third-party blokace)
- Detekce + headery: `src/agents/pi-embedded-runner/extra-params.ts:422-456`
- pii-proxy forwarduje headery (`authorization`, `anthropic-beta`, `anthropic-version`)
- Auth profil: `type: "token"` v `auth-profiles.json`

### Soubory

| Co | Cesta |
|---|---|
| Claude Code credentials | `~/.claude/.credentials.json` |
| OpenClaw auth profily | `~/.openclaw-gw/agents/main/agent/auth-profiles.json` |
| Sync skript | `/home/deploy/openclaw/sync-claude-token.cjs` |
| Sync log | `/home/deploy/openclaw/sync-claude-token.log` |

### Cron

```
# Sync tokenu 1× denně v 06:00 UTC (stačí pro 1-year token)
0 6 * * * /usr/bin/node /home/deploy/openclaw/sync-claude-token.cjs >> /home/deploy/openclaw/sync-claude-token.log 2>&1
```

Sync skript obsahuje logiku pro forced refresh (3.5h buffer, `claude -p ping`).
Při přechodu na krátké tokeny (8h, přes `claude auth login`) stačí změnit cron
na `0 */3 * * *`.

### Obnova tokenu (když vyprší nebo přestane fungovat)

1. **Aktualizuj Claude Code CLI (volitelné):**
   ```bash
   # Přes nsenter (root potřeba):
   docker run --rm --privileged --pid=host alpine nsenter -t 1 -m -u -i -n -- \
     /usr/bin/npm install -g @anthropic-ai/claude-code@latest
   claude --version  # ověř
   ```

2. **Vytvoř nový token (interaktivně přes tmux):**
   ```bash
   tmux new-session -d -s auth 'claude setup-token 2>&1; echo EXIT_CODE=$?; sleep 30'
   # Počkej ~5s, pak přečti URL:
   tmux capture-pane -t auth -p -S -40
   # Otevři URL v prohlížeči → autorizuj jako tomis@kvados.cz
   # Kód z prohlížeče vlož přes tmux:
   tmux send-keys -t auth '<KÓD>' Enter
   # Počkej ~10s, ověř výstup:
   tmux capture-pane -t auth -p -S -50
   # Mělo by se zobrazit: "Long-lived authentication token created successfully!"
   # a token sk-ant-oat01-...
   ```
   **POZOR:** `claude auth login` na headless serveru NEFUNGUJE (nepřijímá
   ruční vložení kódu). Používej výhradně `claude setup-token`.

3. **Zapiš token do credentials:**
   ```bash
   # Token se zobrazí na obrazovce (sk-ant-oat01-...)
   # setup-token ho NEULOŽÍ automaticky do credentials.json!
   cat > ~/.claude/.credentials.json << 'EOF'
   {
     "claudeAiOauth": {
       "accessToken": "sk-ant-oat01-TVŮJ-TOKEN-ZDE",
       "expiresAt": EPOCH_MS_ZA_1_ROK,
       "scopes": ["user:inference"],
       "subscriptionType": "max",
       "rateLimitTier": "default_claude_max_5x"
     }
   }
   EOF
   chmod 600 ~/.claude/.credentials.json
   ```
   expiresAt: `python3 -c "import time; print(int((time.time() + 365*86400)*1000))"`

4. **Spusť sync:**
   ```bash
   node /home/deploy/openclaw/sync-claude-token.cjs
   # Ověř: "Token synced" + "Gateway restarted"
   ```

5. **Ověř funkčnost:**
   ```bash
   # Claude CLI:
   claude -p "odpověz jen: OK"
   # Přímé API volání:
   curl -s https://api.anthropic.com/v1/messages \
     -H "Authorization: Bearer sk-ant-oat01-..." \
     -H "anthropic-beta: claude-code-20250219,oauth-2025-04-20" \
     -H "anthropic-version: 2023-06-01" \
     -H "content-type: application/json" \
     -d '{"model":"claude-haiku-4-5","max_tokens":10,"messages":[{"role":"user","content":"Say OK"}]}'
   ```

### Časté chyby

| Chyba | Příčina | Řešení |
|---|---|---|
| `invalid x-api-key` | Token posílán jako x-api-key místo Bearer | Ověř, že OpenClaw detekuje `sk-ant-oat-*` prefix |
| `OAuth authentication is currently not supported` | Chybí `anthropic-beta: oauth-2025-04-20` header | Ověř extra-params.ts a pii-proxy FORWARD_HEADERS |
| `OAuth authentication is currently not allowed for this organization` | Chybí `claude-code-20250219` beta header, nebo změna předplatného | Nový `claude setup-token`; ověř, že OpenClaw posílá oba beta headery |
| `OAuth token has expired` | Token vypršel (1 rok) | Nový `claude setup-token` (viz postup výše) |
| `claude -p ping` selže s 401 | Credentials mají expirovaný token | Nový `claude setup-token` |
| `not_found_error` pro model | OAuth tokeny fungují jen s novými názvy modelů | Používej `claude-haiku-4-5`, `claude-sonnet-4-5` (ne staré `*-20241022` formáty) |

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
Notebook (Martin)                    Hetzner VPS
+---------------+    SSH tunel     +----------------------------------+
| localhost:    | ===============> | sshd :2222                       |
|  18789 -------+--tunnel---------+-> 127.0.0.1:18789 -> [OpenClaw]   |
|  18790 -------+--tunnel---------+-> 127.0.0.1:18790 -> [OpenClaw]   |
|  8080  -------+--tunnel---------+-> 127.0.0.1:8080  -> [myClaw]     |
|               |                  |                                  |
| 10.10.0.10    |   WireGuard      | WireGuard VPN (10.10.0.1):       |
| http://10.    | ==============>  |  3800-3810 -> [Claudie appky]    |
|  10.0.1:38XX  |  (port 51820)    |                                  |
+---------------+                  | Docker sítě (oddělené):          |
                                   |   openclaw_default: [OpenClaw]   |
Mobil (Pixel 8a)                   |   myclaw_default:   [myClaw]     |
+---------------+    WireGuard     |                                  |
| 10.1.3.2      | ==============>  |                                  |
| http://10.    |  (port 51820)    |                                  |
|  10.0.1:38XX  |                  |                                  |
+---------------+                  +----------------------------------+
```

- Všechny porty bindované na `127.0.0.1` + WireGuard IP `10.10.0.1` (ne veřejně)
- Porty 3800–3810 dostupné přes WireGuard VPN (pro mobil i notebook)
- WireGuard port 51820/udp otevřen v UFW, porty 3800-3810 povoleny jen z `10.1.3.2` (mobil) a `10.10.0.10` (notebook)
- Kontejnery na oddělených Docker sítích (nevidí se navzájem)
- PII proxy port 3001 dostupný jen uvnitř Docker sítě (ne z hostu)
- Přístup přes SSH tunel s klíčem nebo WireGuard VPN
- Gateway chráněný tokenem
- Root SSH zakázán (`PermitRootLogin no`)

## Verze a historie

| Datum | Verze | Poznámka |
|---|---|---|
| 2026-02-21 | v2026.2.21 | Počáteční instalace |
| 2026-02-27 | v2026.2.26 | Update z upstreamu, nové: `controlUi.dangerouslyAllowHostHeaderOriginFallback` |
| 2026-03-02 | v2026.3.1 | Merge z upstreamu, nové: gateway healthcheck, CLI security hardening, docker-compose.override.yml |
