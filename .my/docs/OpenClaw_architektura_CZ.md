# OpenClaw — Architektura a první kroky

## Kontext

OpenClaw je nainstalován na Hetzner VPS v Docker kontejneru. Gateway běží, web UI je dostupné přes SSH tunel na `http://localhost:18789`.

---

## Architektura OpenClaw

### Celková architektura

```
┌─────────────────────────────────────────────────────────┐
│                    OpenClaw Gateway                      │
│                  (Node.js 22, TypeScript)                │
│                                                          │
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
│                │ ...      │                              │
│                └──────────┘                              │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Providers (LLM API)                  │   │
│  │  Anthropic | OpenAI | Google | OpenRouter | ...   │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              Plugins & Extensions                 │   │
│  │  MCP (mcporter) | Custom plugins | ClawHub        │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
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
- Memory systém (plugin slot)
- Soubory: `src/agents/`, `src/sessions/`, `src/memory/`

**5. Sandbox** — izolované prostředí pro spouštění kódu
- Docker kontejnery (Dockerfile.sandbox, Dockerfile.sandbox-common, Dockerfile.sandbox-browser)
- Agent může bezpečně spouštět kód uvnitř sandboxu
- Soubory: `src/agents/sandbox/`

**6. Skills** — vestavěné dovednosti (50+)
- github, brave-search, weather, obsidian, notion, spotify, skill-creator...
- Každý skill = samostatný adresář v `skills/`
- ClawHub = marketplace pro komunitní skills

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
        → LLM API (Anthropic Claude)
          → Odpověď + volání nástrojů
            → Sandbox (pokud kód)
            → Skills (pokud aktivní)
          → Odpověď zpět do kanálu
        → Uživatel vidí odpověď
```

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
