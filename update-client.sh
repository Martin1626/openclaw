#!/usr/bin/env bash
# ==========================================================================
# OpenClaw — Aktualizační skript / Update script
#
# Použití / Usage:
#   bash update-client.sh
# ==========================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"

info()  { echo "==> $*"; }
fail()  { echo "CHYBA: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Stáhnout změny / Pull updates
# ---------------------------------------------------------------------------
info "Stahuji aktualizace..."
cd "$ROOT_DIR"
git pull || fail "git pull selhal. Zkontrolujte připojení k internetu."

# ---------------------------------------------------------------------------
# 2. Rebuild images
# ---------------------------------------------------------------------------
info "Stavím Docker image..."
docker build -t "$IMAGE_NAME" -f "$ROOT_DIR/Dockerfile" "$ROOT_DIR"

info "Stavím pii-proxy image..."
docker compose -f "$COMPOSE_FILE" build pii-proxy

# ---------------------------------------------------------------------------
# 3. Restart kontejnerů / Restart containers
# ---------------------------------------------------------------------------
info "Restartuji kontejnery..."
docker compose -f "$COMPOSE_FILE" down
docker compose -f "$COMPOSE_FILE" up -d

# ---------------------------------------------------------------------------
# 4. Healthcheck
# ---------------------------------------------------------------------------
info "Čekám na spuštění..."
sleep 5

# Kontrola pii-proxy
if curl -sf http://localhost:3001/health >/dev/null 2>&1; then
  info "PII proxy: OK"
else
  echo "VAROVÁNÍ: PII proxy zatím neodpovídá (může ještě startovat)"
fi

# Kontrola gateway
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
if curl -sf "http://localhost:${GATEWAY_PORT}" >/dev/null 2>&1; then
  info "Gateway: OK"
else
  echo "VAROVÁNÍ: Gateway zatím neodpovídá (může ještě startovat)"
fi

echo ""
info "Aktualizace dokončena!"
echo ""
echo "Logy: docker compose -f $COMPOSE_FILE logs -f"
