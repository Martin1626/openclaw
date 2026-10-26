#!/bin/sh
# Ensure node-llama-cpp is available for local embeddings.
# Installed persistently in workspace/node_modules/, linked into /app/node_modules/.
# See .my/docs/OpenClaw_server_info.md for setup details.
LLAMA_SRC="/home/node/.openclaw/workspace/node_modules/node-llama-cpp"
LLAMA_DST="/app/node_modules/node-llama-cpp"
if [ -d "$LLAMA_SRC" ] && [ ! -e "$LLAMA_DST" ]; then
    ln -sf "$LLAMA_SRC" "$LLAMA_DST" 2>/dev/null || true
fi
# Hand over to the upstream entrypoint (tini + image activation, which runs
# `doctor --fix` before a foreground gateway) instead of bypassing it.
if [ -f /app/docker-entrypoint.mjs ]; then
    exec tini -s -- node /app/docker-entrypoint.mjs "$@"
fi
exec "$@"
