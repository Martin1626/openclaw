#!/bin/bash
# sync-claude-token.sh — Sync Claude Code CLI access token to OpenClaw
# Claude Code handles OAuth refresh natively; this script copies the fresh
# access token into OpenClaw's auth-profiles.json as a non-refreshing token.

set -euo pipefail

CLAUDE_CREDS="$HOME/.claude/.credentials.json"
OPENCLAW_AUTH="/home/deploy/.openclaw-gw/agents/main/agent/auth-profiles.json"
LOG_TAG="[sync-claude-token]"
BUFFER_MS=$((2 * 3600 * 1000))  # 2h buffer

log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $LOG_TAG $*"; }

# 1. Check Claude Code credentials exist
if [[ ! -f "$CLAUDE_CREDS" ]]; then
  log "ERROR: Claude credentials not found at $CLAUDE_CREDS"
  exit 1
fi

# 2. Read current expiry
EXPIRES_AT=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CLAUDE_CREDS")
NOW_MS=$(date +%s%3N)
REMAINING_MS=$((EXPIRES_AT - NOW_MS))

# 3. If token expires within 2h, force Claude Code to refresh
if [[ $REMAINING_MS -lt $BUFFER_MS ]]; then
  log "Token expires in $((REMAINING_MS / 60000))m — forcing refresh..."
  if claude -p 'ping' --max-turns 1 > /dev/null 2>&1; then
    log "Refresh successful"
    sleep 1
  else
    log "WARN: claude refresh command failed, trying with existing token"
  fi
fi

# 4. Read (potentially refreshed) credentials
ACCESS_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$CLAUDE_CREDS")
EXPIRES_AT=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CLAUDE_CREDS")

if [[ -z "$ACCESS_TOKEN" ]]; then
  log "ERROR: Could not read access token from Claude Code"
  exit 1
fi

# 5. Write to OpenClaw auth-profiles.json
TEMP=$(mktemp)
NOW_MS=$(date +%s%3N)
jq --arg token "$ACCESS_TOKEN"    --argjson expires "$EXPIRES_AT"    --argjson now "$NOW_MS" '
  .profiles["anthropic:claude"] = {
    type: "token",
    provider: "anthropic",
    token: $token,
    expires: $expires
  } |
  .lastGood.anthropic = "anthropic:claude" |
  .usageStats["anthropic:claude"] = {
    lastUsed: $now,
    errorCount: 0
  }
' "$OPENCLAW_AUTH" > "$TEMP" && mv "$TEMP" "$OPENCLAW_AUTH"

EXPIRES_HUMAN=$(date -d @$((EXPIRES_AT / 1000)) -u '+%Y-%m-%dT%H:%M:%SZ')
log "Token synced to OpenClaw. Expires: $EXPIRES_HUMAN"
