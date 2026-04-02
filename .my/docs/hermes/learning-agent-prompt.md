---
name: Learning Agent Implementation Prompt
description: Revised brief for Claudie to implement custom learning agent as OpenClaw plugin
type: project
---

# Learning Agent — Prompt pro Claudii (REVIZE v2)

**Cíl:** Vytvořit OpenClaw **plugin**, který analyzuje dokončené sessions a navrhuje nové skills.

**Timeline:** 4-6 týdnů (realistický odhad)  
**Stakeholder:** Martin (Tomis)

---

## KRITICKÉ OPRAVY oproti v1

1. **Plugin, NE `src/learning/`** — OpenClaw je upstream projekt. Přidání kódu do `src/` = fork. Správná cesta = plugin v `extensions/learning-agent/`.
2. **`session_end` hook, NE `llm_input`** — Learning potřebuje celou konverzaci (user+assistant) PO dokončení. `llm_input` vidí jen prompt PŘED odesláním do LLM.
3. **`event.prompt`, NE `event.message`** — PluginHookLlmInputEvent nemá pole `message`. Má `prompt`, `historyMessages`, `systemPrompt`.
4. **HEARTBEAT filtr povinný** — Většina sessions obsahuje automatické cron zprávy (`Read HEARTBEAT.md...`). Bez filtru bude learning agent detekovat heartbeat jako "opakující se pattern".
5. **User zprávy mají metadata wrapper** — Reálné user zprávy jsou obaleny v `Conversation info (untrusted metadata): {...}`. Parser musí extrahovat čistý text.
6. **Keyword matching je příliš primitivní** — Pro kvalitní návrhy skills je potřeba LLM (Haiku = $0.25/M input). Čisté klíčové slova zachytí max 20% případů.
7. **34 sessions, 21 MB dat** — Ne "10 sessions". Některé mají přes 1 MB.

---

## I. Architektura — OpenClaw Plugin

### Proč Plugin (ne `src/`)

OpenClaw je upstream projekt (NousResearch/openclaw). Přidání kódu do `src/` znamená fork, který nelze udržovat. OpenClaw má **stabilní plugin API** s 24 hook types a plným SDK:

```
extensions/learning-agent/          ← SPRÁVNÉ umístění
├── package.json
├── src/
│   ├── index.ts                    ← register(api) entry point
│   ├── session-analyzer.ts         ← parsuje JSONL, filtruje heartbeat
│   ├── pattern-detector.ts         ← detekce opakovaní (LLM-assisted)
│   ├── skill-proposer.ts           ← generuje SKILL.md návrhy
│   └── metrics.ts                  ← SQLite tracking
└── test/
    ├── session-analyzer.test.ts
    └── pattern-detector.test.ts
```

### Registrace Pluginu

```typescript
// extensions/learning-agent/src/index.ts
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { SessionAnalyzer } from "./session-analyzer.js";
import { PatternDetector } from "./pattern-detector.js";
import { SkillProposer } from "./skill-proposer.js";

export const id = "learning-agent";

export function register(api: OpenClawPluginApi) {
  const analyzer = new SessionAnalyzer(api.logger);
  const detector = new PatternDetector(api.logger);
  const proposer = new SkillProposer(api.logger);

  // Trigger analýzu při ukončení session
  api.registerHook("session_end", async (event, ctx) => {
    // event: { sessionId, sessionKey, messageCount, durationMs }
    // ctx:   { agentId, sessionKey, sessionId, workspaceDir, channelId }
    
    if (event.messageCount < 4) return; // Příliš krátké session ignoruj
    
    try {
      const messages = await analyzer.parseSession(ctx.workspaceDir!, event.sessionId);
      const patterns = await detector.detect(messages);
      
      if (patterns.length > 0) {
        await proposer.propose(patterns, ctx.workspaceDir!);
        api.logger.info(`learning-agent: ${patterns.length} pattern(s) detected`);
      }
    } catch (err) {
      api.logger.warn(`learning-agent failed: ${String(err)}`);
    }
  });

  // Volitelně: CLI příkaz pro manuální analýzu
  api.registerCli((program) => {
    program
      .command("learning")
      .description("Analyze sessions for learnable patterns")
      .option("--since <days>", "Analyze sessions from last N days", "14")
      .action(async (opts) => {
        // Batch analýza všech sessions
      });
  });
}
```

---

## II. Session Format — Reálná Data

### Struktura na Serveru

```
~/.openclaw-gw/agents/main/sessions/     (34 souborů, 21 MB)
├── b05d83bf-...-.jsonl                   (reálná konverzace)
├── a8c7b8d8-...-.jsonl                   (heartbeat session)
├── b0eb1476-...-.jsonl.reset.2026-04-01  (resetovaná session, 1.4 MB!)
└── ...
```

### JSONL Event Types (ověřeno ze zdrojového kódu)

```typescript
// Reálný session event
{ "type": "session", "version": 3, "id": "...", "timestamp": "...", "cwd": "..." }

// User message — POZOR: obalena metadaty!
{ "type": "message", "id": "...", "message": {
    "role": "user",
    "content": [{ "type": "text", "text": "Conversation info (untrusted metadata):\n```json\n{...}\n```\n\nSkutečný text uživatele" }]
  }
}

// Assistant response
{ "type": "message", "id": "...", "message": {
    "role": "assistant",
    "content": [{ "type": "text", "text": "Odpověď Claudie..." }],
    "model": "delivery-mirror",
    "usage": { "input": 1234, "output": 567, "cost": { "total": 0.05 } }
  }
}

// Model/thinking changes
{ "type": "model_change", ... }
{ "type": "thinking_level_change", "thinkingLevel": "medium" }
```

### Session Parser (opravený)

```typescript
interface ParsedMessage {
  role: "user" | "assistant";
  text: string;                 // Čistý text BEZ metadata wrapperu
  timestamp: number;
  model?: string;
  usage?: { input?: number; output?: number; total?: number };
  isHeartbeat: boolean;         // KRITICKÉ: filtrovat!
}

async function parseSessionFile(filePath: string): Promise<ParsedMessage[]> {
  const content = await fs.readFile(filePath, "utf-8");
  const messages: ParsedMessage[] = [];

  for (const line of content.split("\n")) {
    if (!line.trim()) continue;
    
    let event: any;
    try { event = JSON.parse(line); } catch { continue; }
    
    if (event.type !== "message") continue;
    
    const msg = event.message;
    const rawText = msg.content?.[0]?.text ?? "";
    
    // Extrahuj čistý text z metadata wrapperu
    const cleanText = stripConversationMetadata(rawText);
    
    // Detekuj heartbeat
    const isHeartbeat = cleanText.includes("HEARTBEAT") 
                     || cleanText.includes("Read HEARTBEAT.md");
    
    messages.push({
      role: msg.role,
      text: cleanText,
      timestamp: new Date(event.timestamp).getTime(),
      model: msg.model,
      usage: msg.usage,
      isHeartbeat,
    });
  }

  return messages;
}

function stripConversationMetadata(text: string): string {
  // Reálný formát: "Conversation info (untrusted metadata):\n```json\n{...}\n```\n\nSkutečný text"
  const match = text.match(/^Conversation info \(untrusted metadata\):[\s\S]*?```\s*\n\n([\s\S]*)$/);
  return match ? match[1].trim() : text;
}
```

---

## III. Pattern Detection — Dva Přístupy

### Přístup A: Keyword (levný, omezený)

Funguje pro explicitní opakování ("přelož", "shrň", "připomeň mi"):

```typescript
const PATTERNS = [
  { id: "translate", keywords: ["přelož", "translate", "do angličtiny", "do češtiny"], minOccurrences: 3 },
  { id: "summarize", keywords: ["shrň", "sumarizuj", "tl;dr", "shrnutí"], minOccurrences: 3 },
  { id: "calendar",  keywords: ["kalendář", "schůzka", "meeting", "událost"], minOccurrences: 4 },
  { id: "email",     keywords: ["napiš mail", "odešli", "draft email"], minOccurrences: 3 },
];
```

**Limit:** Zachytí max ~20% reálných opakujících se vzorů.

### Přístup B: LLM-Assisted (lepší, dražší)

Po dokončení session → odešli shrnutí do Haiku ($0.25/M input) → identifikuj vzory:

```typescript
async function detectWithLLM(
  sessions: ParsedMessage[][],
  existingSkills: string[]
): Promise<DetectedPattern[]> {
  // Seskup user zprávy z posledních 14 dní (bez heartbeat)
  const userMessages = sessions
    .flatMap(s => s.filter(m => m.role === "user" && !m.isHeartbeat))
    .map(m => m.text.substring(0, 200))  // Ořízni na 200 znaků
    .slice(-100);  // Max 100 zpráv

  const prompt = `Analyzuj tyto uživatelské zprávy a identifikuj opakující se vzory úloh.
Existující skills: ${existingSkills.join(", ")}

Zprávy (posledních 14 dní):
${userMessages.map((m, i) => `${i + 1}. ${m}`).join("\n")}

Vrať JSON pole detekovaných vzorů:
[{ "pattern": "název", "description": "popis", "occurrences": N, "confidence": 0.0-1.0 }]
Zahrň POUZE vzory s 3+ výskyty, které NEJSOU pokryty existujícími skills.`;

  // Volej Haiku přes OpenClaw API (přes pii-proxy → anonymizováno)
  const response = await callLLM("anthropic/claude-haiku-4-5", prompt);
  return JSON.parse(response);
}
```

**Cena:** ~$0.01-0.03 za analýzu (100 zpráv × 200 chars = ~10K tokens input).

### Doporučení: **Kombinuj oba**

1. Keyword matching vždy (zdarma)
2. LLM analýza 1× denně (cron, ~$1/měsíc)

---

## IV. Skill Proposer — Co Generujeme

OpenClaw skills jsou **markdown instrukce pro LLM** (ne spustitelný kód). Skill = SKILL.md s frontmatter + popis + příklady.

### Output

```
~/.openclaw-gw/workspace/.my/proposed-skills/
├── 2026-04-01-translator.md
├── 2026-04-03-meeting-summarizer.md
└── proposals.json                    ← index s metadaty
```

### Generovaný SKILL.md

```markdown
---
name: translator
description: "Překlad textu CZ↔EN. Detekováno 7x za 14 dní."
metadata:
  openclaw:
    emoji: "🌐"
    proposed_by: "learning-agent"
    confidence: 0.85
    occurrences: 7
    detected_at: "2026-04-01"
---

# Translator

Překlad textu mezi češtinou a angličtinou.

## When to Use

✅ "Přelož do angličtiny: ..."
✅ "Translate to Czech: ..."
✅ "Jak se řekne ... anglicky?"

## How

Přelož požadovaný text. Zachovej formátování (markdown, kód).
Pro odborné texty zachovej terminologii.
```

---

## V. Dostupné Hook Types (ověřeno ze zdrojového kódu)

```
session_start         ← session začíná
session_end           ← session končí (HLAVNÍ trigger)
message_received      ← příchozí zpráva z kanálu
message_sending       ← odchozí zpráva (před odesláním)
message_sent          ← odchozí zpráva (po odeslání)
llm_input             ← prompt PŘED odesláním do LLM (fire-and-forget)
llm_output            ← odpověď LLM (s usage stats)
before_tool_call      ← před voláním tool/skill
after_tool_call       ← po volání tool/skill
before_message_write  ← před zápisem zprávy do session
agent_end             ← agent dokončil zpracování
gateway_start         ← gateway se spustil
gateway_stop          ← gateway se zastavuje
```

### Pro Learning Agent relevantní:

| Hook | Kdy | Co získáš |
|------|-----|-----------|
| **`session_end`** | Po ukončení konverzace | `sessionId`, `messageCount`, `durationMs` |
| **`llm_output`** | Po každé LLM odpovědi | `usage` (tokeny, cena), `assistantTexts` |
| **`after_tool_call`** | Po volání skill | Které skills byly použity |

---

## VI. Implementační Fáze (realistické)

### Fáze 1: Parser + Plugin Skeleton (2 týdny)

```
extensions/learning-agent/
├── package.json                    { "name": "openclaw-learning-agent" }
├── src/
│   ├── index.ts                    register(api) + session_end hook
│   └── session-analyzer.ts         JSONL parser + heartbeat filtr
└── test/
    └── session-analyzer.test.ts    Test na real session data
```

**Deliverables:**
- [ ] Plugin se načte v gateway (ověř `openclaw doctor`)
- [ ] Parser správně extrahuje user/assistant zprávy
- [ ] Heartbeat zprávy jsou filtrovány
- [ ] Metadata wrapper (`Conversation info...`) je odstraněn
- [ ] `.reset` session soubory jsou zpracovány správně

### Fáze 2: Detection + Proposer (2 týdny)

```
src/
├── pattern-detector.ts             Keyword + LLM-assisted detection
├── skill-proposer.ts               SKILL.md generátor
└── ...
```

**Deliverables:**
- [ ] Keyword detection na existujících 34 sessions
- [ ] LLM-assisted detection (Haiku, 1× denně)
- [ ] SKILL.md generátor produkuje validní frontmatter
- [ ] Output do `.my/proposed-skills/`

### Fáze 3: Metrics + CLI (1-2 týdny)

**Deliverables:**
- [ ] `openclaw learning analyze` CLI command
- [ ] SQLite metrics (patterns, approval rate)
- [ ] Notifikace přes WhatsApp/WebUI o nových návrzích

---

## VII. Konfigurace

```json
{
  "plugins": {
    "learning-agent": {
      "enabled": true,
      "detection": {
        "minOccurrences": 3,
        "timeWindowDays": 14,
        "useLLM": true,
        "llmModel": "anthropic/claude-haiku-4-5",
        "llmSchedule": "0 2 * * *"
      },
      "output": {
        "dir": ".my/proposed-skills",
        "notifyChannel": "whatsapp"
      }
    }
  }
}
```

---

## VIII. Constraints (přečti před implementací!)

### 1. OpenClaw je upstream — NIKDY nepiš do `src/`

```
✅ extensions/learning-agent/     (plugin, správně)
❌ src/learning/                  (fork, ŠPATNĚ)
```

### 2. Sessions mají specifický formát

- User zprávy jsou obaleny `Conversation info (untrusted metadata):` wrapper
- HEARTBEAT zprávy = cron automatika, VŽDY filtruj
- `.jsonl.reset.*` soubory = archivované sessions (zpracuj jako normální)
- `message.model: "delivery-mirror"` = interní delivery, ignoruj

### 3. Hook `session_end` je fire-and-forget

- Nesmí blokovat gateway
- Catch všechny errory, log, nezachyť
- Analýza běží async

### 4. PII

- Data prochází pii-proxy → v sessions jsou ORIGINÁLNÍ (neanonymizovaná) data
- Learning agent nesmí posílat raw session data jinam než přes pii-proxy
- Pokud voláš LLM z pluginu, použij OpenClaw API (projde přes proxy)

### 5. Skills = markdown, ne kód

- SKILL.md je prompt/instrukce pro LLM
- Neobsahuje spustitelný kód
- `metadata.openclaw.requires.bins` = CLI nástroje (ne npm packages)

---

## IX. Co Claudie Musí Přečíst na Serveru

1. **Plugin API:** `src/plugins/types.ts` řádky 375-475 (registerHook, hook names)
2. **Plugin registrace:** `src/plugins/loader.ts` (jak se plugins loadují)
3. **Plugin SDK:** `src/plugin-sdk/index.ts` (exporty pro pluginy)
4. **Session end hook:** `src/plugins/types.ts` řádky 788-800 (SessionEndEvent)
5. **Příklady pluginů:** `extensions/msteams/` (jak se plugin strukturuje)
6. **Reálné sessions:** `~/.openclaw-gw/agents/main/sessions/*.jsonl`
7. **Existující skills:** `skills/github/SKILL.md`, `skills/gog/SKILL.md`
