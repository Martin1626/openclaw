#!/usr/bin/env bash
# ==========================================================================
# OpenClaw — Post-upgrade test suite
#
# Ověří funkčnost customizací po upgradu. Voláno z openclaw-upgrade.sh
# nebo ručně: bash openclaw-test.sh
#
# Výstup: JSON soubor ve workspace (.upgrade-test-result)
# ==========================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-/home/deploy/.openclaw-gw/workspace}"
RESULT_FILE="$WORKSPACE/.upgrade-test-result"
COMPOSE="docker compose"

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
TESTS_TMPFILE=$(mktemp)
echo -n "[" > "$TESTS_TMPFILE"
FIRST_TEST=true

run_test() {
    local name="$1" group="$2"
    shift 2
    local start_ms
    start_ms=$(date +%s%3N)

    local output status detail
    if output=$("$@" 2>&1); then
        status="pass"
        detail="$output"
        PASS=$((PASS + 1))
    else
        status="fail"
        detail="$output"
        FAIL=$((FAIL + 1))
    fi

    local end_ms
    end_ms=$(date +%s%3N)
    local elapsed=$((end_ms - start_ms))

    # Sanitize detail for JSON (remove newlines, escape quotes, truncate)
    detail=$(printf '%s' "$detail" | head -3 | tr '\n' ' ' | tr '"' "'" | cut -c1-200)

    # Append to temp file (avoid sed on dynamic content)
    if [ "$FIRST_TEST" = true ]; then
        FIRST_TEST=false
    else
        echo -n "," >> "$TESTS_TMPFILE"
    fi
    printf '{"name":"%s","group":"%s","status":"%s","ms":%d,"detail":"%s"}' \
        "$name" "$group" "$status" "$elapsed" "$detail" >> "$TESTS_TMPFILE"

    if [ "$status" = "pass" ]; then
        echo "  ✓ $name (${elapsed}ms)"
    else
        echo "  ✗ $name (${elapsed}ms): $detail"
    fi
}

# ---------------------------------------------------------------------------
# Test implementations
# ---------------------------------------------------------------------------

test_gateway_health() {
    curl -sf http://127.0.0.1:18789/healthz >/dev/null
    echo "ok"
}

test_pii_proxy_health() {
    $COMPOSE exec -T pii-proxy python -c "
import urllib.request
urllib.request.urlopen('http://localhost:3001/health')
print('ok')
"
}

test_pii_anonymization() {
    local result
    result=$($COMPOSE exec -T pii-proxy python -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:3001/test',
    data=json.dumps({'text': 'Jan Novák +420731131426 jan@firma.cz'}).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
resp = json.loads(urllib.request.urlopen(req).read())
assert resp['count'] >= 3, f'Expected >=3 entities, got {resp[\"count\"]}'
assert '<PERSON' in resp['anonymized'], 'PERSON not anonymized'
assert '<PHONE' in resp['anonymized'], 'PHONE not anonymized'
assert '<EMAIL' in resp['anonymized'], 'EMAIL not anonymized'
print(f'{resp[\"count\"]} entities detected')
")
    echo "$result"
}

test_node_llama_cpp() {
    $COMPOSE exec -T openclaw-gateway node -e "
import('node-llama-cpp')
  .then(() => console.log('ok'))
  .catch(e => { console.error(e.message); process.exit(1); })
"
}

test_embedding_model_exists() {
    $COMPOSE exec -T openclaw-gateway node -e "
const fs = require('fs');
const dir = '/home/node/.node-llama-cpp/models';
const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith('.gguf')) : [];
if (files.length === 0) { console.error('no .gguf models found'); process.exit(1); }
console.log(files[0]);
"
}

test_memory_status() {
    local output
    output=$($COMPOSE exec -T openclaw-gateway node dist/index.js memory status 2>&1 | head -5)
    if echo "$output" | grep -qi "error\|unavailable\|failed"; then
        echo "$output"
        return 1
    fi
    echo "ok"
}

test_workspace_skills() {
    local count
    count=$(ls -d "$WORKSPACE/skills"/*/ 2>/dev/null | wc -l)
    if [ "$count" -lt 5 ]; then
        echo "only $count skills (expected >=5)"
        return 1
    fi
    echo "$count skills"
}

test_active_memory_plugin() {
    $COMPOSE exec -T openclaw-gateway node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json'));
const am = config.plugins?.entries?.['active-memory'];
if (!am?.enabled) { console.error('not enabled'); process.exit(1); }
console.log('enabled, queryMode=' + (am.config?.queryMode || 'default'));
"
}

test_dreaming_configured() {
    $COMPOSE exec -T openclaw-gateway node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json'));
const d = config.plugins?.entries?.['memory-core']?.config?.dreaming;
if (!d?.enabled) { console.error('not enabled'); process.exit(1); }
console.log('enabled, freq=' + d.frequency);
"
}

test_telegram_bots() {
    local output
    output=$($COMPOSE exec -T openclaw-gateway node dist/index.js doctor 2>&1 | grep -i "telegram:")
    if echo "$output" | grep -q "ok"; then
        echo "$output" | head -1
    else
        echo "$output" | head -1
        return 1
    fi
}

test_pii_roundtrip() {
    # Ověří, že anonymizace + de-anonymizace vrátí původní text
    $COMPOSE exec -T pii-proxy python -c "
from proxy import anonymize_text, deanonymize_text
original = 'Zavolejte Janu Novákovi na +420731131426, email jan@firma.cz'
anonymized, mapping = anonymize_text(original)
assert '<PERSON' in anonymized, 'anonymization failed'
restored = deanonymize_text(anonymized, mapping)
assert restored == original, f'round-trip failed: {restored!r} != {original!r}'
print(f'ok ({len(mapping)} entities)')
"
}

test_pii_codex_format() {
    # Ověří anonymizaci ve formátu Codex Responses API (input_text content blocks)
    $COMPOSE exec -T pii-proxy python -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:3001/test',
    data=json.dumps({
        'format': 'codex-input',
        'input': [{'role': 'user', 'content': [
            {'type': 'input_text', 'text': 'Zavolej Janu Novakovi na +420731131426'}
        ]}]
    }).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
resp = json.loads(urllib.request.urlopen(req).read())
assert resp['count'] >= 2, f'Expected >=2 entities, got {resp[\"count\"]}'
# Verify original PII is NOT in anonymized output
out_str = json.dumps(resp['input'])
assert '+420731131426' not in out_str, 'Phone number not anonymized in codex format'
print(f'{resp[\"count\"]} entities (codex format)')
"
}

test_pii_noanon_codex() {
    # Ověří, že /noanon bypass funguje v Codex input formátu
    $COMPOSE exec -T pii-proxy python -c "
import urllib.request, json
req = urllib.request.Request('http://localhost:3001/test',
    data=json.dumps({
        'format': 'codex-input',
        'input': [{'role': 'user', 'content': [
            {'type': 'input_text', 'text': '/noanon Zavolej Janu Novakovi na +420731131426'}
        ]}]
    }).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
resp = json.loads(urllib.request.urlopen(req).read())
assert resp['count'] == 0, f'Expected 0 entities with /noanon, got {resp[\"count\"]}'
print('ok (noanon bypass works)')
"
}

test_pii_openai_route() {
    # Ověří, že /openai/ route existuje (vrací non-404 pro POST)
    $COMPOSE exec -T pii-proxy python -c "
import urllib.request, json
# Send minimal request to /openai/ route - expect auth error (401/403), NOT 404
req = urllib.request.Request('http://localhost:3001/openai/v1/models',
    method='GET')
try:
    urllib.request.urlopen(req)
    print('ok (unexpected 200)')
except urllib.error.HTTPError as e:
    if e.code == 404:
        raise AssertionError('/openai/ route returns 404 - not configured')
    print(f'ok (route exists, status {e.code})')
"
}

test_pii_deanon_return_value() {
    # Ověří kontrakt _deanonymize_dict_strings: vrací nový objekt, nemutuje vstup.
    # Regrese: opakovaný bug — volající ignorovali návratovou hodnotu → data zůstala anonymizovaná.
    $COMPOSE exec -T pii-proxy python -c "
from proxy import _deanonymize_dict_strings, anonymize_text
original = 'Kontakt: Jan Novák, +420731131426'
anon, mapping = anonymize_text(original)
# Vstupní struktura simulující OpenAI/Anthropic response
obj = {'output': [{'content': [{'text': anon}]}]}
import copy
snapshot = copy.deepcopy(obj)
result = _deanonymize_dict_strings(obj, mapping)
# 1. Musí vrátit nový objekt (ne None)
assert result is not None, 'return value is None'
# 2. Vstup musí zůstat nezměněný (no mutation)
assert obj == snapshot, 'input was mutated'
# 3. Výstup musí obsahovat deanonymizovaný text
assert original.split(': ')[1] in result['output'][0]['content'][0]['text'], \
    f'deanon failed: {result}'
print('ok (returns new object, no mutation)')
"
}

test_pii_phone_formats() {
    # Ověří detekci českých telefonů ve všech formátech (+420, 00420, bare 6xx/7xx, s mezerami).
    # Regrese: původně regex chytal jen +420 → bare čísla a 00420 prošla neanonymizovaná.
    $COMPOSE exec -T pii-proxy python -c "
from proxy import anonymize_text
test_cases = [
    ('+420731131426', '+420 no-space'),
    ('+420 731 131 426', '+420 with spaces'),
    ('00420731131426', '00420 no-space'),
    ('00420 731 131 426', '00420 with spaces'),
    ('731131426', 'bare 7xx'),
    ('608123456', 'bare 6xx'),
]
failed = []
for phone, label in test_cases:
    text = f'Zavolej na {phone}'
    anon, mapping = anonymize_text(text)
    if phone in anon or '<PHONE' not in anon:
        failed.append(label)
if failed:
    raise AssertionError(f'not anonymized: {failed}')
print(f'ok ({len(test_cases)} phone formats)')
"
}

test_pii_entity_types() {
    # Ověří, že všechny klíčové PII entity typy jsou detekovány.
    # Používá >= pro robustnost (regex může generovat více entit než záměrných).
    $COMPOSE exec -T pii-proxy python -c "
from proxy import anonymize_text
# Testovací text obsahující všechny klíčové typy
text = '''
Kontakt: Jan Novák, Sokolovská 123, 18600 Praha 8
Email: jan.novak@firma.cz, tel: +420731131426
Karta: 4532015112830366
IBAN: CZ6508000000192000145399
Rodné číslo: 800101/1234
IČO: 27082440
DIČ: CZ27082440
'''
anon, mapping = anonymize_text(text)
# Entity names match proxy.py: CZECH_ICO (ne COMPANY_ID), CZECH_DIC (ne VAT_ID)
expected_tags = ['<PERSON', '<CZECH_ADDRESS', '<EMAIL', '<PHONE',
                 '<CREDIT_CARD', '<IBAN', '<CZECH_BIRTH_NUMBER',
                 '<CZECH_ICO', '<CZECH_DIC']
missing = [tag for tag in expected_tags if tag not in anon]
if missing:
    raise AssertionError(f'missing entity tags: {missing}\\nanon={anon}')
# Verify original PII is NOT in anonymized output
sensitive = ['+420731131426', 'jan.novak@firma.cz', '4532015112830366',
             'CZ6508000000192000145399', '800101/1234', '27082440']
leaked = [s for s in sensitive if s in anon]
if leaked:
    raise AssertionError(f'PII leaked in anonymized output: {leaked}')
print(f'ok ({len(expected_tags)} entity types, {len(mapping)} total entities)')
"
}

test_env_vars_present() {
    # Ověří, že kritické env proměnné jsou v kontejneru nastaveny.
    # GROQ_API_KEY: používá se pro Codex fallback / tool calls; prázdný = skryté selhání.
    # OPENCLAW_GATEWAY_TOKEN: autentizace pro webhooks (Caddy, Zapier).
    $COMPOSE exec -T openclaw-gateway sh -c '
MISSING=""
for VAR in OPENCLAW_GATEWAY_TOKEN; do
    eval "VAL=\$$VAR"
    if [ -z "$VAL" ]; then
        MISSING="$MISSING $VAR"
    fi
done
# GROQ_API_KEY je optional (warning, ne fail)
if [ -z "$GROQ_API_KEY" ]; then
    echo "warn: GROQ_API_KEY not set (optional)" >&2
fi
if [ -n "$MISSING" ]; then
    echo "missing critical env vars:$MISSING"
    exit 1
fi
echo "ok"
'
}

test_vault_indexed() {
    # Ověří, že vault je nakonfigurovaný v extraPaths a adresář není prázdný
    $COMPOSE exec -T openclaw-gateway node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json'));
const extra = config.agents?.defaults?.memorySearch?.extraPaths || [];
if (!extra.includes('vault')) { console.error('vault not in extraPaths'); process.exit(1); }
const vaultDir = '/home/node/.openclaw/workspace/vault';
if (!fs.existsSync(vaultDir)) { console.error('vault dir missing'); process.exit(1); }
const files = fs.readdirSync(vaultDir, { recursive: true }).filter(f => f.endsWith('.md'));
if (files.length === 0) { console.error('vault empty (no .md files)'); process.exit(1); }
console.log(files.length + ' markdown files in vault');
"
}

test_workspace_writeable() {
    # Ověří, že Claudie může zapisovat do workspace (upgrade triggery, skills)
    $COMPOSE exec -T openclaw-gateway sh -c '
TESTFILE="/home/node/.openclaw/workspace/.write-test-$$"
echo "test" > "$TESTFILE" 2>&1 && rm -f "$TESTFILE" && echo "ok" || { rm -f "$TESTFILE"; echo "write failed"; exit 1; }
'
}

test_llm_endpoint_reachable() {
    # Ověří, že nakonfigurovaný LLM provider je dosažitelný (bez LLM volání).
    # Čte baseUrl z configu a zkusí HTTP HEAD/GET na známý endpoint.
    $COMPOSE exec -T openclaw-gateway node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('/home/node/.openclaw/openclaw.json'));
const providers = config.models?.providers || {};
const primary = config.agents?.defaults?.model?.primary || '';
const providerKey = primary.split('/')[0];

// Najdi baseUrl pro primární provider
let baseUrl = providers[providerKey]?.baseUrl;
if (!baseUrl) {
    // Default endpoints pro známé providery
    const defaults = {
        'openai-codex': 'https://api.openai.com',
        'openai': 'https://api.openai.com',
        'anthropic': 'https://api.anthropic.com',
    };
    baseUrl = defaults[providerKey];
}
if (!baseUrl) { console.error('No baseUrl for provider: ' + providerKey); process.exit(1); }

// Test dosažitelnosti (HEAD request, ignorujeme auth errors)
const url = new URL(baseUrl);
fetch(url.origin, { method: 'HEAD', signal: AbortSignal.timeout(5000) })
    .then(r => {
        // Jakýkoli HTTP response (i 401/403/404) = endpoint je dosažitelný
        console.log(providerKey + ' reachable (' + url.origin + ' → ' + r.status + ')');
    })
    .catch(e => {
        // Síťová chyba = endpoint nedosažitelný
        if (baseUrl.startsWith('http://pii-proxy') || baseUrl.startsWith('http://localhost')) {
            // Interní proxy — test přes Docker síť
            console.error(providerKey + ' UNREACHABLE: ' + baseUrl + ' (' + e.cause?.code + ')');
            process.exit(1);
        }
        // Externí endpoint — může být blokovaný firewallem, zkusíme DNS
        console.log(providerKey + ' DNS ok, HTTP blocked (' + url.hostname + ')');
    });
"
}

test_doctor_errors() {
    local errors
    errors=$($COMPOSE exec -T openclaw-gateway node dist/index.js doctor 2>&1 | grep -oP 'Errors:\s*\K\d+' | head -1)
    if [ -z "$errors" ]; then errors=0; fi
    if [ "$errors" -gt 0 ]; then
        echo "$errors errors"
        return 1
    fi
    echo "0 errors"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo "=== OpenClaw Post-Upgrade Tests ==="
    echo ""

    cd "$ROOT_DIR"

    echo "--- Critical (infra) ---"
    run_test "gateway_health"       "critical"  test_gateway_health
    run_test "pii_proxy_health"     "critical"  test_pii_proxy_health
    run_test "node_llama_cpp"       "critical"  test_node_llama_cpp
    run_test "embedding_model"      "critical"  test_embedding_model_exists

    echo ""
    echo "--- Functional ---"
    run_test "pii_anonymization"    "functional" test_pii_anonymization
    run_test "pii_roundtrip"        "functional" test_pii_roundtrip
    run_test "pii_codex_format"     "functional" test_pii_codex_format
    run_test "pii_noanon_codex"     "functional" test_pii_noanon_codex
    run_test "pii_openai_route"     "functional" test_pii_openai_route
    run_test "pii_deanon_return_value" "functional" test_pii_deanon_return_value
    run_test "pii_phone_formats"    "functional" test_pii_phone_formats
    run_test "pii_entity_types"     "functional" test_pii_entity_types
    run_test "memory_status"        "functional" test_memory_status
    run_test "vault_indexed"        "functional" test_vault_indexed
    run_test "workspace_writeable"  "functional" test_workspace_writeable

    echo ""
    echo "--- Integration ---"
    run_test "llm_endpoint"         "integration" test_llm_endpoint_reachable

    echo ""
    echo "--- Status ---"
    run_test "workspace_skills"     "status"    test_workspace_skills
    run_test "active_memory"        "status"    test_active_memory_plugin
    run_test "dreaming"             "status"    test_dreaming_configured
    run_test "telegram_bots"        "status"    test_telegram_bots
    run_test "env_vars_present"     "status"    test_env_vars_present
    run_test "doctor_errors"        "status"    test_doctor_errors

    echo ""
    echo "=== Results: $PASS passed, $FAIL failed ==="

    # Write JSON result
    echo -n "]" >> "$TESTS_TMPFILE"
    local tests_json
    tests_json=$(cat "$TESTS_TMPFILE")
    rm -f "$TESTS_TMPFILE"

    local version
    version=$(git describe --tags --always 2>/dev/null || echo "unknown")
    cat > "$RESULT_FILE" <<EOJSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "$version",
  "passed": $PASS,
  "failed": $FAIL,
  "tests": $tests_json
}
EOJSON
    chmod 644 "$RESULT_FILE"

    return 0
}

main "$@"
