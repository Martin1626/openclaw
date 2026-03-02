#!/bin/bash
# Upgrade OpenClaw fork from upstream tag.
# Usage: bash scripts/upgrade-from-upstream.sh <tag>
# Example: bash scripts/upgrade-from-upstream.sh v2026.3.1
set -euo pipefail

TAG="${1:?Použití: $0 <upstream-tag>  (např. v2026.3.1)}"

echo "=== Kontrola čistého stavu ==="
if [[ -n "$(git status --porcelain)" ]]; then
    echo "CHYBA: Máš uncommitted změny. Commitni nebo stashni před upgrade."
    git status --short
    exit 1
fi

echo "=== Záloha: local/pre-$TAG ==="
git tag "local/pre-$TAG"

echo "=== Fetch upstream ==="
git fetch upstream --tags

echo "=== Kontrola, zda tag existuje ==="
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "CHYBA: Tag $TAG neexistuje. Dostupné v2026.* tagy:"
    git tag -l 'v2026.*' | sort -V | tail -10
    git tag -d "local/pre-$TAG"
    exit 1
fi

echo ""
echo "=== Změny v OAuth souborech (kontrola před merge) ==="
CURRENT_BASE=$(git describe --tags --abbrev=0 upstream/main 2>/dev/null || echo "$TAG")
for f in src/commands/models/auth.ts src/commands/auth-choice.apply.anthropic.ts src/agents/auth-profiles/oauth.ts; do
    if git diff --quiet "HEAD...$TAG" -- "$f" 2>/dev/null; then
        echo "  $f: beze změn"
    else
        echo "  $f: ZMĚNĚN upstreamem — možný konflikt"
    fi
done
echo ""

echo "=== Merge $TAG ==="
if ! git merge "$TAG" --no-ff -m "merge: upstream $TAG into local main"; then
    echo ""
    echo ">>> KONFLIKTY — vyřeš ručně, pak spusť:"
    echo ">>>   git add <soubory>"
    echo ">>>   git commit"
    echo ">>>   git tag local/$TAG"
    echo ">>>   git push origin main --tags"
    exit 1
fi

echo "=== Tag: local/$TAG ==="
git tag "local/$TAG"

echo ""
echo "=== HOTOVO ==="
echo "Další kroky:"
echo "  1. pnpm install && pnpm build && pnpm test"
echo "  2. git push origin main --tags"
echo "  3. Na serveru: git pull && docker compose build && docker compose up -d"
