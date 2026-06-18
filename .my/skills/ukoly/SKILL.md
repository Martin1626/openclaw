---
name: ukoly
description: Správa Martinových úkolů. Použij když Martin říká "přidej úkol", "co mám na seznamu", "splnil jsem", "ukázat úkoly", "udělej z toho úkol", nebo když je potřeba změnit status či prioritu úkolu. Primární úložiště je Notion (MCP server `notion`), fallback je soubor vault/Osobni/ukoly.md.
---

# Úkoly

Primární úložiště: Martinův Notion task list přes MCP server `notion`.
Fallback: `vault/Osobni/ukoly.md` (ve workspace) — použij jen když Notion není dostupný.

## Notion task list — „Nezapomenout"

- MCP server `notion` (`@notionhq/notion-mcp-server`), token je v configu. Pro běžné operace použij Notion MCP nástroje.
- database_id: `319a54ee-bcfd-4b14-83d4-90ccf1a0e764`
- **data_source_id: `1d2dabed-f428-4e28-9c4f-bd9eb4e94857`** ← rodič nově zakládané stránky (nová Notion API zakládá stránky pod `data_source_id`, NE `database_id`)
- Notion-Version: `2026-03-11`

### Vlastnosti (přesné názvy — při překlepu zápis selže)
| Property | Typ | Povolené / formát |
|----------|-----|-------------------|
| `Úkol` | title | text úkolu |
| `Priorita` | select | **`Vysoká` · `Střední` · `Nízká`** |
| `Projekt` | select | **`PlaudSync` · `Alza` · `FHB` · `OpenClaw`** |
| `Termín připomenutí` | date | ISO datum |
| `Hotovo` | checkbox | true/false |
| `Poznámka` | rich_text | volný text |

⚠️ `Priorita` a `Projekt` jsou **select** — používej výhradně hodnoty z tabulky, jinak Notion vrátí chybu. Emoji priority (🔥/⭐/📋) níže platí **jen pro fallback soubor**, ne pro Notion select.

## Operace (primárně přes Notion MCP)

**Přidat úkol:** Zjisti prioritu (Vysoká/Střední/Nízká); pokud není zřejmá, zeptej se. Volitelně Projekt, Termín připomenutí, Poznámka. Založ stránku s rodičem `data_source_id` a title-property `Úkol`. Potvrď: „Přidáno ({Priorita}): {název}". Když Notion není dostupný → ulož do fallback souboru a jasně řekni, že Notion zápis NEproběhl.

**Označit hotové:** Nastav checkbox `Hotovo` = true. (Ve fallbacku změň `[ ]`→`[x]` a přesuň řádek do sekce ✅.)

**Zobrazit seznam:** Dotaz na data source (query), filtruj `Hotovo` = false, řaď podle Priority/Termínu. Vypiš přehledně po sekcích s počty.

**Smazat:** Jen na výslovné přání → `PATCH` stránky s `in_trash: true` (NE „archived"). Hotové úkoly se standardně nemažou (historie).

## Fallback soubor (jen bez Notionu)
Priority: 🔥 Urgentní (dnes/zítra) · ⭐ Důležité (tento týden) · 📋 Běžné (bez termínu) · ✅ Hotové (přesouvat, nemazat).
Formát: `- [ ] Popis úkolu` + volitelně `  > poznámka`. Při změně aktualizuj datum „Poslední aktualizace".

## Pravidla
- Opakující se úkoly → do kalendáře, ne sem.
- Při přidání vždy potvrď uživateli název + zařazení.
