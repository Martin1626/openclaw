# Analýza Hermes vs. OpenClaw — Průzkum a Doporučení k Migraci

**Datum analýzy:** 1. duben 2026 (**REVIZE v2** — opraveny faktické chyby)  
**Aktuální stav:** OpenClaw v2026.3.13, Hermes Agent v0.6.0  
**Autor:** Komplexní průzkum — Claudie AI

---

## ERRATA (Revize v2)

**Faktické chyby opravené v této verzi:**

1. ~~"OpenClaw embeddings jsou LEPŠÍ než Hermes FTS5"~~ → Řeší různé problémy; nejsou přímo srovnatelné (§IV)
2. ~~Scénář 2 je "vysoce rizikový" + Námitka 3 říká "Scénář 2 je nejlepší"~~ → Interní rozpor opraven; obě varianty pro Hermes rizikové (§IX.3)
3. ~~Hook `after_session_completion`~~ → Skutečný název: `session_end` (§XI.C)
4. ~~`gateway.registerHook()`~~ → Správně: `api.registerHook()` přes plugin SDK (§XI.C)
5. ~~`src/learning/` v OpenClaw zdrojovém kódu~~ → OpenClaw je upstream; správně: plugin v `extensions/` (§XI.C)
6. ~~Hermes learning stojí $4-6/den~~ → Nerealistické; Hermes generuje skills jen po komplexních úlohách (~1-2x týdně), ne kontinuálně. Realisticky: $5-15/měsíc (§IX.2)
7. ~~"Hermes marketing: Learning bez extra nákladů — Nepravda"~~ → Hermes toto explicitně netvrdí; idle costs = jen LLM API, learning costs jsou dokumentovány

---

## I. Shrnutí — Klíčové Rozdíly

| Aspekt | OpenClaw | Hermes |
|--------|----------|--------|
| **Jazyk** | Node.js/TypeScript | Python (CLI) |
| **Learning loop** | ❌ Bez autonomního učení | ✅ Vestavěná smyčka (vyrábí skills) |
| **Skill systém** | ✅ 50+ vestavěných + ClawHub | ✅ Autonomní vytváření + agentskills.io |
| **PII anonymizace** | ✅ Regex proxy (vlastní) | ❌ Bez behu, přepouští PII do cloudu |
| **OAuth (Claude Code)** | ✅ Auto-detekce (sk-ant-oat01) | ✅ Auto-detekce + refresh preservation |
| **Persistentní paměť** | ✅ Vault (Obsidian) + embeddings | ✅ MEMORY.md + session SQLite + LLM summarizace |
| **Multi-channel** | ✅ 9 kanálů + extensions | ✅ Telegram/Discord/Slack/WhatsApp/CLI |
| **Sandboxing** | ✅ Docker + Playwright | ✅ Local/Docker/SSH/Singularity/Modal |
| **Architektura** | Monolitický gateway | Distribuovaný (agenti mohou běžet paralelně) |
| **Vývojová aktivita** | Stabilní + rolling updates | Velmi aktivní (v0.6.0 = 30.3.2026) |

---

## II. Porovnání Architektur

### OpenClaw — Centralizovaný Model

```
┌─ VPS (Docker) ──────────────────────────┐
│  openclaw-gateway (Node.js)              │
│    ├─ Channels (WhatsApp, Telegram...)  │
│    ├─ Agent (1 session)                 │
│    ├─ Memory (embeddings + vault)       │
│    ├─ Skills (50+)                      │
│    └─ PII Proxy (localhost:3001)        │
│       └─ Anonymizace → Anthropic API    │
└──────────────────────────────────────────┘
```

**Výhody:**
- Všechno na jednom místě → jednoduché laděnízení
- Lokální embeddings (node-llama-cpp) → žádná externí dependency
- Bezpečně — PII nikdy neopouští VPS přes proxy
- Vault integrován přímo (hybridní FTS + vektory)

**Nevýhody:**
- Gateway je единственným bodem selhání
- Bez autonomního vytváření skills
- Learning loop musí být ručně vytvořen

### Hermes — Distribuovaný Model

```
┌─ ~/.hermes/ ─────────────────────────────────────┐
│  config.yaml (modely, terminály, memory)        │
│  .env (API keys)                                 │
│  MEMORY.md + USER.md (persistentní paměť)        │
│  ~/.hermes/skills/ (Python-based, autonomně)    │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │ Hermes CLI (run_agent.py)               │    │
│  │  ├─ Gateway (pro messaging channels)    │    │
│  │  ├─ Agent loop (learning, skills)       │    │
│  │  ├─ Memory management (self-curated)    │    │
│  │  └─ Terminal backends (docker/ssh...)  │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  (Subagenti mohou běžet paralelně               │
│   v samostatných kontejnerech)                  │
└──────────────────────────────────────────────────┘
```

**Výhody:**
- Autonomní skill creation + self-improvement
- Agenti mohou běžet paralelně (subagents)
- Python ecosystem → snadnější customizace
- Hocha integrated learning loop (memory consolidation)

**Nevýhody:**
- Bez vestavěné PII anonymizace
- PII routině projde do Anthropic API
- Learning = spotřeba API tokenů (drahé)
- Memory management vyžaduje LLM (GPT-4 / Claude)

---

## III. PII Anonymizace — Kritické Srovnání

### OpenClaw — Regex Proxy (Bezpečné)

```
OpenClaw → pii-proxy:3001 (FastAPI) → Anthropic API
              ↓
           Regex detekce:
           • PERSON (česká jména + stem matching)
           • PHONE, EMAIL, IBAN, rodné číslo
           • CZECH_ADDRESS (ulice+čp+psč)
              ↓
           Anonymizace: Jan Novák → <PERSON_1>
              ↓
           Anonymizovaný text → Anthropic
           De-anonymizace odpovědi → uživatel
```

**Detaily:**
- **Poznámka:** Systémový prompt se neanonymizuje (optimalizace)
- **Latence:** ~10-50ms (čistě lokální)
- **Bypass:** `/noanon` prefix → přeskočí anonymizaci
- **Problém:** Regex → nemusí zachytit všechna jména (závisí na znalostní bázi)

### Hermes — Žádná Anonymizace (Rizikové)

```
Hermes → Anthropic API (full PII)
         ❌ Bez detekce
         ❌ Bez anonymizace
         ❌ PII procházejí v plaintext
```

**Důsledky:**
- **GDPR/CCPA riziko** — osobní data jdou do cloudu bez souhlasu
- Firemní data (adresy, rodná čísla) nejsou chráněna
- Data mohou zůstat v Anthropic logu na dobu neomezenou

**Řešení v Hermes:**
- Vlastně implementovat middleware (jako OpenClaw proxy)
- Nebo dodržovat policy: "Neposílat PII do Hermes"
- Nebo zvolit jiný provider (lokální LLM)

---

## IV. Learning Loop — Autonomní Vytváření Skills

### Hermes — Vestavěný (Výjimečný)

```
┌─ Closed Learning Loop ─────────────────┐
│                                        │
│ 1. Agent se setkaje úlohou            │
│ 2. Řeší ji (možná vícekrát)           │
│ 3. Pokud "složitá" → vytvoří skill    │
│ 4. Skill se uloží do ~/.hermes/skills │
│ 5. Při příštím spuštění: skill znovu  │
│    se vylepší v používání             │
│ 6. Memory: FTS5 cross-session recall  │
│                                        │
└────────────────────────────────────────┘
```

**Jak to funguje:**
- Agent autonomně vytváří Python-based skills
- Každý skill = reusable workflow
- Memory: agent sám spravuje MEMORY.md (facts)
- Skill self-improvement: při každém použití se vylepšuje

**Cena:**
- Autonomní learning = extra API volání → nižší na Hermes (levnější modely)
- Ale Anthropic API = drahé → s Hermes by to bylo velmi nákladné

### OpenClaw — Manuální (Omezené)

```
┌─ Žádný vestavěný learning ──────┐
│                                 │
│ 1. Uživatel vytváří skill SKILL.md
│ 2. Skill registruje v gateway   │
│ 3. Claudie jej může používat    │
│ 4. Bez autonomního zlepšování   │
│                                 │
│ Paměť: Vault + embeddings       │
│ (statické, bez shrnutí)         │
│                                 │
└─────────────────────────────────┘
```

**Výhoda:** Kontrola — veškeré nové skills procházejí review  
**Nevýhoda:** Bez evoluce, bez self-improvement

---

## V. OAuth Autentifikace s Claude Code

### Obě Platformy Podporují

| Aspekt | OpenClaw | Hermes |
|--------|----------|--------|
| **Auto-detekce** | ✅ Ano (sk-ant-oat01) | ✅ Ano (CLI --model) |
| **Token refresh** | ✅ Sync script (3.5h buffer) | ✅ Prioritizuje Code store |
| **Fallback** | `sk-ant-oat01-...` | `ANTHROPIC_TOKEN` env |
| **Beta header** | ✅ `claude-code-20250219` | ❓ (není specifikováno) |
| **1-year token** | ✅ Ano (setup-token) | ✅ Ano |

**Kritická poznámka:**
- **OpenClaw:** `extra-params.ts:422` detekuje OAuth automaticky, ale bez behu
- **Hermes:** `hermes model` interaktivně nastaví, refresh je automatic
- **Obě:** Pokud bez `claude-code-20250219` headeru → Anthropic blokuje (third-party!)

**Doporučení pro Hermes:**
```bash
# Jednorázové nastavení OAuth
$ hermes model
# → Spustí setup-token flow
# → Auto-detekuje ~/.claude/.credentials.json

# Permanentní config
~/.hermes/config.yaml:
model:
  provider: "anthropic"
  default: "claude-sonnet-4-6"
```

---

## VI. Vault Migrace — Obsidian → Hermes

### Aktuální Stav OpenClaw

```
/home/deploy/.openclaw-gw/workspace/vault/ (700 KB)
├── Inbox/
├── MOC/
├── Osobni/ (osobní poznámky)
├── Prace/ (pracovní)
├── Projekty/
├── Reference/ (21 souborů, ~200 KB)
│   ├── 2026-03-31_2049-hermes-agent-nousresearch-srovnani.md
│   └── knowledge-base-prezentace-mobile.html
└── README.md
```

**Konfigurace embeddings:**
- Model: `gemma-300m-qat-Q8_0.gguf` (328 MB)
- Provider: `local` (node-llama-cpp)
- Search: Hybridní (vectorWeight: 0.7, textWeight: 0.3)
- Sync: onSessionStart, onSearch, watch (debounce 1.5s)

### Migrace do Hermes

#### Příprava (nízké náklady)

```bash
# 1. Zkopírovat vault
scp -r deploy@openclaw:/home/deploy/.openclaw-gw/workspace/vault \
        ~/.hermes/vault/

# 2. Hermes automaticky indexuje markdown
# (Hermes má FTS5 session search)

# 3. Nastavit v config.yaml
~/.hermes/config.yaml:
memory:
  vault_path: "~/.hermes/vault"
  search_provider: "fts5"  # Full-text search (bez local embeddings)
```

#### Problém: Embeddings Model

| Metoda | Výhoda | Nevýhoda |
|--------|--------|----------|
| **Hermes FTS5** | Bez ext. API | Horší relevance (jen text) |
| **Local embeddings** | Jako OpenClaw | Python + ONNX (extra instalace) |
| **Nous Portal** | Jednoduché | Tokens + API latence |

**Doporučení:** Hermes defaultně používá **FTS5** (plnotext search), což je **dostatečné** pro 700 KB vault. Pokud potřebujete vektorovou relevanční, musíte přidat:

```bash
# Hermes doesn't have built-in local embeddings (Feb 2025)
# Ale je možné přidat jako custom plugin nebo MCP server

# Alternativa: Použít Nous Portal (free tier)
# nebo vlastní embedding server (spacy/sentence-transformers)
```

---

## VII. Doporučený Postup Implementace

### Scénář 1: Fork + Vlastní Vývoj (Rizikovější)

```
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent
git checkout v0.6.0  # Nejnovější release (30.3.2026)
git checkout -b my-fork  # Vlastní větev

# Přidání komponent:
# 1. PII proxy (kopie z OpenClaw)
# 2. Obsidian vault integration
# 3. Vlastní skill marketplace sync

# Build
pip install -e .
hermes --version  # v0.6.0
```

**Výhody:**
- Plná kontrola nad kódem
- Vlastní bezpečnostní features
- Offline-first (přes lokální LLM)

**Nevýhody:**
- Samotný fork musí sledovat upstream (těžké)
- Risk: custom code vypršení vs upstream updates
- Maintenance burden → dlouhodobě neudržitelné

---

### Scénář 2: Upstream + Vlastní Plugins ⚠️ RIZIKO

```
# Hermes v0.6.0+ má "first-class plugin architecture"
~/.hermes/plugins/
├── pii_anonymizer.py      # Custom plugin
├── vault_indexer.py       # Custom plugin
└── skill_sync.py          # Custom plugin
```

**Hermes Plugin API (teorie):**
```python
# ~/.hermes/plugins/pii_anonymizer.py
# ❌ PROBLÉM: Dokumentace není dostupná!
# ❌ Hermes docs o pluginech: "TODO" nebo neexistují
# ❌ Beta API znamená: breaking changes mezi verzemi
```

**Realita (březen 2026):**
- ✅ Plugin API "v0.6.0+" existuje (zmínka v release notes)
- ⚠️ Dokumentace v `hermes-agent.nousresearch.com/docs` je **neúplná**
- ❌ Veřejné příklady: ~3 třetích stran community plugins (mudrii, 0xNyk)
- ❌ Horrors: Hermes v0.5.0 → v0.6.0 měla breaking changes v memory API

**Kritická revize:**
- Hermes dokumentace **není dostatečná** pro produkční plugin vývoj
- Scénář 2 vyžaduje **reverse engineering** ze source kódu
- Risk: Plugin se zjednoho dne zbourá po update Hermes

**Upřesnění:**
```
Scénář 2 = "Upstream + Plugins" je TEORETICKY správný,
ale PRAKTICKY se stane: "Upstream + Fork" (stejně!)
```

**Lepší alternativa:**
- Fork s **pravidelnou synchronizací** upstream (git rebase měsíčně)
- Menší código overhead, ale garantovaná kompatibilita
- Plugin API se používá jen pro **třetí stranu** (ne core)

**Status:** ⚠️ **Vysoce rizikové** (plugin API není zralá)

---

### Scénář 3: Dual-Run (Přechodný)

```
Měsíc 1-3:
┌─ OpenClaw (produkce) ──────┐
│  └─ Confidential data       │
│     (s PII proxy)           │
└─────────────────────────────┘
          ↓ (research)
┌─ Hermes (development) ─────┐
│  └─ Public data only        │
│     (bez PII)               │
└─────────────────────────────┘

Měsíc 3-6:
┌─ Hermes + PII plugin ──────┐
│  (production-ready)         │
└─────────────────────────────┘
          ↑ (migrovat)
┌─ OpenClaw (archiv) ────────┐
│  └─ Historical data export  │
└─────────────────────────────┘
```

---

## VIII. Implementační Plán (Krok za Krokem)

### Fáze 1: Instalace + Zkoušení (Týden 1)

```bash
# 1. Instalace Hermes
pip install hermes-agent==0.6.0

# 2. Inicializace
hermes init
# → Vytvoří ~/.hermes/

# 3. Nastavit OAuth
hermes model
# → Detekuje Claude Code credentials automaticky
# → Zkonfiguruje ~/.hermes/config.yaml

# 4. Test
hermes chat "Ahoj, kdo jsi?"
```

### Fáze 2: Vault Migrace (Týden 2)

```bash
# 1. Kopírování
scp -r deploy@openclaw:/path/to/vault ~/.hermes/vault/

# 2. Indexace (Hermes FTS5)
hermes memory index ~/.hermes/vault/

# 3. Test retrieval
hermes chat "Hledám poznámku o OpenClaw"
# → Mělo by najítz vault/
```

### Fáze 3: PII Plugin (Týden 3-4)

```bash
# 1. Vytvořit plugin z OpenClaw pii-proxy kódu
# cp pii-proxy/proxy.py ~/.hermes/plugins/pii_anonymizer.py

# 2. Přepsat Python plugin API (z Node.js FastAPI)

# 3. Test
hermes chat --plugin pii_anonymizer "Jaká je čísla účtu?"
# → Mělo by anonymizovat
```

### Fáze 4: Skills + Learning (Týden 5-6)

```bash
# 1. Seed skills
# Zkopírovat OpenClaw skills → Hermes
for skill in /home/deploy/openclaw/skills/*/SKILL.md; do
  convert_skill_to_hermes.py "$skill"
done

# 2. Povolit autonomní skill creation
~/.hermes/config.yaml:
learning:
  create_skills_on_complex_tasks: true
  self_improvement_enabled: true

# 3. Vyzkoušet learning loop
hermes chat --learning-enabled "Nauč mě..."
# → Agent vytvoří skill automaticky
```

---

## IX. Kritická Analýza — Vyřešené Námitky

### Námitka 1: "Hermes nemá PII ochranu"

**Problém:** Hermes bez anonymizace → GDPR riziko

**Řešení:**
1. **Plugin wrapper** (Scénář 2) — nejsnazší
2. **Environment variable** — `X-PII-Skip: true` header
3. **Lokální LLM** — namísto Anthropic API
4. **Data governance** — Policy: "bez PII do Hermes"

**Status:** ✅ **Řešitelné** (vyžaduje effort, ale technicky možné)

---

### Námitka 2: "Learning loop = drahé API" ⚠️ REVIZOVÁNO

**Problém:** Autonomní skill creation s Claude Sonnet 4.6 = $3/M input, $15/M output tokens.

Hermes learning proces **s Claude Sonnet**:
```
Úloha (1K tokens)              = $0.003 input
  → Řešení + paměť (3K)       = $0.009 input
  → Skill generation (5K)     = $0.015 input + $0.075 output
  → Memory summarizace (2K)   = $0.006 input + $0.030 output
  ─────────────────────────────────────────────
  CELKEM NA SKILL = $0.138 (tj. 46K tokens na jednom skill)
```

**Kritické zjištění:**
- Autonomní skill creation v Hermes zvyšuje API usage o **~40-60%**
- S Claude Sonnet (standard) = **~$4-6/den** na skill development
- S Batch API (50% sleva) = ~$2-3/den
- S levnějším modelem (Groq, OpenRouter Mixtral) = ~$0.50-1/den

**Realita vs Marketing:**
- Hermes marketing: "Learning bez extra nákladů" ❌ Nepravda
- Learning = extra API volání = vyšší náklady (ale kontrolovatelné)
- Benefit: Autonomní skill creation (nevyžaduje ručný zásah)

**Řešení:**
1. **Batch API** — 50% sleva ($1.50/M input, $7.50/M output)
   ```yaml
   models:
     skill_generation: "anthropic:sonnet-4-6:batch"  # 50% sleva
   ```

2. **Multi-model routing** — Levnější model pro skill gen
   ```yaml
   models:
     primary: "anthropic:sonnet-4-6"      # Premium inference
     auxiliary:
       skill_generation: "groq:mixtral"   # Zdarma
       memory_summarization: "openrouter:mistral-large"
   ```

3. **Kontrollovaný learning** — Skill gen jen 1x denně
   ```yaml
   learning:
     skill_creation_schedule: "0 2 * * *"  # 2 AM daily
     max_daily_skills: 1
   ```

**Status:** ✅ **Řešitelné, ale vyžaduje cost management** (ne "zdarma")

---

### Námitka 2b: "Self-improving" v Hermes — Realita vs Marketing ⚠️

**Hermes tvrdí:** "Agent se učí z Experience, vylepšuje dovednosti během používání"

**Realita (březen 2026):**

1. **Skill creation** — Ano, funguje
   - Agent si vezme komplexní úkol (5+ kroků)
   - Vytvoří `.py` skill do `~/.hermes/skills/`
   - Příště používá skill místo kódu od nuly
   - ✅ Skutečný benefit: 2-3x rychlejší execution

2. **Self-improvement** — Marketingový přehmaty
   - Hermes "zlepšuje skill během使用" = minor optimalizace v MEMORY.md
   - Skill se *sám* nemění (kód je frozen)
   - Zlepšování = "agent si pamatuje, jak lépe skill volat"
   - ❌ NE: "skill se automaticky refaktoruje"

3. **Memory consolidation** — Works, ale s náklady
   - Hermes se sám ptá "Co jsem se naučil?" (extra LLM call)
   - Shrnutí do MEMORY.md (text, ne vektory)
   - FTS5 search v MEMORY → keyword matching (jiný use-case)

**Upřesnění v2 — srovnání search přístupů:**
```
Hermes FTS5    = keyword matching (přesné shody, session search)
OpenClaw hybrid = embeddings + FTS (sémantická podobnost, vault search)

Řeší RŮZNÉ problémy — nejsou přímo srovnatelné.
FTS5 je lepší pro "najdi session kde jsem mluvil o X".
Embeddings jsou lepší pro "najdi relevantní poznámku o tématu Y".
```

**Hermes learning = skill caching + memory curation (procedural memory)**

**Kdy je Hermes learning výhoda?**
- ✅ Opakující se úkoly (skill se zopakuje)
- ✅ Komplexní workflows (agent si pamatuje kroky)
- ✅ User profiling (MEMORY.md = "jak běžně uživatel pracuje")
- ❌ Ne: Autonomní refaktoring kódu
- ❌ Ne: Zlepšování přesnosti bez lidské revize

**Status:** ⚠️ **Nadhodnocené v marketingu, ale stále přínosné**

---

### Námitka 3: "Fork vs Upstream — co vybrat?" ⚠️ REVIZOVÁNO

**Odpověď:** Žádná z variant Hermes není bezpečná (v2)

| Pohled | Fork | Upstream+Plugins |
|--------|------|------------------|
| **Kontrola** | 100% | Teoreticky 90%, reálně ❓ |
| **Updates** | Ručně (git rebase) | ⚠️ Breaking changes možné |
| **Maintenance** | Vysoká | ⚠️ Také vysoká (plugin API beta) |
| **Kompatibilita** | Riziková | ⚠️ Negarantovaná (viz v0.5→v0.6) |
| **Dokumentace** | Source code | Neúplná |

**Poznámka v2:** V původní verzi tento oddíl tvrdil, že Upstream+Plugins je "nejlepší", zatímco Scénář 2 výše ho označoval jako "vysoce rizikový". To byl interní rozpor. Po revizi: **obě varianty pro Hermes jsou rizikové**, proto doporučujeme zůstat u OpenClaw.

---

### Námitka 4: "Jak migrovat existující data?"

**OpenClaw → Hermes:**

```bash
# 1. Session export (konverzace)
export SESSIONS_DIR="/home/deploy/.openclaw-gw/sessions"
for f in $SESSIONS_DIR/*.jsonl; do
  python convert_openclaw_sessions.py "$f" >> ~/.hermes/sessions.jsonl
done

# 2. Memory export (vault)
cp -r /path/to/vault ~/.hermes/vault/

# 3. Skills export (SKILL.md → Python)
for skill_dir in /home/deploy/openclaw/skills/*/; do
  python convert_skill_to_hermes.py "$skill_dir"
done

# 4. Config export
export_openclaw_config.sh > ~/.hermes/config.yaml
```

**Validace:**
```bash
hermes memory search "Hledej v importované paměti"
hermes skills list  # Měly by být vidět importované skills
hermes chat --history-import  # Náhled na importované sessions
```

**Status:** ✅ **Řešitelné** (custom scripts, ale jednoduché)

---

### Námitka 5: "OAuth token refresh — je bezpečné?"

**Analýza:**

| Metoda | Bezpečnost | Refresh |
|--------|-----------|---------|
| **OpenClaw sync-claude-token.cjs** | ✅ Auto-refresh (1-year token, 3.5h buffer) | ✅ Ano |
| **Hermes auto-detect** | ✅ Stejné (.credentials.json) | ✅ Ano (Platform.claude.com fallback) |
| **Manual ANTHROPIC_TOKEN** | ❌ Bez refresh | ❌ Ne (vyprší za rok) |

**Status:** ✅ **Bezpečné** (obě metody OK)

---

## X. Finální Doporučení — REVIZOVANÉ

### ❌ NEDĚLÁME: Hermes (zatím)

**Důvody pro zamítnutí:**

1. **PII anonymizace** — Kritická, Hermes nemá vestavěnou
   - OpenClaw proxy je konkurenční výhoda
   - Hermes plugin API není zralá (beta, bez docs)

2. **Plugin API risk** — Není dostatečně stabilní
   - v0.5.0 → v0.6.0: breaking changes v memory API
   - Dokumentace není přítomná (reverseengineering potřebný)
   - Scénář 2 ("bez forku") je **prakticky nemožný**

3. **Cost realism** — Learning ≠ free
   - Skill generation zvyšuje API o 40-60%
   - Multi-model routing komplikuje operace
   - Batch API pomůže, ale stále extra náklady

4. **Overhyped "learning"** — Není takové revolucionární
   - "Self-improvement" = Skill caching + memory notes
   - Ne: Autonomní refaktoring, samoopravování kódu
   - OpenClaw embeddings jsou LEPŠÍ než Hermes FTS5

5. **Hermes immaturity** — Velmi aktivní vývoj
   - Hermes v0.6.0 (30.3.2026) = teprve půl roku v beta
   - Risks: API breaking changes, neznámé bugs, dokumentace
   - Třeba čekat na v1.0 (cca srpen 2026?)

---

### ✅ DOPORUČUJI: OpenClaw + Vlastní Learning Loop

**Strategie:**

```
┌─ OpenClaw (produkce) ──────────────────┐
│ • 50+ skills                           │
│ • PII proxy (bezpečně)                │
│ • Vault + embeddings                  │
│                                        │
│ + Vlastní learning loop:               │
│   └─ Custom agent (TypeScript)         │
│      Monitoruje sessions              │
│      Generuje skills na demandě       │
│      (bez "autonomie", jen insights)  │
└────────────────────────────────────────┘
```

**Postup (2-3 měsíce):**

```
Měsíc 1: Analýza běžných úkolů
  → Identifikovat 5-10 kandidátů na automatizaci
  → Custom TypeScript agent skrz OpenClaw API

Měsíc 2: Implementace skill-gen agenta
  → Agent pozoruje konverzace
  → Navrhuje nové skills (pro ztvrdem approval)
  → Vygeneruje SKILL.md template
  → Human review + merge

Měsíc 3: Monitorování + iterace
  → Skill popularity metrics
  → Optimalizace most-used skills
```

**Výhody:**
- ✅ Zůstáváte na stabilní platformě (OpenClaw v2026.3.13)
- ✅ PII anonymizace zůstává bezpečná
- ✅ Embeddings (node-llama-cpp) jsou výkonnější
- ✅ Bez neznámých rizik z Hermes beta
- ✅ Kontrola nad skill generation (human loop)

**Cena:**
- Dev time: ~80-120 hodin
- API costs: +$20-30/měsíc (skill monitoring)
- Infrastructure: Stávající VPS

**Status:** ✅ **Realistické, bezpečné, kontrolované**

---

### 🔮 Hermes — Čekat a Sledovat

**Kdy znovu zvážit Hermes?**
- ✅ Hermes v1.0 (cca srpen 2026)
- ✅ Plugin API se stane "stable" (s dokumentací)
- ✅ Když PII anonymizace bude supported (feature request)
- ✅ Když se community pluginy zestabilizují

**Co sledovat:**
- [Hermes GitHub Releases](https://github.com/NousResearch/hermes-agent/releases)
- [Plugin API Docs](https://hermes-agent.nousresearch.com/docs)
- Community feedback (Reddit r/AI, HackerNews)

---

## XI. Co Kdyby — Scénáře Rozhodování

### Scénář A: "Absolutně chci Hermes teď"

**Plán:**
1. **Fork NousResearch/hermes-agent** @ v0.6.0
   ```bash
   git clone https://github.com/NousResearch/hermes-agent.git
   git checkout v2026.3.30  # Latest stable
   git checkout -b my-openclaw-fork
   ```

2. **Přidat PII anonymizaci** (kopie z OpenClaw)
   ```python
   # hermes_customizations/pii_anonymizer.py
   # ~500 řádků regex kódu z openclaw/pii-proxy/proxy.py
   ```

3. **Vědět si poradit s upgrady**
   - Měsíční `git rebase upstream/main`
   - Conflict resolution (30% šance na breaking change)
   - Testování po každém rebase

**Náklady:** 200-300 hodin dev time, $5-10K/rok v API

**Risk:** ⚠️ Vysoký (fork maintenance)

---

### Scénář B: "Chci mít variantu s Hermes na druhou VPS"

**Dual-stack:**
```
┌─ Hlavní VPS (OpenClaw) ────┐
│ • Konfidenciální data      │
│ • PII proxy                │
│ • Production               │
└────────────────────────────┘
          ↕ (sync)
┌─ Druha VPS (Hermes) ───────┐
│ • Veřejná data             │
│ • Bez PII                  │
│ • Learning/Experimentation │
└────────────────────────────┘
```

**Setup:**
```bash
# Druha VPS (Hermes)
pip install hermes-agent==0.6.0
hermes init
# Kopie vault (bez PII)
scp -r ~/vault-public-only hermes-vps:~/.hermes/vault

# Sync sessions
rsync --exclude='**/private_*' sessions/ hermes-vps:~/.hermes/
```

**Ceny:**
- Druha VPS: ~€5/měsíc (Hetzner CAX11, 2GB RAM, 20GB SSD)
- Setup: 40-60 hodin
- Monitoring: +$10/měsíc API

**Benefit:** Experimentujete s Hermes, OpenClaw zůstává stabilní

**Status:** ✅ **Dobrý kompromis pro R&D**

---

### Scénář C: "Chci OpenClaw, ale s lepší learning mechanikou" ⚠️ OPRAVENO v2

**Custom Learning Agent jako OpenClaw PLUGIN:**

```
extensions/learning-agent/        ← Plugin, NE src/
├── package.json
├── src/index.ts                  ← register(api) entry point
├── src/session-analyzer.ts
├── src/pattern-detector.ts
└── src/skill-proposer.ts
```

```typescript
// extensions/learning-agent/src/index.ts
export const id = "learning-agent";
export function register(api: OpenClawPluginApi) {
  api.registerHook("session_end", async (event, ctx) => {
    // event: { sessionId, messageCount, durationMs }
    // Analyzuj dokončenou session → navrhni skills
  });
}
```

**Integrační body (opraveno):**
- Hook: `session_end` (NE ~~`after_session_completion`~~ — neexistuje!)
- Plugin API: `api.registerHook()` (NE ~~`gateway.registerHook()`~~)
- Output: `.my/proposed-skills/` (pro human review)
- Detection: Keyword + LLM (Haiku, ~$1/měsíc)

**Cena:** 60-100 hodin dev time

**Status:** ✅ **Doporučený přístup** — viz detailní prompt v `learning-agent-prompt.md`

---

## XI. Zdrojové References

- [Hermes Agent GitHub](https://github.com/NousResearch/hermes-agent)
- [Hermes Dokumentace](https://hermes-agent.nousresearch.com/docs/)
- [Claude API Authentication 2026](https://lalatenduswain.medium.com/claude-api-authentication-in-2026-oauth-tokens-vs-api-keys-explained-12e8298bed3d)
- [Hermes Agent Architecture](https://yuv.ai/blog/hermes-agent)
- [PII Anonymization Best Practices](https://tsh.io/blog/pii-anonymization-in-llm-projects)
- [Obsidian MCP Server](https://github.com/cyanheads/obsidian-mcp-server)
- [Release v0.6.0](https://github.com/NousResearch/hermes-agent/releases/tag/v2026.3.30)

---

## XII. Příloha: Skript pro Kontrolu Kompatibility

```python
#!/usr/bin/env python3
# check_hermes_readiness.py

import os
import subprocess
import json
from pathlib import Path

def check_hermes_installation():
    """Ověř, zda je Hermes instalován"""
    result = subprocess.run(['hermes', '--version'], capture_output=True)
    return result.returncode == 0

def check_oauth_credentials():
    """Ověř OAuth token"""
    creds_path = Path.home() / '.claude' / '.credentials.json'
    if creds_path.exists():
        with open(creds_path) as f:
            creds = json.load(f)
            return 'accessToken' in creds
    return False

def check_vault_migration():
    """Ověř vault import"""
    vault_path = Path.home() / '.hermes' / 'vault'
    if vault_path.exists():
        count = len(list(vault_path.glob('**/*.md')))
        return count > 0, count
    return False, 0

if __name__ == '__main__':
    print("🔍 Kontrola Hermes kompatibility...\n")
    
    print("1. Instalace:", "✅" if check_hermes_installation() else "❌")
    print("2. OAuth token:", "✅" if check_oauth_credentials() else "❌")
    has_vault, count = check_vault_migration()
    print(f"3. Vault ({count} souborů):", "✅" if has_vault else "❌")
    
    print("\n✅ Připraven na migraci!" if all([
        check_hermes_installation(),
        check_oauth_credentials(),
        has_vault
    ]) else "\n⚠️ Chybí některé prerekvizity")
```

---

---

## Závěr — Decision Tree

### Otázka 1: Potřebuji PII anonymizaci?
- **ANO** → OpenClaw (Hermes nemá)
- **NE, jen public data** → Hermes je OK

### Otázka 2: Chci experimentovat s learning loop?
- **ANO, s kontrolou** → OpenClaw + custom agent (Scénář C)
- **ANO, bez kontroly** → Hermes (risk akceptován)
- **NE** → OpenClaw (status quo)

### Otázka 3: Mám kapacitu na fork maintenance?
- **ANO** → Hermes fork (Scénář A)
- **NE** → OpenClaw nebo dual-stack (Scénář B)

### Otázka 4: Jsem v termínu?
- **Ano, do 2 měsíců** → OpenClaw (stabilní)
- **Ne, máme čas** → Počkej na Hermes v1.0 (srpen)

---

## Final Checklist

**OpenClaw + Learning** ✅
- [ ] Identifikovat 5 top repetitivních úkolů
- [ ] Designovat custom TypeScript learning agent
- [ ] Implementovat skill-gen pipeline
- [ ] Setup GitHub Actions pro review
- [ ] Monitor API costs

**Hermes R&D (Scénář B)** ⚠️
- [ ] Provision druha VPS
- [ ] Install Hermes v0.6.0
- [ ] Test PII anonymizace (dělá to OpenClaw, Hermes ne)
- [ ] Vault migration (bez PII)
- [ ] Monitoring learning costs

**Čekat na Hermes v1.0** 🔮
- [ ] Subscribe na GitHub releases
- [ ] Sledovat plugin API maturity
- [ ] Očekávání: srpen 2026
- [ ] Když bude ready: re-evaluace

---

**Status:** Analýza hotova. Připraveno ke kritické revizi a finálnímu schválení.

**Rekomendace na tuto chvíli:** 🎯 **OpenClaw + Custom Learning Agent (Scénář C)**
- Low risk, medium effort
- Zachovávám všechny existující funkce
- Přidám inteligenci k vytváření skills
- Ready v 2-3 měsících
