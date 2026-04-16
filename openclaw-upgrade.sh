#!/usr/bin/env bash
# ==========================================================================
# OpenClaw — Self-service upgrade skript s automatickým rollback
#
# Spouštěn systemd path unitem, když Claudie zapíše trigger soubor.
# Může být spuštěn i ručně: bash openclaw-upgrade.sh [rollback]
#
# Trigger soubor (JSON):
#   {"action":"upgrade","target":"latest-stable","timestamp":"..."}
#   {"action":"upgrade","target":"v2026.3.22","timestamp":"..."}
#   {"action":"rollback","timestamp":"..."}
#
# ==========================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Konfigurace
# ---------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"
UPSTREAM_URL="https://github.com/openclaw/openclaw.git"

WORKSPACE="${OPENCLAW_WORKSPACE_DIR:-/home/deploy/.openclaw-gw/workspace}"
TRIGGER_FILE="$WORKSPACE/.upgrade-trigger"
RESULT_FILE="$WORKSPACE/.upgrade-result"
LOG_FILE="$WORKSPACE/.upgrade-log"
LOCK_FILE="/tmp/openclaw-upgrade.lock"

MIN_DISK_MB=2048
MAX_BACKUP_IMAGES=3
HEALTH_TIMEOUT=60
HEALTH_INTERVAL=5

# ---------------------------------------------------------------------------
# Pomocné funkce
# ---------------------------------------------------------------------------
TS() { date '+%Y-%m-%d %H:%M:%S'; }
info()  { echo "[$(TS)] INFO:  $*" | tee -a "$LOG_FILE"; }
warn()  { echo "[$(TS)] WARN:  $*" | tee -a "$LOG_FILE"; }
fail()  { echo "[$(TS)] ERROR: $*" | tee -a "$LOG_FILE" >&2; }

write_result() {
    local status="$1" version="${2:-}" message="${3:-}" rollback_tag="${4:-}"
    cat > "$RESULT_FILE" <<EOJSON
{
  "status": "$status",
  "version": "$version",
  "message": "$message",
  "rollback_tag": "$rollback_tag",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "log": "$LOG_FILE"
}
EOJSON
    chmod 644 "$RESULT_FILE"
}

cleanup_trigger() {
    rm -f "$TRIGGER_FILE"
}

cleanup_old_backups() {
    local kept=0
    for tag in $(docker images "$IMAGE_NAME" --format '{{.Tag}}' 2>/dev/null | grep '^backup-' | sort -r); do
        kept=$((kept + 1))
        if [ "$kept" -gt "$MAX_BACKUP_IMAGES" ]; then
            info "Mažu starý backup image: $IMAGE_NAME:$tag"
            docker rmi "$IMAGE_NAME:$tag" 2>/dev/null || true
        fi
    done
}

check_disk_space() {
    local avail_mb
    avail_mb=$(df -m "$ROOT_DIR" | awk 'NR==2 {print $4}')
    if [ "$avail_mb" -lt "$MIN_DISK_MB" ]; then
        fail "Nedostatek místa na disku: ${avail_mb} MB (minimum: ${MIN_DISK_MB} MB)"
        return 1
    fi
    info "Volné místo na disku: ${avail_mb} MB"
}

ensure_upstream_remote() {
    cd "$ROOT_DIR"
    if ! git remote get-url upstream >/dev/null 2>&1; then
        info "Přidávám upstream remote: $UPSTREAM_URL"
        git remote add upstream "$UPSTREAM_URL"
    fi
}

get_latest_stable_tag() {
    git tag -l 'v20*' | grep -v -E '(beta|alpha|rc|dev)' | sort -V | tail -1
}

get_current_version() {
    git describe --tags --always 2>/dev/null || git rev-parse --short HEAD
}

health_check() {
    local elapsed=0
    info "Čekám na health check (max ${HEALTH_TIMEOUT}s)..."

    while [ "$elapsed" -lt "$HEALTH_TIMEOUT" ]; do
        sleep "$HEALTH_INTERVAL"
        elapsed=$((elapsed + HEALTH_INTERVAL))

        local gw_ok=false pii_ok=false
        if curl -sf http://127.0.0.1:18789/healthz >/dev/null 2>&1; then
            gw_ok=true
        fi
        if curl -sf http://127.0.0.1:3001/health >/dev/null 2>&1; then
            pii_ok=true
        fi

        if [ "$gw_ok" = true ] && [ "$pii_ok" = true ]; then
            info "Health check OK: gateway + pii-proxy"
            return 0
        fi

        info "  Čekám... (${elapsed}s) gateway=$gw_ok pii-proxy=$pii_ok"
    done

    fail "Health check selhal po ${HEALTH_TIMEOUT}s"
    return 1
}

# ---------------------------------------------------------------------------
# Rollback
# ---------------------------------------------------------------------------
do_rollback() {
    local reason="${1:-manuální rollback}"
    info "=== ROLLBACK: $reason ==="

    cd "$ROOT_DIR"

    # Najdi poslední backup image
    local backup_tag
    backup_tag=$(docker images "$IMAGE_NAME" --format '{{.Tag}}' 2>/dev/null | grep '^backup-' | sort -r | head -1)
    if [ -z "$backup_tag" ]; then
        fail "Žádný backup image nenalezen! Rollback není možný."
        write_result "rollback_failed" "" "Žádný backup image" ""
        return 1
    fi

    info "Obnovuji image: $IMAGE_NAME:$backup_tag → $IMAGE_NAME"
    docker tag "$IMAGE_NAME:$backup_tag" "$IMAGE_NAME"

    # Najdi poslední pre-upgrade git tag
    local git_backup_tag
    git_backup_tag=$(git tag -l 'local/pre-*' | sort -r | head -1)
    if [ -n "$git_backup_tag" ]; then
        info "Obnovuji git stav: $git_backup_tag"
        git reset --hard "$git_backup_tag" || warn "Git reset selhal, pokračuji s aktuálním stavem"
    fi

    info "Restartuji kontejnery s rollback image..."
    docker compose down 2>&1 | tee -a "$LOG_FILE"
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"

    if health_check; then
        info "=== ROLLBACK ÚSPĚŠNÝ ==="
        write_result "rollback_ok" "$(get_current_version)" "Rollback z důvodu: $reason" "$backup_tag"
        return 0
    else
        fail "=== ROLLBACK SELHAL — systém může být nestabilní ==="
        write_result "rollback_failed" "$(get_current_version)" "Rollback i health check selhaly" "$backup_tag"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Hlavní upgrade
# ---------------------------------------------------------------------------
do_upgrade() {
    local target="$1"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    info "=========================================="
    info "OpenClaw upgrade zahájen"
    info "Cíl: $target"
    info "=========================================="

    cd "$ROOT_DIR"

    # --- Kontroly ---
    check_disk_space || { write_result "error" "" "Nedostatek místa na disku" ""; return 1; }

    if [ -n "$(git status --porcelain)" ]; then
        fail "Git working tree není čistý!"
        git status --short | tee -a "$LOG_FILE"
        write_result "error" "" "Git working tree není čistý" ""
        return 1
    fi

    # --- Verze před upgradem ---
    local version_before
    version_before=$(get_current_version)
    info "Aktuální verze: $version_before"

    # --- Upstream remote ---
    ensure_upstream_remote

    # --- Fetch ---
    info "Fetch upstream tags..."
    if ! git fetch upstream --tags 2>&1 | tee -a "$LOG_FILE"; then
        fail "git fetch upstream selhal (síť?)"
        write_result "error" "$version_before" "git fetch upstream selhal" ""
        return 1
    fi

    # --- Resolve target tag ---
    local target_tag
    if [ "$target" = "latest-stable" ]; then
        target_tag=$(get_latest_stable_tag)
        if [ -z "$target_tag" ]; then
            fail "Nepodařilo se najít latest stable tag"
            write_result "error" "$version_before" "Žádný stable tag nenalezen" ""
            return 1
        fi
        info "Latest stable tag: $target_tag"
    else
        target_tag="$target"
    fi

    # Ověř, že tag existuje
    if ! git rev-parse "$target_tag" >/dev/null 2>&1; then
        fail "Tag $target_tag neexistuje. Dostupné:"
        git tag -l 'v20*' | grep -v -E '(beta|alpha|rc|dev)' | sort -V | tail -5 | tee -a "$LOG_FILE"
        write_result "error" "$version_before" "Tag $target_tag neexistuje" ""
        return 1
    fi

    # Zkontroluj, jestli není už na požadované verzi
    if git merge-base --is-ancestor "$target_tag" HEAD 2>/dev/null; then
        info "Tag $target_tag je již zahrnut v aktuální verzi."
        write_result "already_current" "$version_before" "Už na verzi $target_tag nebo novější" ""
        cleanup_trigger
        return 0
    fi

    # --- Záloha Docker image ---
    info "Záloha Docker image: $IMAGE_NAME → $IMAGE_NAME:backup-$timestamp"
    docker tag "$IMAGE_NAME" "$IMAGE_NAME:backup-$timestamp" 2>/dev/null || warn "Backup image tagging selhal (první instalace?)"

    # --- Záloha git ---
    local git_backup_tag="local/pre-$target_tag"
    if git tag -l "$git_backup_tag" | grep -q .; then
        git_backup_tag="local/pre-${target_tag}-${timestamp}"
    fi
    info "Git backup tag: $git_backup_tag"
    git tag "$git_backup_tag"

    # --- Pre-merge kontrola konfliktů (OAuth soubory) ---
    info "Kontrola potenciálních konfliktů..."
    local conflict_risk=false
    for f in src/commands/models/auth.ts src/agents/auth-profiles/oauth.ts src/providers/anthropic-oauth.ts; do
        if ! git diff --quiet "HEAD...$target_tag" -- "$f" 2>/dev/null; then
            warn "  $f: ZMĚNĚN upstreamem — možný konflikt"
            conflict_risk=true
        fi
    done

    # --- Merge ---
    info "Merge: $target_tag → local main..."
    if ! git merge "$target_tag" --no-ff -m "merge: upstream $target_tag into local main (self-upgrade)" 2>&1 | tee -a "$LOG_FILE"; then
        fail "MERGE KONFLIKT! Automatický upgrade přerušen."
        git merge --abort 2>/dev/null || true
        git tag -d "$git_backup_tag" 2>/dev/null || true
        docker rmi "$IMAGE_NAME:backup-$timestamp" 2>/dev/null || true
        write_result "conflict" "$version_before" "Merge konflikt s $target_tag — vyžaduje ruční řešení" ""
        return 1
    fi

    local version_after
    version_after=$(get_current_version)
    info "Merge úspěšný: $version_before → $version_after"

    # --- Tag výsledku ---
    git tag "local/$target_tag" 2>/dev/null || true

    # --- Build ---
    info "Build Docker image..."
    if ! docker compose build 2>&1 | tee -a "$LOG_FILE"; then
        fail "Docker build selhal! Rollback git..."
        git reset --hard "$git_backup_tag"
        git tag -d "local/$target_tag" 2>/dev/null || true
        write_result "build_failed" "$version_before" "Docker build selhal" "backup-$timestamp"
        return 1
    fi

    # --- Rebuild PII proxy (pokud se změnilo pii-proxy/) ---
    if git diff --name-only "$git_backup_tag..HEAD" -- pii-proxy/ 2>/dev/null | grep -q .; then
        info "Změny v pii-proxy/ detekovány, rebuilduji..."
        docker compose build pii-proxy 2>&1 | tee -a "$LOG_FILE" || warn "PII proxy rebuild selhal"
    else
        info "PII proxy beze změn, přeskakuji rebuild"
    fi

    # --- Restart ---
    info "Restart kontejnerů..."
    docker compose down 2>&1 | tee -a "$LOG_FILE"
    docker compose up -d 2>&1 | tee -a "$LOG_FILE"

    # --- Health check ---
    if ! health_check; then
        warn "Health check selhal — spouštím automatický rollback..."
        do_rollback "health check selhal po upgrade na $target_tag"
        return 1
    fi

    # --- Push na fork ---
    info "Push na origin (fork)..."
    git push origin main --tags 2>&1 | tee -a "$LOG_FILE" || warn "git push selhal (nic kritického, lokální verze běží)"

    # --- Cleanup ---
    cleanup_old_backups

    info "=========================================="
    info "UPGRADE ÚSPĚŠNÝ: $version_before → $version_after ($target_tag)"
    info "=========================================="

    write_result "success" "$version_after" "Upgrade z $version_before na $target_tag" "backup-$timestamp"
    return 0
}

# ---------------------------------------------------------------------------
# Hlavní logika
# ---------------------------------------------------------------------------
main() {
    # Truncate log
    : > "$LOG_FILE"

    info "openclaw-upgrade.sh spuštěn"

    # Zpracování CLI argumentu (ruční spuštění)
    if [ "${1:-}" = "rollback" ]; then
        do_rollback "manuální příkaz"
        cleanup_trigger
        exit $?
    fi

    if [ "${1:-}" = "dry-run" ]; then
        cd "$ROOT_DIR"
        ensure_upstream_remote
        git fetch upstream --tags 2>/dev/null
        local latest
        latest=$(get_latest_stable_tag)
        local current
        current=$(get_current_version)
        echo "Aktuální verze: $current"
        echo "Poslední stable: $latest"
        if git merge-base --is-ancestor "$latest" HEAD 2>/dev/null; then
            echo "Stav: UŽ AKTUÁLNÍ"
        else
            echo "Stav: UPGRADE DOSTUPNÝ"
            echo "Změněné soubory:"
            git diff --stat "HEAD...$latest" 2>/dev/null | tail -5
        fi
        exit 0
    fi

    # Zpracování trigger souboru
    local action="upgrade"
    local target="latest-stable"

    if [ -f "$TRIGGER_FILE" ]; then
        # Parsuj JSON trigger (jq pokud dostupný, jinak grep)
        if command -v jq >/dev/null 2>&1; then
            action=$(jq -r '.action // "upgrade"' "$TRIGGER_FILE" 2>/dev/null || echo "upgrade")
            target=$(jq -r '.target // "latest-stable"' "$TRIGGER_FILE" 2>/dev/null || echo "latest-stable")
        else
            action=$(grep -oP '"action"\s*:\s*"\K[^"]+' "$TRIGGER_FILE" 2>/dev/null || echo "upgrade")
            target=$(grep -oP '"target"\s*:\s*"\K[^"]+' "$TRIGGER_FILE" 2>/dev/null || echo "latest-stable")
        fi
        info "Trigger soubor: action=$action target=$target"
        cleanup_trigger
    elif [ -z "${1:-}" ]; then
        # Bez trigger souboru a bez argumentů = spuštěn manuálně bez parametrů
        info "Žádný trigger soubor ani argument. Použití:"
        echo "  bash $0 dry-run       # Zkontroluj dostupné verze"
        echo "  bash $0 rollback      # Vrať předchozí verzi"
        echo "  Nebo zapište trigger soubor do: $TRIGGER_FILE"
        exit 0
    fi

    # Akce
    case "$action" in
        upgrade)
            do_upgrade "$target"
            ;;
        rollback)
            do_rollback "trigger soubor"
            ;;
        *)
            fail "Neznámá akce: $action"
            write_result "error" "" "Neznámá akce: $action" ""
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Spuštění s flock
# ---------------------------------------------------------------------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Jiný upgrade již běží (lock: $LOCK_FILE)" >&2
    exit 1
fi

main "$@"
