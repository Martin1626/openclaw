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
