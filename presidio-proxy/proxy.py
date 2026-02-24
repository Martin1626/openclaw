"""
Anthropic API Proxy with PII Anonymization.

Sits between OpenClaw and Anthropic API:
  OpenClaw -> pii-proxy (anonymize) -> Anthropic API
  OpenClaw <- pii-proxy (de-anonymize) <- Anthropic API

All PII detection is local (regex + Czech name knowledge base).
No external NLP services needed.

Supports both streaming (SSE) and non-streaming modes.
"""

import json
import logging
import os
import re
from collections import defaultdict
from typing import AsyncGenerator

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse, StreamingResponse

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ANTHROPIC_API_URL = os.getenv("ANTHROPIC_API_URL", "https://api.anthropic.com")
PII_DEBUG = os.getenv("PII_DEBUG", "false").lower() in ("true", "1", "yes")
ANONYMIZE_SYSTEM = os.getenv("PII_ANONYMIZE_SYSTEM", "false").lower() in ("true", "1", "yes")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
log = logging.getLogger("pii-proxy")

app = FastAPI(title="PII Anonymization Proxy for Anthropic API")

# ---------------------------------------------------------------------------
# Czech name knowledge base for PERSON validation
# ---------------------------------------------------------------------------

# Top ~100 Czech first names (nominative, lowercase)
_CZECH_FIRST_NAMES = frozenset([
    # Male
    "jan", "jiří", "josef", "karel", "pavel", "martin", "petr", "jaroslav",
    "miroslav", "tomáš", "františek", "zdeněk", "václav", "milan", "michal",
    "vladimír", "lukáš", "david", "roman", "jakub", "ondřej", "daniel",
    "filip", "marek", "adam", "aleš", "radek", "vojtěch", "stanislav",
    "ladislav", "rudolf", "antonín", "oldřich", "bohumil", "vlastimil",
    "ivan", "libor", "robert", "richard", "marcel", "dominik", "rené",
    "patrik", "matěj", "štěpán", "viktor", "igor", "erik", "kamil",
    "boris", "robin", "šimon", "kryštof", "matouš", "sebastian", "tadeáš",
    "tobias", "dalibor", "bedřich", "leopold", "vratislav", "bronislav",
    # Female
    "jana", "marie", "eva", "anna", "hana", "lenka", "kateřina", "věra",
    "lucie", "petra", "alena", "jaroslava", "miroslava", "helena", "ludmila",
    "zdeňka", "jiřina", "monika", "marcela", "martina", "tereza", "božena",
    "michaela", "dagmar", "vlasta", "gabriela", "ivana", "veronika",
    "klára", "barbora", "simona", "nicole", "denisa", "andrea", "markéta",
    "eliška", "kristýna", "šárka", "nela", "natálie", "adéla",
    "karolína", "aneta", "renata", "soňa", "olga", "blanka", "růžena",
    # Common international names
    "alexander", "thomas", "michael", "john", "peter", "paul", "james",
    "william", "george", "charles", "henry", "hans", "franz", "heinrich",
])

# Explicit Czech surnames (lowercase nominative) — known contacts & colleagues
_CZECH_SURNAMES = frozenset([
    "aghová", "babisz", "baier", "baierová", "barčiová", "bezděk", "bezecný",
    "bialas", "bilas", "bílek", "brzezinová", "bzonek", "cavalcante", "czopnik",
    "čech", "černý", "dadok", "daňa", "dobruská", "dohňanský", "domanský",
    "dorňák", "drda", "ďuríšek", "fajstaverová", "färber", "feichtinger",
    "gasiorek", "gelnar", "gödrich", "gregor", "gregorčík", "gruška", "günther",
    "gwizdž", "hamala", "hampel", "hampl", "hanke", "hanus", "hanzlová",
    "hodoň", "holáň", "holomek", "holub", "horák", "hořínková", "hradil",
    "hrnčíř", "jakubíček", "jaroš", "jarošová", "jasiok", "jaskevič",
    "jelínek", "jemelka", "ježíková", "josefus", "just", "kaňovská",
    "kašprák", "koczy", "kohut", "kochová", "koláčková", "kořený", "kotlář",
    "kovár", "kovář", "kozáková", "kožušník", "králičková", "krčal", "krčmář",
    "křižáková", "kubala", "kubíčková", "lambor", "langer", "lodňan", "macek",
    "maléřová", "malinkovič", "mališ", "marková", "maschke", "matýsek",
    "melicharová", "micak", "michálek", "miškařík", "mohelník", "možný",
    "muta", "mydlář", "nerud", "nytra", "obluk", "olšar", "ondráček",
    "ondruch", "pelíšek", "peterka", "petříčková", "pindora", "popek",
    "poštulka", "pristaš", "prokop", "prokůpek", "rašková", "rédrová",
    "richtár", "ručka", "řehová", "řepecký", "satke", "selecký", "semerák",
    "skalický", "skalka", "skura", "smetana", "soldán", "soukup", "soukupová",
    "souralová", "sporysz", "staufčík", "stebel", "stempak", "strakoš",
    "stuchlík", "svoboda", "sýkora", "sýkorová", "ševčíková", "šidlík",
    "šimeček", "šimek", "šimková", "škrobánek", "šmíd", "šmiga", "šotková",
    "špok", "štěpánek", "šulcová", "švejnoha", "tesarčík", "tichý", "tobiáš",
    "tomis", "ulčáková", "vaněček", "vaněk", "veličková", "vidlář", "vzorek",
    "walach", "wilczek", "wrona", "zetocha", "židková", "bočková", "hamplová",
])

# Common Czech surname suffixes (helps identify name-like words)
_CZECH_SURNAME_SUFFIXES = (
    "ová", "ový", "ský", "ská", "cký", "cká",
    "ník", "ček", "šek", "nek", "lík", "řík",
    "ák", "ář", "áč", "ůrek",
)

# Expanded deny list — common Czech words falsely detected as PERSON
_CZ_DENY_WORDS = frozenset(
    w.lower()
    for w in [
        # Greetings / common phrases
        "dobrý", "dobry", "den", "jsem", "jsi", "není", "neni", "máte", "mate",
        "prosím", "prosim", "děkuji", "dekuji", "ahoj", "hezký", "hezky",
        "potvrzuji", "omlouvám", "omlouvam", "díky", "diky", "zdravím",
        # Titles / honorifics
        "pan", "paní", "pani", "slečna", "slecna", "ing", "mgr", "mudr", "judr",
        # Document / business terms
        "rodné", "rodne", "číslo", "cislo", "telefon", "adresa", "email",
        "schůzka", "schuzka", "firma", "společnost", "spolecnost",
        "faktura", "smlouva", "objednávka", "projekt", "systém", "služba",
        # Technical terms (often capitalized in headers)
        "bezpečnostní", "síťová", "architektura", "konfigurace", "instalace",
        "databáze", "aplikace", "prostředí", "správa", "nastavení",
        "infrastruktura", "autentizace", "autorizace", "monitoring",
        "docker", "compose", "container", "server", "deploy", "build",
        "gateway", "proxy", "webhook", "endpoint", "plugin", "service",
        # Common Czech nouns/adjectives (often in headers)
        "první", "druhý", "třetí", "nový", "nová", "hlavní", "základní",
        "veřejný", "veřejná", "osobní", "pracovní", "národní", "český",
        "česká", "centrální", "obecní", "městský", "městská", "krajský",
        "úvodní", "závěrečný", "celkový", "celková", "aktuální",
        # Months / time
        "leden", "únor", "březen", "duben", "květen", "červen",
        "červenec", "srpen", "září", "říjen", "listopad", "prosinec",
        "pondělí", "úterý", "středa", "čtvrtek", "pátek", "sobota", "neděle",
        # Locations (not people)
        "praha", "brno", "ostrava", "plzeň", "liberec", "olomouc",
        "české", "budějovice", "hradec", "králové", "zlín", "pardubice",
        # Common Czech words that are also surnames — avoid standalone match
        "čech", "černý", "svoboda", "smetana", "holub", "tichý", "možný",
        "jelínek", "macek", "kořený", "kovář", "kovár",
    ]
)


def _has_czech_name_signal(span: str) -> bool:
    """Check if a detected PERSON span has signals of being an actual Czech name.

    Handles Czech inflection: checks not just nominative forms but also
    common case suffixes (Jana/Janem/Janovi from Jan, Nováka/Novákem from Novák).
    """
    words = [w for w in span.strip().split() if len(w) > 1]
    if not words:
        return False

    for w in words:
        wl = w.lower()
        # Direct first name match (nominative)
        if wl in _CZECH_FIRST_NAMES:
            return True
        # Direct surname match (nominative)
        if wl in _CZECH_SURNAMES:
            return True
        # Stem match for first names: strip common Czech case endings
        # This handles: Janem→Jan, Jana→Jan, Janovi→Jan, Martinem→Martin, etc.
        for suffix in ("em", "ovi", "ově", "ou", "u", "a", "y", "e", "i"):
            stem = wl.removesuffix(suffix)
            if len(stem) >= 3 and stem in _CZECH_FIRST_NAMES:
                return True
        # Stem match for explicit surnames: strip case endings
        # This handles: Tomise→Tomis, Svobodou→Svoboda, Prokopa→Prokop, etc.
        for suffix in ("em", "ovi", "ově", "ou", "u", "a", "y", "e", "i", "ů", "ům"):
            stem = wl.removesuffix(suffix)
            if len(stem) >= 3 and stem in _CZECH_SURNAMES:
                return True
            # -a/-y alternation: Peterka→Peterky (genitive), stem "peterk" + "a" = "peterka"
            if suffix in ("y", "e", "u", "i", "ou") and len(stem) >= 3:
                if (stem + "a") in _CZECH_SURNAMES or (stem + "o") in _CZECH_SURNAMES:
                    return True
        # Czech surname suffix match (word must be capitalized and 4+ chars)
        if w[0].isupper() and len(w) >= 4:
            if any(wl.endswith(sfx) for sfx in _CZECH_SURNAME_SUFFIXES):
                return True
            # Also check inflected surname forms:
            # Novák→Nováka/Novákem/Novákovi, Dvořák→Dvořáka, etc.
            if any(wl.endswith(sfx) for sfx in (
                "áka", "ákem", "ákovi", "ákům",  # -ák declension
                "íka", "íkem", "íkovi",  # -ík declension
                "ovou", "ové", "ovém",  # -ová declension
                "ského", "skému", "ském",  # -ský declension
                "ckého", "ckému",  # -cký declension
                "kem", "kovi", "kům",  # general -ek declension
            )):
                return True

    return False


# ---------------------------------------------------------------------------
# PII regex patterns
# ---------------------------------------------------------------------------

# Czech-specific
_CZECH_PHONE = re.compile(r"(?:\+420[\s-]?\d{3}[\s-]?\d{3}[\s-]?\d{3})")
_CZECH_BIRTH_NUMBER = re.compile(r"\b(\d{6})/(\d{3,4})\b")
_CZECH_PSC = re.compile(r"\b(\d{3})\s(\d{2})\b")
_CZECH_ICO = re.compile(r"\bIČO?\s*:?\s*(\d{8})\b", re.IGNORECASE)
_CZECH_DIC = re.compile(r"\bDIČ\s*:?\s*(CZ\d{8,10})\b", re.IGNORECASE)

# Full Czech address: [optional prefix] [street name] [house number], [PSČ] [city]
_CZECH_ADDRESS = re.compile(
    r"(?:ul\.\s*|nám\.\s*|tř\.\s*|náměstí\s+|ulice\s+|třída\s+)?"
    r"(?:(?:na|pod|nad|u|v|ve|za|před|při|ke|k)\s+)?"
    r"[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽÜÖÄŁŚŹŻĆŃ][a-záčďéěíňóřšťúůýžüöäßłśźżćń]+"
    r"(?:\s+[a-záčďéěíňóřšťúůýžA-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]+){0,2}"
    r"\s+\d+(?:/\d+)?[a-z]?"
    r"\s*,\s*"
    r"\d{3}\s?\d{2}"
    r"\s+[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽÜÖÄŁŚŹŻĆŃ][a-záčďéěíňóřšťúůýžüöäßłśźżćń]+(?:\s+\d+)?",
    re.UNICODE,
)

# Universal patterns (previously handled by Presidio)
_EMAIL = re.compile(r"\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b")
_IBAN = re.compile(r"\b[A-Z]{2}\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{4}(?:\s?\d{4})?(?:\s?\d{2})?\b")
_CREDIT_CARD = re.compile(r"\b(?:\d{4}[\s-]?){3}\d{4}\b")

# PERSON candidates: sequences of 2+ capitalized words (Latin script)
_PERSON_CANDIDATE = re.compile(
    r"\b([A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽÜÖÄŁŚŹŻĆŃ][a-záčďéěíňóřšťúůýžüöäßłśźżćń]+"
    r"(?:\s+[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽÜÖÄŁŚŹŻĆŃ][a-záčďéěíňóřšťúůýžüöäßłśźżćń]+)+)\b",
    re.UNICODE,
)

# Single capitalized word (for standalone known-surname detection)
_SINGLE_CAP_WORD = re.compile(
    r"\b([A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽÜÖÄŁŚŹŻĆŃ][a-záčďéěíňóřšťúůýžüöäßłśźżćń]{2,})\b",
    re.UNICODE,
)


def _luhn_check(number: str) -> bool:
    """Validate a credit card number using the Luhn algorithm."""
    digits = [int(d) for d in number if d.isdigit()]
    if len(digits) < 13 or len(digits) > 19:
        return False
    checksum = 0
    for i, d in enumerate(reversed(digits)):
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        checksum += d
    return checksum % 10 == 0


# ---------------------------------------------------------------------------
# PII detection (all local, no external services)
# ---------------------------------------------------------------------------

def detect_pii(text: str) -> list[dict]:
    """Detect PII entities using regex + Czech name knowledge base."""
    if not text or not text.strip():
        return []

    entities: list[dict] = []

    # --- Czech-specific ---
    for m in _CZECH_PHONE.finditer(text):
        entities.append({"entity_type": "PHONE_NUMBER", "start": m.start(), "end": m.end(), "score": 0.95})
    for m in _CZECH_BIRTH_NUMBER.finditer(text):
        entities.append({"entity_type": "CZECH_BIRTH_NUMBER", "start": m.start(), "end": m.end(), "score": 0.95})
    for m in _CZECH_PSC.finditer(text):
        entities.append({"entity_type": "CZECH_PSC", "start": m.start(), "end": m.end(), "score": 0.80})
    for m in _CZECH_ICO.finditer(text):
        entities.append({"entity_type": "CZECH_ICO", "start": m.start(1), "end": m.end(1), "score": 0.90})
    for m in _CZECH_DIC.finditer(text):
        entities.append({"entity_type": "CZECH_DIC", "start": m.start(1), "end": m.end(1), "score": 0.95})
    for m in _CZECH_ADDRESS.finditer(text):
        entities.append({"entity_type": "CZECH_ADDRESS", "start": m.start(), "end": m.end(), "score": 0.95})

    # --- Universal ---
    for m in _EMAIL.finditer(text):
        entities.append({"entity_type": "EMAIL_ADDRESS", "start": m.start(), "end": m.end(), "score": 1.0})
    for m in _IBAN.finditer(text):
        entities.append({"entity_type": "IBAN_CODE", "start": m.start(), "end": m.end(), "score": 0.95})
    for m in _CREDIT_CARD.finditer(text):
        num = m.group()
        if _luhn_check(num):
            entities.append({"entity_type": "CREDIT_CARD", "start": m.start(), "end": m.end(), "score": 0.95})

    # --- PERSON detection: capitalized word sequences validated by Czech name DB ---
    for m in _PERSON_CANDIDATE.finditer(text):
        span = m.group()
        # Technical character check
        if any(c in span for c in "./-_@#[]{}()=<>"):
            continue
        words = [w for w in span.split() if len(w) > 1]
        # Strip deny-list words
        name_words = [w for w in words if w.lower() not in _CZ_DENY_WORDS]
        if not name_words:
            continue
        if not any(w[0].isupper() for w in name_words):
            continue
        # Require Czech name signal
        if not _has_czech_name_signal(span):
            if PII_DEBUG:
                log.info("  [PERSON REJECTED] no Czech name signal: %r", span)
            continue
        entities.append({"entity_type": "PERSON", "start": m.start(), "end": m.end(), "score": 0.85})

    # --- Standalone known-surname detection ---
    # Catches single-word references like "Babisz", "Tomise", "Drda"
    for m in _SINGLE_CAP_WORD.finditer(text):
        start, end = m.start(), m.end()
        # Skip if already covered by a previously detected entity
        if any(e["start"] <= start and e["end"] >= end for e in entities):
            continue
        word = m.group()
        wl = word.lower()
        if wl in _CZ_DENY_WORDS:
            continue
        # Direct match
        if wl in _CZECH_SURNAMES:
            entities.append({"entity_type": "PERSON", "start": start, "end": end, "score": 0.75})
            continue
        # Stem match for inflected forms (Tomise→Tomis, Babiszem→Babisz, etc.)
        matched = False
        for suffix in ("em", "ovi", "ově", "ou", "u", "a", "y", "e", "i", "ů", "ům"):
            stem = wl.removesuffix(suffix)
            if len(stem) >= 3 and stem in _CZECH_SURNAMES:
                matched = True
                break
            # -a/-y alternation: Peterka→Peterky, stem "peterk" + "a"
            if suffix in ("y", "e", "u", "i", "ou") and len(stem) >= 3:
                if (stem + "a") in _CZECH_SURNAMES or (stem + "o") in _CZECH_SURNAMES:
                    matched = True
                    break
        if matched:
            entities.append({"entity_type": "PERSON", "start": start, "end": end, "score": 0.75})

    return _remove_overlaps(entities)


def _remove_overlaps(entities: list[dict]) -> list[dict]:
    """Remove overlapping entities, keeping higher-scoring ones."""
    if not entities:
        return []
    sorted_ents = sorted(entities, key=lambda e: (-e["score"], e["start"]))
    kept = []
    for ent in sorted_ents:
        overlaps = any(
            not (ent["end"] <= k["start"] or ent["start"] >= k["end"])
            for k in kept
        )
        if not overlaps:
            kept.append(ent)
    return kept


# ---------------------------------------------------------------------------
# Anonymization / De-anonymization
# ---------------------------------------------------------------------------

def build_anonymization(
    text: str, entities: list[dict]
) -> tuple[str, dict[str, str]]:
    """
    Replace detected PII with numbered placeholders.
    Returns (anonymized_text, {placeholder: original}).
    """
    if not entities:
        return text, {}

    sorted_ents = sorted(entities, key=lambda e: e["start"], reverse=True)
    mapping: dict[str, str] = {}
    value_to_ph: dict[str, str] = {}
    counters: dict[str, int] = defaultdict(int)

    for ent in sorted_ents:
        original = text[ent["start"] : ent["end"]]
        etype = ent["entity_type"]

        if original in value_to_ph:
            ph = value_to_ph[original]
        else:
            counters[etype] += 1
            ph = f"<{etype}_{counters[etype]}>"
            mapping[ph] = original
            value_to_ph[original] = ph

        text = text[: ent["start"]] + ph + text[ent["end"] :]

    return text, mapping


def deanonymize_text(text: str, mapping: dict[str, str]) -> str:
    """Simple string replacement of placeholders -> originals."""
    for ph, original in mapping.items():
        text = text.replace(ph, original)
    return text


def anonymize_text(text: str) -> tuple[str, dict[str, str]]:
    """Full pipeline: detect PII then anonymize."""
    entities = detect_pii(text)
    return build_anonymization(text, entities)


# ---------------------------------------------------------------------------
# Anthropic message processing
# ---------------------------------------------------------------------------

def anonymize_system(system):
    """Anonymize the system prompt (string or block array)."""
    if system is None or not ANONYMIZE_SYSTEM:
        return system, {}
    if isinstance(system, str):
        return anonymize_text(system)
    if isinstance(system, list):
        combined: dict[str, str] = {}
        result = []
        for item in system:
            if isinstance(item, dict) and item.get("type") == "text" and "text" in item:
                anon, m = anonymize_text(item["text"])
                combined.update(m)
                result.append({**item, "text": anon})
            else:
                result.append(item)
        return result, combined
    return system, {}


def anonymize_messages(messages: list[dict]):
    """Anonymize all text content in the messages array."""
    combined: dict[str, str] = {}
    out = []

    for msg in messages:
        mc = dict(msg)
        content = mc.get("content")
        if content is None:
            out.append(mc)
            continue

        if isinstance(content, str):
            anon, m = anonymize_text(content)
            combined.update(m)
            mc["content"] = anon
        elif isinstance(content, list):
            new_content = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text" and "text" in item:
                    anon, m = anonymize_text(item["text"])
                    combined.update(m)
                    new_content.append({**item, "text": anon})
                else:
                    new_content.append(item)
            mc["content"] = new_content

        out.append(mc)

    return out, combined


# ---------------------------------------------------------------------------
# Streaming de-anonymizer
# ---------------------------------------------------------------------------

_PARTIAL_PH = re.compile(r"<[A-Z_0-9]*$")


class StreamDeanonymizer:
    """Processes streaming text chunks, de-anonymizing placeholders."""

    def __init__(self, mapping: dict[str, str]):
        self.mapping = mapping
        self._buf = ""

    def process(self, text: str) -> str:
        self._buf += text
        m = _PARTIAL_PH.search(self._buf)
        if m:
            safe = self._buf[: m.start()]
            self._buf = self._buf[m.start() :]
        else:
            safe = self._buf
            self._buf = ""
        return deanonymize_text(safe, self.mapping)

    def flush(self) -> str:
        out = deanonymize_text(self._buf, self.mapping)
        self._buf = ""
        return out


# ---------------------------------------------------------------------------
# SSE streaming proxy
# ---------------------------------------------------------------------------

async def _stream_proxy(
    resp: httpx.Response,
    mapping: dict[str, str],
    client: httpx.AsyncClient,
) -> AsyncGenerator[bytes, None]:
    """Read Anthropic SSE stream, de-anonymize text deltas, re-emit."""
    deanon = StreamDeanonymizer(mapping) if mapping else None
    pending_event: str | None = None

    try:
        async for raw_line in resp.aiter_lines():
            if not raw_line:
                if pending_event is None:
                    yield b"\n"
                continue

            if raw_line.startswith("event:"):
                pending_event = raw_line
                continue

            if not raw_line.startswith("data:"):
                if pending_event:
                    yield (pending_event + "\n").encode()
                    pending_event = None
                yield (raw_line + "\n").encode()
                continue

            data_str = raw_line[5:].strip()

            if not deanon:
                if pending_event:
                    yield (pending_event + "\n").encode()
                    pending_event = None
                yield f"data: {data_str}\n\n".encode()
                continue

            try:
                data = json.loads(data_str)
            except json.JSONDecodeError:
                if pending_event:
                    yield (pending_event + "\n").encode()
                    pending_event = None
                yield f"data: {data_str}\n\n".encode()
                continue

            evt_type = data.get("type")

            if evt_type == "content_block_delta":
                delta = data.get("delta", {})
                if delta.get("type") == "text_delta":
                    text = delta.get("text", "")
                    processed = deanon.process(text)
                    if processed:
                        out = {**data, "delta": {**delta, "text": processed}}
                        if pending_event:
                            yield (pending_event + "\n").encode()
                            pending_event = None
                        yield f"data: {json.dumps(out, ensure_ascii=False)}\n\n".encode()
                    else:
                        pending_event = None
                    continue

            if evt_type == "content_block_stop":
                remaining = deanon.flush()
                if remaining:
                    idx = data.get("index", 0)
                    flush_evt = {
                        "type": "content_block_delta",
                        "index": idx,
                        "delta": {"type": "text_delta", "text": remaining},
                    }
                    yield f"event: content_block_delta\ndata: {json.dumps(flush_evt, ensure_ascii=False)}\n\n".encode()

            if pending_event:
                yield (pending_event + "\n").encode()
                pending_event = None
            yield f"data: {data_str}\n\n".encode()

    finally:
        await resp.aclose()
        await client.aclose()


# ---------------------------------------------------------------------------
# /noanon marker detection
# ---------------------------------------------------------------------------

_NOANON_PATTERN = re.compile(r"^/noanon\b[^\S\n]*", re.IGNORECASE | re.MULTILINE)


def _check_and_strip_noanon(body: dict) -> bool:
    """Check if the last user message contains /noanon marker.

    If found, strip the marker from the message and return True.
    The gateway wraps user text in metadata, so /noanon may appear
    at the start of any line, not just the start of the string.
    """
    messages = body.get("messages")
    if not messages:
        return False

    # Find last user message
    for msg in reversed(messages):
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            if _NOANON_PATTERN.search(content):
                msg["content"] = _NOANON_PATTERN.sub("", content)
                return True
        elif isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text" and "text" in item:
                    if _NOANON_PATTERN.search(item["text"]):
                        item["text"] = _NOANON_PATTERN.sub("", item["text"])
                        return True
        break  # only check the last user message

    return False


# ---------------------------------------------------------------------------
# Main proxy endpoint
# ---------------------------------------------------------------------------

FORWARD_HEADERS = frozenset(["x-api-key", "authorization", "anthropic-version", "anthropic-beta"])


@app.post("/v1/messages")
async def proxy_messages(request: Request):
    """Proxy Anthropic Messages API with PII anonymization."""

    body = await request.json()
    raw_hdrs = {k.lower(): v for k, v in request.headers.items()}

    fwd = {"content-type": "application/json"}
    for h in FORWARD_HEADERS:
        if h in raw_hdrs:
            fwd[h] = raw_hdrs[h]

    skip_pii = raw_hdrs.get("x-pii-skip", "").lower() in ("true", "1", "yes")

    # Check for /noanon marker in last user message
    if not skip_pii and _check_and_strip_noanon(body):
        skip_pii = True
        log.info("PII anonymization skipped (/noanon marker in user message)")
    is_stream = body.get("stream", False)

    client = httpx.AsyncClient(timeout=httpx.Timeout(300.0, connect=10.0))

    try:
        if skip_pii:
            log.info("PII anonymization skipped (X-PII-Skip header)")
            mapping = {}
            anon_body = body
        else:
            anon_sys, sys_map = anonymize_system(body.get("system"))
            anon_msgs, msg_map = anonymize_messages(body.get("messages", []))
            mapping = {**sys_map, **msg_map}

            if mapping:
                log.info("Anonymized %d PII entities: %s", len(mapping), list(mapping.keys()))
                if PII_DEBUG:
                    log.info("=== PII DEBUG: Mapping ===")
                    for ph, orig in mapping.items():
                        log.info("  %s -> %s", ph, repr(orig))
                    for msg in body.get("messages", [])[-2:]:
                        role = msg.get("role", "?")
                        content = msg.get("content", "")
                        if isinstance(content, str):
                            log.info("  [ORIGINAL %s] %.200s", role, content)
                    for msg in anon_msgs[-2:]:
                        role = msg.get("role", "?")
                        content = msg.get("content", "")
                        if isinstance(content, str):
                            log.info("  [ANONYMIZED %s] %.200s", role, content)
                    log.info("=== END PII DEBUG ===")

            anon_body = {**body, "messages": anon_msgs}
            if anon_sys is not None:
                anon_body["system"] = anon_sys

        target = f"{ANTHROPIC_API_URL}/v1/messages"

        if is_stream:
            req = client.build_request("POST", target, json=anon_body, headers=fwd)
            resp = await client.send(req, stream=True)

            if resp.status_code != 200:
                err_body = await resp.aread()
                await resp.aclose()
                await client.aclose()
                return Response(content=err_body, status_code=resp.status_code, media_type="application/json")

            return StreamingResponse(
                _stream_proxy(resp, mapping, client),
                status_code=200,
                media_type="text/event-stream",
                headers={"cache-control": "no-cache", "x-accel-buffering": "no"},
            )

        resp = await client.post(target, json=anon_body, headers=fwd, timeout=120.0)
        await client.aclose()

        if resp.status_code != 200:
            return Response(content=resp.content, status_code=resp.status_code, media_type="application/json")

        resp_data = resp.json()

        if mapping and "content" in resp_data:
            for block in resp_data["content"]:
                if block.get("type") == "text" and "text" in block:
                    if PII_DEBUG:
                        log.info("  [LLM RESPONSE] %.300s", block["text"])
                    block["text"] = deanonymize_text(block["text"], mapping)
                    if PII_DEBUG:
                        log.info("  [DE-ANONYMIZED] %.300s", block["text"])

        return JSONResponse(content=resp_data)

    except Exception as e:
        await client.aclose()
        log.error("Proxy error: %s", e, exc_info=True)
        return JSONResponse({"error": {"type": "proxy_error", "message": str(e)}}, status_code=502)


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok"}
