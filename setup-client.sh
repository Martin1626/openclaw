#!/usr/bin/env bash
# ==========================================================================
# OpenClaw — Instalační skript pro klienty
# Setup script for new client deployments
#
# Použití / Usage:
#   git clone <repo-url> openclaw && cd openclaw
#   bash setup-client.sh
# ==========================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "==> $*"; }
warn()  { echo "VAROVÁNÍ: $*" >&2; }
fail()  { echo "CHYBA: $*" >&2; exit 1; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
}

# ---------------------------------------------------------------------------
# 1. Kontrola prerekvizit / Check prerequisites
# ---------------------------------------------------------------------------
info "Kontrola prerekvizit..."

MISSING=()
if ! require_cmd docker; then
  MISSING+=("docker")
fi
if ! require_cmd git; then
  MISSING+=("git")
fi
if ! require_cmd curl; then
  MISSING+=("curl")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "Chybí potřebné programy: ${MISSING[*]}"
  echo ""
  echo "Nainstalujte je následovně:"
  echo ""
  for cmd in "${MISSING[@]}"; do
    case "$cmd" in
      docker)
        echo "  Docker:"
        echo "    curl -fsSL https://get.docker.com | sh"
        echo "    sudo usermod -aG docker \$USER"
        echo "    (po instalaci se odhlaste a přihlaste znovu)"
        echo ""
        ;;
      git)
        echo "  Git:"
        echo "    sudo apt-get update && sudo apt-get install -y git"
        echo ""
        ;;
      curl)
        echo "  Curl:"
        echo "    sudo apt-get update && sudo apt-get install -y curl"
        echo ""
        ;;
    esac
  done
  echo "Po instalaci spusťte tento skript znovu: bash setup-client.sh"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo ""
  echo "Docker Compose není dostupný."
  echo "Pokud jste právě nainstalovali Docker, odhlaste se a přihlaste znovu."
  echo "Poté zkuste:  docker compose version"
  exit 1
fi

info "Prerekvizity OK (docker, git, curl)"

# ---------------------------------------------------------------------------
# 2. Nastavení cest / Configure paths
# ---------------------------------------------------------------------------
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"

mkdir -p "$OPENCLAW_CONFIG_DIR"
mkdir -p "$OPENCLAW_WORKSPACE_DIR"

export OPENCLAW_CONFIG_DIR
export OPENCLAW_WORKSPACE_DIR
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
export OPENCLAW_IMAGE="$IMAGE_NAME"

# ---------------------------------------------------------------------------
# 3. Interaktivní konfigurace / Interactive configuration
# ---------------------------------------------------------------------------
echo ""
echo "============================================"
echo "   OpenClaw — Nastavení pro nového klienta"
echo "============================================"
echo ""

# --- Anthropic API klíč ---
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Potřebujete Anthropic API klíč."
  echo "Získáte ho na: https://console.anthropic.com/settings/keys"
  echo ""
  while true; do
    read -rp "Anthropic API klíč (sk-ant-...): " ANTHROPIC_API_KEY
    if [[ "$ANTHROPIC_API_KEY" == sk-ant-* ]]; then
      break
    elif [[ "$ANTHROPIC_API_KEY" == sk-* ]]; then
      # Some keys don't have the -ant- prefix
      break
    else
      echo "Neplatný formát. Klíč by měl začínat 'sk-ant-' nebo 'sk-'."
    fi
  done
fi
export ANTHROPIC_API_KEY

# --- Gateway token ---
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
  else
    OPENCLAW_GATEWAY_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  fi
fi
export OPENCLAW_GATEWAY_TOKEN

# --- Vlastní příjmení pro PII detekci ---
echo ""
echo "PII anonymizace chrání vaše osobní údaje."
echo "Můžete přidat příjmení vašich kontaktů pro lepší detekci."
echo "(Příjmení v 1. pádu, malými písmeny, jedno na řádek)"
echo ""
read -rp "Chcete přidat vlastní příjmení? [a/N]: " ADD_SURNAMES
if [[ "$ADD_SURNAMES" =~ ^[aAyY] ]]; then
  SURNAMES_FILE="$ROOT_DIR/pii-proxy/surnames.txt"
  echo ""
  echo "Zadávejte příjmení (jedno na řádek). Prázdný řádek = konec:"
  echo "# Vlastní příjmení pro PII detekci" > "$SURNAMES_FILE"
  while true; do
    read -rp "  > " SURNAME
    if [[ -z "$SURNAME" ]]; then
      break
    fi
    echo "${SURNAME,,}" >> "$SURNAMES_FILE"
  done
  SURNAME_COUNT=$(grep -cv '^#\|^$' "$SURNAMES_FILE" 2>/dev/null || echo "0")
  info "Uloženo $SURNAME_COUNT příjmení do pii-proxy/surnames.txt"
fi

# ---------------------------------------------------------------------------
# 4. Generování konfigurace / Generate configuration
# ---------------------------------------------------------------------------
info "Generuji konfiguraci..."

# Kopírování openclaw.json ze šablony (pokud ještě neexistuje)
if [[ ! -f "$OPENCLAW_CONFIG_DIR/openclaw.json" ]]; then
  cp "$ROOT_DIR/openclaw.template.json" "$OPENCLAW_CONFIG_DIR/openclaw.json"
  info "Vytvořen $OPENCLAW_CONFIG_DIR/openclaw.json ze šablony"
else
  info "openclaw.json už existuje, přeskakuji"
fi

# Kopírování workspace šablon (pokud workspace je prázdný)
if [[ -d "$ROOT_DIR/template/workspace" ]]; then
  TEMPLATE_FILES=(AGENTS.md SOUL.md IDENTITY.md USER.md HEARTBEAT.md BOOTSTRAP.md)
  COPIED=0
  for f in "${TEMPLATE_FILES[@]}"; do
    if [[ ! -f "$OPENCLAW_WORKSPACE_DIR/$f" && -f "$ROOT_DIR/template/workspace/$f" ]]; then
      cp "$ROOT_DIR/template/workspace/$f" "$OPENCLAW_WORKSPACE_DIR/$f"
      ((COPIED++))
    fi
  done
  if [[ $COPIED -gt 0 ]]; then
    info "Zkopírováno $COPIED workspace šablon"
  fi
fi

# Vytvoření .env
ENV_FILE="$ROOT_DIR/.env"
upsert_env() {
  local file="$1"
  shift
  local -a keys=("$@")
  local tmp
  tmp="$(mktemp)"
  local seen=" "

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      local key="${line%%=*}"
      local replaced=false
      for k in "${keys[@]}"; do
        if [[ "$key" == "$k" ]]; then
          printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
          seen="$seen$k "
          replaced=true
          break
        fi
      done
      if [[ "$replaced" == false ]]; then
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$file"
  fi

  for k in "${keys[@]}"; do
    if [[ "$seen" != *" $k "* ]]; then
      printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
    fi
  done

  mv "$tmp" "$file"
}

upsert_env "$ENV_FILE" \
  OPENCLAW_CONFIG_DIR \
  OPENCLAW_WORKSPACE_DIR \
  OPENCLAW_GATEWAY_PORT \
  OPENCLAW_BRIDGE_PORT \
  OPENCLAW_GATEWAY_BIND \
  OPENCLAW_GATEWAY_TOKEN \
  OPENCLAW_IMAGE \
  ANTHROPIC_API_KEY

info "Konfigurace uložena do .env"

# ---------------------------------------------------------------------------
# 5. Build Docker images / Build Docker images
# ---------------------------------------------------------------------------
info "Stavím Docker image (může trvat několik minut)..."
docker build \
  -t "$IMAGE_NAME" \
  -f "$ROOT_DIR/Dockerfile" \
  "$ROOT_DIR"

info "Stavím pii-proxy image..."
docker compose -f "$COMPOSE_FILE" build pii-proxy

# ---------------------------------------------------------------------------
# 6. Onboarding
# ---------------------------------------------------------------------------
echo ""
info "Spouštím onboarding..."
echo "Při dotazech zvolte:"
echo "  - Gateway bind: lan"
echo "  - Gateway auth: token"
echo "  - Gateway token: (ponechte výchozí)"
echo "  - Install daemon: No"
echo ""
docker compose -f "$COMPOSE_FILE" run --rm openclaw-cli onboard --no-install-daemon

# ---------------------------------------------------------------------------
# 7. WhatsApp pairing (volitelné)
# ---------------------------------------------------------------------------
echo ""
read -rp "Chcete připojit WhatsApp? [a/N]: " SETUP_WA
if [[ "$SETUP_WA" =~ ^[aAyY] ]]; then
  info "Spouštím WhatsApp pairing..."
  echo "V telefonu: WhatsApp → Nastavení → Propojená zařízení → Propojit zařízení"
  echo "Naskenujte QR kód, který se zobrazí níže."
  echo ""
  docker compose -f "$COMPOSE_FILE" run --rm openclaw-cli channels login
fi

# ---------------------------------------------------------------------------
# 8. Spuštění / Start
# ---------------------------------------------------------------------------
info "Spouštím OpenClaw..."
docker compose -f "$COMPOSE_FILE" up -d

echo ""
echo "============================================"
echo "   OpenClaw je připraven!"
echo "============================================"
echo ""
echo "WebUI:     http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):${OPENCLAW_GATEWAY_PORT}"
echo "Token:     $OPENCLAW_GATEWAY_TOKEN"
echo ""
echo "Konfigurace: $OPENCLAW_CONFIG_DIR/openclaw.json"
echo "Workspace:   $OPENCLAW_WORKSPACE_DIR"
echo ""
echo "--- Užitečné příkazy ---"
echo "Logy:      docker compose -f $COMPOSE_FILE logs -f"
echo "Restart:   docker compose -f $COMPOSE_FILE restart"
echo "Stop:      docker compose -f $COMPOSE_FILE down"
echo "Update:    bash $ROOT_DIR/update-client.sh"
echo ""
