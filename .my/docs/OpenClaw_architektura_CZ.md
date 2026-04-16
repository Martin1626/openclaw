# OpenClaw — Architektura a první kroky

## Kontext

OpenClaw je nainstalován na Hetzner VPS v Docker kontejneru. Gateway běží, web UI je dostupné přes SSH tunel na `http://localhost:18789`. Webové aplikace vytvořené Claudií jsou dostupné přes SSH tunel nebo WireGuard VPN z mobilu (`http://10.10.0.1:38XX`).

---

## Architektura OpenClaw

### Celková architektura

```
┌────────────────────────────────────────────────────────┐
│                    OpenClaw Gateway                    │
│                  (Node.js 24, TypeScript)              │
│                                                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐  │
│  │ Web UI   │  │ Channels │  │  Agents  │  │ Skills │  │
│  │ :18789   │  │          │  │          │  │        │  │
│  │          │  │ WhatsApp │  │ Sessions │  │ 50+    │  │
│  │ Chat     │  │ Telegram │  │ Memory   │  │ github │  │
│  │ Config   │  │ Discord  │  │ Sandbox  │  │ search │  │
│  │ Channels │  │ Slack    │  │ (Docker) │  │ notion │  │
│  │ Skills   │  │ Signal   │  │          │  │ ...    │  │
│  │ Cron     │  │ iMessage │  │ Browser  │  │        │  │
│  │ Debug    │  │ Teams    │  │ (Playw.) │  │        │  │
│  └──────────┘  │ Matrix   │  └──────────┘  └────────┘  │
│                │ ...      │                            │
│                └──────────┘                            │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Providers (LLM API)                 │  │
│  │  Anthropic | OpenAI | Google | OpenRouter | ...  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │              Plugins & Extensions                │  │
│  │  MCP (mcporter) | Custom plugins | ClawHub       │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

### Detailní schéma: Gateway, Agent, gateway-client a pairing

```
┌─────────────────────── Hetzner VPS (Docker) ─────────────────────────┐
│                                                                      │
│  ┌─────────────── kontejner: openclaw-gateway-1 ────────────────┐    │
│  │                                                              │    │
│  │  ┌────────────────── GATEWAY (Node.js) ───────────────────┐  │    │
│  │  │  Hlavní server proces — řídí vše                       │  │    │
│  │  │  Naslouchá na ws://0.0.0.0:18789                       │  │    │
│  │  │                                                        │  │    │
│  │  │  ┌───────────────┐     ┌───────────────────────────┐   │  │    │
│  │  │  │   WhatsApp    │     │         AGENT             │   │  │    │
│  │  │  │   (Baileys)   │     │   (AI — Claude Haiku)     │   │  │    │
│  │  │  │               │     │                           │   │  │    │
│  │  │  │ Připojuje se  │────>│ Přijímá zprávy,           │   │  │    │
│  │  │  │ k WhatsApp    │     │ generuje odpovědi,        │   │  │    │
│  │  │  │ serverům      │     │ volá skills/tools         │   │  │    │
│  │  │  └───────────────┘     │                           │   │  │    │
│  │  │                        │    Když potřebuje         │   │  │    │
│  │  │                        │    tool (cron, message,   │   │  │    │
│  │  │                        │    restart...) vytvoří:   │   │  │    │
│  │  │                        │         │                 │   │  │    │
│  │  │                        └─────────┼─────────────────┘   │  │    │
│  │  │                                  │                     │  │    │
│  │  │                                  v                     │  │    │
│  │  │                   ┌──────────────────────────┐         │  │    │
│  │  │                   │    GATEWAY-CLIENT        │         │  │    │
│  │  │                   │    (interní WS klient)   │         │  │    │
│  │  │                   │                          │         │  │    │
│  │  │                   │  ws://127.0.0.1:18789    │         │  │    │
│  │  │                   │  deviceId: 336623ef...   │         │  │    │
│  │  │                   │  Připojuje se zpět       │         │  │    │
│  │  │                   │  k vlastnímu gateway!    │         │  │    │
│  │  │                   └────────────┬─────────────┘         │  │    │
│  │  │                                │                       │  │    │
│  │  │                     loopback   │  WebSocket            │  │    │
│  │  │                                v                       │  │    │
│  │  │  ┌─────────────────────────────────────────────────┐   │  │    │
│  │  │  │          GATEWAY API (WebSocket server)         │   │  │    │
│  │  │  │                                                 │   │  │    │
│  │  │  │  Ověřuje device token + scopes                  │   │  │    │
│  │  │  │  Zpracovává: chat, cron, tools, config...       │   │  │    │
│  │  │  │                                                 │   │  │    │
│  │  │  │  Připojení přijímá od:                          │   │  │    │
│  │  │  │    • gateway-client (agent, zevnitř)            │   │  │    │
│  │  │  │    • control-ui (WebUI, zvenčí přes tunel)      │   │  │    │
│  │  │  └─────────────────────────────────────────────────┘   │  │    │
│  │  └────────────────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                              │                                       │
│                     port 18789 (pouze 127.0.0.1)                     │
│                              │                                       │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
                          SSH tunel                    WhatsApp servery
                          port 2222                    (web.whatsapp.com)
                               │                             ▲
                               │                             │
                    ┌──────────┴──────────┐          Baileys WebSocket
                    │   Tvůj počítač      │          (z kontejneru ven)
                    │                     │
                    │  localhost:18789 ───┤
                    │       │             │
                    │       v             │
                    │  ┌──────────┐       │
                    │  │  WEB UI  │       │
                    │  │ (prohlí- │       │
                    │  │  žeč)    │       │
                    │  │          │       │
                    │  │ deviceId:│       │
                    │  │ e993ae.. │       │
                    │  └──────────┘       │
                    └─────────────────────┘
```

#### Device pairing a scopes

Agent (gateway-client) i Web UI jsou z pohledu gateway **samostatná zařízení**,
každé s vlastním `deviceId`, tokenem a sadou scope. Při připojení gateway
ověřuje, zda požadované scopes odpovídají schváleným — jakákoli neshoda
(i downgrade) vyžaduje re-pairing.

| Scope | Popis | Hierarchie |
|---|---|---|
| `operator.read` | Čtení dat | Splněn i přes write nebo admin |
| `operator.write` | Zápis (posílání zpráv, tools) | Pouze přesná shoda |
| `operator.admin` | Administrace (cron, config) | Pouze přesná shoda |
| `operator.approvals` | Schvalování požadavků | Pouze přesná shoda |
| `operator.pairing` | Správa device pairingu | Pouze přesná shoda |

**Důležité:** `operator.admin` **nezahrnuje** `operator.write` — jsou nezávislé.
Agent potřebuje všech 5 scope, aby mohl používat všechny tools bez chyb.

Soubory na serveru:
- `~/.openclaw-gw/devices/paired.json` — schválená zařízení a jejich scopes
- `~/.openclaw-gw/devices/pending.json` — čekající požadavky na schválení
- `~/.openclaw-gw/identity/device-auth.json` — klientská identita agenta

### Klíčové komponenty

**1. Gateway** — centrální server (Node.js proces)
- Řídí všechny sessions, kanály, nástroje a události
- Běží jako daemon (Docker kontejner / systemd / launchd)
- Komunikuje s LLM přes API (žádné lokální modely, vše vzdáleně)
- Soubory: `src/gateway/`, `src/cli/gateway-cli/`

**2. Web UI (Control UI)** — prohlížečové rozhraní na `:18789`
- Chat s AI, správa kanálů, skills, cron jobs, konfigurace
- Vyžaduje device pairing při prvním připojení
- Soubory: `ui/`

**3. Channels** — komunikační kanály
- 9 vestavěných (WhatsApp, Telegram, Discord, Slack, Signal, iMessage, Teams, Google Chat, WebChat)
- Další přes extensions/ (Matrix, Mattermost, IRC, LINE, Nostr, Twitch...)
- Soubory: `src/telegram/`, `src/discord/`, `src/slack/`, `src/web/`, `extensions/`

**4. Agents & Sessions** — AI agent systém
- Každá konverzace = session
- Multi-agent routing (různé kanály → různí agenti)
- Memory systém: lokální embeddings (node-llama-cpp), sqlite-vec + FTS hybrid search
- **Active Memory** plugin: automatický recall relevantního kontextu PŘED odpovědí
- **Dreaming**: noční konsolidace paměti, promovuje vzory do MEMORY.md
- Soubory: `src/agents/`, `src/sessions/`, `src/memory/`

**5. Sandbox** — izolované prostředí pro spouštění kódu
- Docker kontejnery (Dockerfile.sandbox, Dockerfile.sandbox-common, Dockerfile.sandbox-browser)
- Agent může bezpečně spouštět kód uvnitř sandboxu
- Soubory: `src/agents/sandbox/`

**6. Skills** — dvouúrovňový systém
- **Bundled skills** (50+): v Docker image (`/app/skills/`) — github, weather, obsidian, spotify...
- **Workspace skills**: v `workspace/skills/` — custom skills, vyšší priorita než bundled
- Claudie může vytvářet vlastní skills zápisem `SKILL.md` do `workspace/skills/<name>/`
- Custom skill šablony v repo: `.my/skills/` (kopírovány do workspace při upgrade, nepřepisují existující)
- ClawHub = marketplace pro komunitní skills
- Žádné skill volume mounty — vše přes workspace auto-discovery

**7. Plugins & MCP** — rozšiřitelnost
- Plugin API pro vlastní rozšíření
- MCP podpora přes `mcporter` (Model Context Protocol)
- Soubory: `src/plugins/`, `extensions/`

**8. Security** — bezpečnostní vrstva
- Skill scanner (detekce eval, exec, crypto-mining)
- Sandbox validace (blokované cesty, Docker socket)
- Env sanitizace (NODE_OPTIONS, LD_PRELOAD blokované)
- Dangerous tools denylist
- Soubory: `src/security/`

### Adresářová struktura src/

```
src/
├── agents/          # Agent logika, sandbox, bash tools
├── browser/         # Playwright browser automation
├── canvas-host/     # Vizuální workspace (Canvas)
├── cli/             # CLI wiring, gateway CLI
├── commands/        # Všechny CLI příkazy (doctor, setup, agent...)
├── config/          # Konfigurace, openclaw.json schema
├── cron/            # Plánované úlohy
├── discord/         # Discord kanál
├── gateway/         # Centrální gateway server
├── channels/        # Sdílená logika kanálů
├── hooks/           # Hook systém
├── infra/           # Infrastruktura, env security
├── media/           # Media pipeline (obrázky, audio, video)
├── memory/          # Memory plugins
├── pairing/         # Device pairing
├── plugins/         # Plugin loader, installer
├── providers/       # LLM providery (Anthropic, OpenAI, Gemini...)
├── routing/         # Message routing mezi kanály
├── security/        # Bezpečnostní audit, skill scanner
├── sessions/        # Session management
├── signal/          # Signal kanál
├── slack/           # Slack kanál
├── telegram/        # Telegram kanál
├── terminal/        # Terminal UI, tabulky, barvy
├── web/             # WhatsApp Web kanál
└── wizard/          # Onboarding wizard
```

### Datový tok (jak funguje zpráva)

```
Uživatel (browser/Telegram/...)
  → Gateway přijme zprávu
    → Routing (který agent? který kanál?)
      → Session (kontext, paměť)
        → LLM API (OpenAI Codex / Anthropic Claude)
          → Odpověď + volání nástrojů
            → Sandbox (pokud kód)
            → Skills (pokud aktivní)
          → Odpověď zpět do kanálu
        → Uživatel vidí odpověď
```

**Aktuální LLM provider (od 2026-04-05):** OpenAI Codex (`openai-codex/gpt-5.4`)
přes ChatGPT Plus subscription (499 Kč/měs). OpenAI explicitně povoluje Codex OAuth
v third-party nástrojích. Anthropic Claude zůstává jako záložní profil (blokován
pro third-party od 4.4.2026).

---

## Webové aplikace (Claudie) a mobilní přístup

### Architektura přístupu

Claudie (AI agent) může vytvářet webové aplikace uvnitř gateway kontejneru. Ty jsou dostupné
přes pre-alokované porty 3800–3810.

```
┌──────────────┐                    ┌──────────── Hetzner VPS ─────────────┐
│  Počítač     │    SSH tunel       │                                      │
│  localhost:  │ =================> │  127.0.0.1:3800-3810                 │
│  38XX        │   (port 2222)      │       │                              │
└──────────────┘                    │       ▼                              │
                                    │  ┌────────────────────────────────┐  │
┌──────────────┐    WireGuard VPN   │  │  openclaw-gateway kontejner    │  │
│  Mobil       │ =================> │  │  (Node 22)                     │  │
│  (Pixel 8a)  │                    │  │                                │  │
│  http://10.  │   10.10.0.1        │  │  ~/workspace/moje-appka/       │  │
│  10.0.1:38XX │   :3800-3810       │  │    └── node server.js :38XX    │  │
└──────────────┘                    │  │                                │  │
                                    │  └────────────────────────────────┘  │
                                    └──────────────────────────────────────┘
```

### Pravidla pro Claudii (skill `webapp`)

- Povolené porty: **3800–3810** (pre-alokovány v `docker-compose.override.yml`)
- Porty vystaveny na `127.0.0.1` (SSH tunel) i `10.10.0.1` (WireGuard VPN)
- Jiné porty nebudou dostupné — Docker je nevystaví
- Aplikace žijí v `~/workspace/` (sdílený volume s hostem)
- Aplikace nepřežijí restart kontejneru samy — pro trvalost použít systemd službu (viz níže)
- Playwright + headless Chromium k dispozici pro testování (build arg `OPENCLAW_INSTALL_BROWSER=1`)
- Server: 4 GB RAM + 2 GB swap (swappiness=10) — po Chromium testu vždy `browser.close()`

### WireGuard VPN (přístup z mobilu)

| Parametr | Hodnota |
|---|---|
| VPS WireGuard IP | `10.10.0.1` |
| Mobil WireGuard IP | `10.1.3.2` |
| Server config | `/etc/wireguard/wg0.conf` |
| Port | `51820/udp` |

- WireGuard server nainstalován přímo na hostu (ne v kontejneru)
- Mobil má profil "HA" se dvěma peery (domácí router + VPS)
- Přístup z mobilu: `http://10.10.0.1:38XX`

### Aktuální aplikace

| Port | Aplikace | Popis | Správa |
|---|---|---|---|
| 3800 | Velké kameny (nocni-projekt) | Personal command center — C.S. Lewis citáty, denní kameny, kalendář, počasí | manuální |
| 3801 | Brainbox (vault-viewer) | Obsidian-like vault viewer pro mobil, info-log | systemd |
| 3802–3810 | Volné | | — |

### Systemd služby pro trvalé webapps

Webapps, které mají přežít restart kontejneru, jsou spravovány host-level systemd platformou.
Claudie může přidávat/odebírat služby přes JSON requesty v workspace — bez SSH přístupu.

```
Claudie (kontejner)  →  workspace/services/requests/<uuid>.json
                              ↓  (bind mount)
Host systemd .path   →  detekuje nový soubor
                              ↓
Processor script     →  validuje → vytvoří unit → start
                              ↓
                         workspace/services/results/<uuid>.json  →  Claudie čte výsledek
```

**Bezpečnost:** Processor validuje vstupy — porty 3800-3810, cesta v workspace, bezpečný název.
ExecStart je vždy šablona (`openclaw-app-ctl.sh`), žádný arbitrary exec.

**Správa:** `systemctl --user {status|restart|stop} openclaw-<name>`
**Logy:** `journalctl --user -u openclaw-<name>`
**Detaily:** viz `OpenClaw_server_info.md` sekce "Systemd služby pro webapps"

---

## První kroky — doporučený postup

### Krok 1: Otevřít web UI a spárovat zařízení

```bash
# Na lokálním PC:
ssh -N openclaw        # otevře SSH tunel
# Otevřít: http://localhost:18789
```

Při prvním přístupu bude vyžadováno **device pairing**:
```bash
# Na VPS:
ssh myclaw
cd ~/openclaw
docker compose exec openclaw-gateway node dist/index.js devices approve <requestId>
```

### Krok 2: Otestovat chat přes CLI

```bash
ssh myclaw
cd ~/openclaw
docker compose run --rm openclaw-cli agent --message "Ahoj, kdo jsi?" --thinking low
```

### Krok 3: Prozkoumat konfiguraci

```bash
# Zobrazit aktuální konfiguraci
ssh myclaw "cat ~/.openclaw-gw/openclaw.json"

# Diagnostika
ssh myclaw "cd ~/openclaw && docker compose run --rm openclaw-cli doctor"
```

### Krok 4: Aktivovat skills (volitelně)

Přes web UI → Skills → zapnout vybrané (github, brave-search, weather...)

### Krok 5: Připojit kanál (volitelně)

Přes web UI → Channels → přidat Telegram/Discord/...

---

## PII Anonymizace (Regex Proxy)

### Architektura

Veškerá PII detekce je **lokální regex + česká znalostní báze** (jména, příjmení, adresy).

```
┌─────────────── VPS (Docker) ───────────────────────────────┐
│                                                            │
│  ┌───────────────────┐       ┌───────────────────────┐     │
│  │  OpenClaw Gateway │──────>│  pii-proxy            │     │
│  │  (Node.js)        │       │  (Python FastAPI)     │     │
│  │                   │       │  port 3001            │     │
│  │  baseUrl:         │       │                       │     │
│  │  pii-proxy        │       │  1. Regex PII detekce │     │
│  └───────────────────┘       │  2. Anonymizace       │     │
│         │                    │  3. Forward do LLM API│     │
│         │                    │  4. De-anonymizace    │     │
│         │                    └───────┬───────┬───────┘     │
│         │                            │       │             │
│         │                            ▼       ▼             │
│         │           ┌────────────┐  ┌────────────────┐     │
│         │           │ OpenAI API │  │ Anthropic API  │     │
│         │           │ (Codex)    │  │ (záloha)       │     │
│         │           │ chatgpt.   │  │ api.anthropic  │     │
│         │           │ com        │  │ .com           │     │
│         │           │            │  │                │     │
│         │           │ vidí jen   │  │ vidí jen       │     │
│         │           │ <PERSON_1> │  │ <PERSON_1>     │     │
│         │           └────────────┘  └────────────────┘     │
└─────────┼──────────────────────────────────────────────────┘
```

### Jak to funguje

**OpenAI Codex (primární, od 2026-04-05):**
1. OpenClaw pošle LLM request na `http://pii-proxy:3001/openai/codex/responses`
2. Proxy zkontroluje `/noanon` marker — pokud přítomen, přeskočí anonymizaci
3. Proxy extrahuje text z `input[]`/`messages[]` (OpenAI formát)
4. Regex detekce PII entit (jména, telefony, emaily, adresy, rodná čísla, IBAN)
5. Proxy nahradí PII číslovanými placeholdery: `Jan Novák` → `<PERSON_1>`
6. Anonymizovaný request jde do `chatgpt.com/backend-api/codex/responses`
7. Odpověď (streaming SSE) projde de-anonymizací: `<PERSON_1>` → `Jan Novák`
8. Uživatel vidí odpověď s reálnými údaji

**Anthropic Claude (záložní):**
1. OpenClaw pošle LLM request na `http://pii-proxy:3001/v1/messages`
2. Stejný PII pipeline jako výše
3. Forward do `api.anthropic.com/v1/messages`

### Detekce jmen — česká znalostní báze

Proxy obsahuje rozsáhlou znalostní bázi pro detekci českých jmen:

- **100+ křestních jmen** (české, slovenské, německé, polské varianty)
- **160+ explicitních příjmení** (známé kontakty, kolegové)
- **Suffix-based detekce**: `-ová`, `-ský`, `-ský`, `-ek`, `-ík` atd.
- **Stem matching pro 7 pádů**: Novák/Nováka/Novákovi/Novákem...
- **Samohláská alternace**: Peterka → Peterky (genitiv)
- **Standalone detekce**: jedno velké slovo, pokud je ve znalostní bázi
- **False-positive ochrana**: deny-list běžných českých slov (smetana, svoboda, černý, holub...)

### Detekované entity

| Typ | Metoda | Příklad |
|---|---|---|
| PERSON | Znalostní báze + suffix + stem matching | Jan Novák, Nováka, Steinberger |
| PHONE_NUMBER | Regex (CZ/SK/mezinárodní) | +420 731 131 426 |
| EMAIL_ADDRESS | Regex | jan.novak@firma.cz |
| CZECH_ADDRESS | Regex (ulice + č.p. + PSČ) | Zkušebny 123/45, 110 00 Praha 1 |
| IBAN_CODE | Regex (CZ/SK prefix) | CZ65 0800 0000 1920 0014 5399 |
| BIRTH_NUMBER | Regex (rodné číslo) | 850101/1234 |

### Bypass anonymizace (`/noanon`)

Uživatel může jednorázově přeskočit anonymizaci přidáním `/noanon` na začátek zprávy:

```
/noanon Jaká je adresa Jana Nováka?
```

- Proxy detekuje `/noanon` marker, odstraní ho, a přeskočí PII anonymizaci
- Platí **jen pro daný request** — další zprávy jsou anonymizovány normálně
- Claudie o této možnosti ví přes skill `noanon` (SKILL.md v systémovém promptu)
- Skill má `user-invocable: false` — gateway ho nezachytí jako command, marker projde na proxy

### Kde jsou jaká data

| Data | Umístění | Anonymizované? | Opouští VPS? |
|---|---|---|---|
| Session JSONL | VPS `/sessions/` | NE (originál) | NE |
| Vault/Memory | VPS `/workspace/` | NE (originál) | NE |
| Embeddings | VPS sqlite-vec | N/A (vektory) | NE (lokální model) |
| **LLM prompt (OpenAI)** | **OpenAI API** | **NE** (pii-proxy nepoužito) | **ANO → cloud** |
| **LLM prompt (Anthropic)** | **Anthropic API** | **ANO** (přes pii-proxy) | **ANO → cloud** |
| **LLM odpověď** | **OpenAI/Anthropic** | **viz výše** | **ANO → cloud** |

> **Pozn.:** PII proxy anonymizuje pouze Anthropic provoz (`baseUrl: pii-proxy:3001`).
> OpenAI Codex provoz jde přímo bez anonymizace. Pokud potřebuješ PII ochranu
> i pro OpenAI, je třeba nastavit OpenAI provider přes pii-proxy.

### Docker služby

| Služba | Image | RAM | Účel |
|---|---|---|---|
| `pii-proxy` | custom (Python 3.12-slim) | ~50 MB | Regex PII detekce + API proxy |


### Konfigurace

V `openclaw.json`:
```json
{
  "models": {
    "providers": {
      "openai-codex": {
        "baseUrl": "http://pii-proxy:3001/openai",
        "api": "openai-codex-responses",
        "models": []
      },
      "anthropic": {
        "baseUrl": "http://pii-proxy:3001",
        "api": "anthropic-messages",
        "models": []
      }
    }
  }
}
```

V `docker-compose.override.yml`: služba `pii-proxy` (build z `./pii-proxy/`).

### Omezení

- Regex detekce — závisí na znalostní bázi, nová jména je třeba přidat ručně
- Český jazyk: stem matching pokrývá 7 pádů, ale neformální text může uniknout
- Systémový prompt se neanonymizuje (optimalizace výkonu)
- Latence: minimální (~10-50ms, vše lokální regex)

---

## Plaud.ai integrace (sync + linking enrichment)

### Architektura

Přepisy schůzek z Plaud zápisníku se automaticky synchronizují do vault jako Markdown soubory.
Sync běží na **hostu** přes systemd timer každých 10 minut. Po každé změně je spuštěna
deterministická vrstva linking enrichment **uvnitř kontejneru** přes `docker exec`.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Hetzner VPS                                │
│                                                                         │
│  ┌──────────── HOST ─────────────┐    ┌──── DOCKER (gateway) ─────┐     │
│  │                               │    │                           │     │
│  │  systemd: plaud-sync.timer    │    │  ┌─────────────────────┐  │     │
│  │  ↓ (každých 10 min)           │    │  │ plaud_link_enrich.py│  │     │
│  │  plaud-sync.py                │    │  │ (Python, layer A)   │  │     │
│  │                               │    │  │                     │  │     │
│  │  1. /file/simple/web ────────────────────────►              │  │     │
│  │  2. /filetag/        ────────────────────────►              │  │     │
│  │  3. /file/detail/{id}─────────► api.plaud.ai│              │  │     │
│  │  4. zápis .md do vault        │    │  │                     │  │     │
│  │  5. docker exec ───────────────────►│ --files <changed>   │  │     │
│  │     (po každém cyklu)         │    │  │                     │  │     │
│  │                               │    │  │ doplní:             │  │     │
│  │  state: .plaud-state.json     │    │  │  - related: ve FM   │  │     │
│  │                               │    │  │  - ## Související   │  │     │
│  │                               │    │  │    blok             │  │     │
│  │                               │    │  └─────────────────────┘  │     │
│  └───────────────────────────────┘    │                           │     │
│            │                          │  OpenClaw cron:           │     │
│            │ shared volume            │   "Plaud linking          │     │
│            │ (workspace/)             │    enrichment — nightly"  │     │
│            ▼                          │   schedule: 15 2 * * *    │     │
│  ┌────────────────────────────────────┴──┐ (spustí --all noc)    │     │
│  │  vault/Inbox/Plaud/                   │                       │     │
│  │  ├── Alza.sk/                         │                       │     │
│  │  ├── FHB/         (podle Plaud tagů)  │                       │     │
│  │  ├── OEZ/                             │                       │     │
│  │  ├── ...                              │                       │     │
│  │  ├── projects.json     (project tags) │                       │     │
│  │  ├── linking-map.json  (related map)  │                       │     │
│  │  ├── .plaud-state.json (sync state)   │                       │     │
│  │  └── .plaud-linking-state.json        │                       │     │
│  └───────────────────────────────────────┘                       │     │
│                                                                  │     │
│  Chokidar watch → memory search auto-index                       │     │
└──────────────────────────────────────────────────────────────────┴─────┘
                                  │
                       Plaud reverse-eng. API
                       (api-euc1.plaud.ai)
                       ▲
                       │
                  [Plaud zápisník + appka]
```

### Dvě vrstvy linking enrichmentu

| Vrstva | Kdy | Spouštěč | Co dělá |
|---|---|---|---|
| **A — sync-time** | každých 10 min, jen pro změněné | `plaud-sync.py` → `docker exec` | Deterministicky doplní `related:` ve frontmatteru a sekci `## Související` (mezi `<!-- AUTOGENERATED -->` značkami) |
| **B — nightly** | 02:15 CET | OpenClaw cron job (Claudie spustí `--all`) | Stejná logika nad celým Plaud stromem (přepočítá vše, např. po změně `linking-map.json`) |

Obě vrstvy používají **stejný script** `plaud_link_enrich.py`. Ruční poznámky v `## Moje poznámky`
zůstávají nedotčené (enrichment sahá pouze do vyhrazených bloků).

### Klíčové soubory

| Soubor | Umístění | Účel |
|---|---|---|
| `plaud-sync.py` | host: `/home/deploy/openclaw/plaud-sync/` | Sync script (systemd) |
| `plaud-sync.timer/.service` | host: `~/.config/systemd/user/` | Plánování (10 min) |
| `.env` | host: `/home/deploy/openclaw/plaud-sync/` | `PLAUD_TOKEN` (JWT, ~10 měs.), `PLAUD_API_DOMAIN` |
| `plaud_link_enrich.py` | container: `/home/node/.openclaw/workspace/scripts/` | Deterministický enrichment |
| `projects.json` | vault: `Inbox/Plaud/` | Mapping `název projektu → project tag` |
| `linking-map.json` | vault: `Inbox/Plaud/` | Mapping `project tag → related MOC/poznámky` |
| `.plaud-state.json` | vault: `Inbox/Plaud/` | Sync state (file_version, folder, filepath) |
| `.plaud-linking-state.json` | vault: `Inbox/Plaud/` | Enrichment state (contentHash, linkingVersion) |

### Cesty: host vs. kontejner

Sync script čte/zapisuje na host cestě `/home/deploy/.openclaw-gw/workspace/vault/Inbox/Plaud/`.
Enrichment script má hardcoded `WORKSPACE = /home/node/.openclaw/workspace` (cesta v kontejneru).
Sync překládá cesty před voláním:

```
host:      /home/deploy/.openclaw-gw/workspace/vault/Inbox/Plaud/FHB/<file>.md
container: /home/node/.openclaw/workspace/vault/Inbox/Plaud/FHB/<file>.md
```

### Chování při chybě enrichmentu

- Sync cyklus je vždy úspěšný (soubory zapsány do vault).
- `docker exec` s timeoutem 60s; non-zero exit / timeout / exception → **zalogovat a pokračovat**.
- Příští cyklus (za 10 min) zkusí znovu — idempotentní.

### Detekce nových / smazaných záznamů

- **Nový/změněný** detekován porovnáním `version_ms` z Plaud API se `.plaud-state.json`.
- **Trashed/removed** v Plaud → `.md` soubor se z vault smaže (a state entry odebere).
- **Folder change** → `.md` soubor se přesune do nové podsložky (zachová ruční poznámky).

### Přidání nového projektu (pro Claudii)

1. Edit `vault/Inbox/Plaud/projects.json`: `"Nový projekt": "project/Nový-projekt"`
2. Edit `vault/Inbox/Plaud/linking-map.json` v sekci `projects`: přidat `"project/Nový-projekt": { "related": [...] }`
3. Pro přepsání existujících záznamů: `docker exec openclaw-openclaw-gateway-1 python3 /home/node/.openclaw/workspace/scripts/plaud_link_enrich.py --all` (nebo počkat na noční job).

---

## Self-service upgrade (od 2026-04-16)

Claudie může sama upgradovat OpenClaw na poslední stabilní verzi.

```
Claudie (kontejner) → workspace/.upgrade-trigger (JSON)
       ↓
systemd path unit (host) → openclaw-upgrade.sh
       ↓
git pull + merge upstream + docker compose build + restart + health check
       ↓
workspace/.upgrade-result (JSON) ← Claudie čte po restartu
```

- **Trigger akce:** `upgrade` (merge + build), `deploy` (jen build), `rollback`
- **Automatický rollback:** Docker image backup + git tag; health check selhání → obnoví předchozí verzi
- **Konfliktní plocha:** nulová (Anthropic OAuth patche odstraněny)
- **Skill šablony:** `.my/skills/` → `workspace/skills/` (jen nové, nepřepisuje Claudiiny)
- **Detaily:** viz `OpenClaw_server_info.md` sekce "Self-service upgrade"

---

## Klíčové soubory pro studium

| Co chcete pochopit | Soubory |
|---|---|
| Jak gateway funguje | `src/gateway/`, `src/cli/gateway-cli/run.ts` |
| Jak se zpracuje zpráva | `src/routing/`, `src/sessions/` |
| Jak fungují tools/agent | `src/agents/`, `src/agents/bash-tools.exec.ts` |
| Bezpečnostní model | `SECURITY.md`, `src/security/` |
| Plugin systém | `src/plugins/loader.ts`, `VISION.md` |
| Konfigurace | `src/config/`, `.env.example` |
| Web UI | `ui/` |
| Sandbox | `src/agents/sandbox/`, `Dockerfile.sandbox*` |
| PII Anonymizace | `pii-proxy/proxy.py` |
| Per-channel model routing | `src/channels/model-overrides.ts` |
| Plaud sync (host) | `/home/deploy/openclaw/plaud-sync/plaud-sync.py` |
| Plaud linking enrichment (container) | `workspace/scripts/plaud_link_enrich.py` |
