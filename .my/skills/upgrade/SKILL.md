---
name: upgrade
description: "Self-service OpenClaw upgrade. Use when: user asks to upgrade/update OpenClaw, check for new versions, or rollback to a previous version. The upgrade runs on the host via systemd — you trigger it by writing a JSON file to workspace."
user-invocable: false
metadata: { "openclaw": { "emoji": "⬆️" } }
---

# OpenClaw Self-Service Upgrade

Upgrade, deploy, or rollback OpenClaw without SSH access.

## How It Works

You write a JSON trigger file to the workspace. A systemd path watcher on the host detects it and runs the upgrade script. The script handles git merge, Docker build, container restart, health checks, and automatic rollback on failure.

**IMPORTANT:** The upgrade restarts your container — you will lose the current session. Warn the user before triggering.

## Check Available Versions

```bash
# Check the latest stable upstream tag
curl -s https://api.github.com/repos/openclaw/openclaw/releases/latest | grep -o '"tag_name": "[^"]*"'
```

Or read the last upgrade result:
```bash
cat /home/node/.openclaw/workspace/.upgrade-result
```

## Trigger Upgrade (latest stable)

```bash
cat > /home/node/.openclaw/workspace/.upgrade-trigger << 'EOF'
{"action":"upgrade","target":"latest-stable"}
EOF
```

## Trigger Upgrade (specific version)

```bash
cat > /home/node/.openclaw/workspace/.upgrade-trigger << 'EOF'
{"action":"upgrade","target":"v2026.4.14"}
EOF
```

## Trigger Deploy (rebuild without merge)

Use when the code is already updated via git but the Docker image needs rebuilding:

```bash
cat > /home/node/.openclaw/workspace/.upgrade-trigger << 'EOF'
{"action":"deploy"}
EOF
```

## Trigger Rollback

Restore the previous Docker image and git state:

```bash
cat > /home/node/.openclaw/workspace/.upgrade-trigger << 'EOF'
{"action":"rollback"}
EOF
```

## Read Result (after restart)

After your container restarts, read the result:

```bash
cat /home/node/.openclaw/workspace/.upgrade-result
```

Result JSON fields:
- `status`: `success`, `already_current`, `conflict`, `build_failed`, `error`, `rollback_ok`, `rollback_failed`
- `version`: current version after operation (this reads `git describe` — **not** the Docker image version)
- `message`: human-readable description
- `rollback_tag`: Docker backup image tag (for manual rollback reference)

## Verify Runtime Matches Git (do this every time)

The `version` field in the result comes from `git describe HEAD` — it tells you what code is in the repo, **not** what the running Docker image was built from. These two can drift apart. Always confirm the container actually runs the version you intended:

```bash
# What the running Docker image was built from:
grep '"version"' /app/package.json
```

Compare this with the target tag. If they disagree, the git state advanced but the image is stale → the upgrade did not actually apply to the runtime.

**Known scenario for a silent desync:** after a `rollback`, git is reset to a pre-upgrade tag but the merge commit that brought the target tag in still lives on `origin/main`. The next `upgrade` runs `git pull origin main` first, which fast-forwards past the target again. The script then sees "target is already an ancestor of HEAD" and exits `already_current` **without rebuilding the Docker image**. Git is on the new version, runtime is still on the old one.

**Fix:** trigger a rebuild without merge:

```bash
cat > /home/node/.openclaw/workspace/.upgrade-trigger << 'EOF'
{"action":"deploy"}
EOF
```

Do not report an upgrade as successful to the user until `/app/package.json` matches the target tag.

## What Happens During Upgrade

1. `git pull origin main` (gets latest fork code)
2. `git fetch upstream --tags` (gets upstream release tags)
3. Resolves target version (latest stable or specific tag)
4. Creates Docker image backup (`openclaw:backup-YYYYMMDD-HHMMSS`)
5. Creates git tag backup (`local/pre-<version>`)
6. `git merge <tag> --no-ff` (if conflict → aborts, nothing changes)
7. `docker compose build` (~15 min on VPS)
8. `docker compose down && up -d` (your session ends here)
9. Health check (gateway + PII proxy)
10. If health check fails → automatic rollback to backup image
11. If OK → `git push origin main --tags`

## When NOT to Upgrade

- In the middle of an important conversation (warn user about session loss)
- When the user hasn't confirmed they want to upgrade
- When disk space is low (check with `df -h` — need at least 2 GB free)
- When the result of a previous upgrade shows `conflict` (needs manual resolution on PC)

## When Conflicts Occur

If the upgrade returns `status: "conflict"`, tell the user:
- Automatic merge failed — manual resolution needed
- User should run on their PC: `bash scripts/upgrade-from-upstream.sh <tag>`
- After resolving and pushing, trigger `{"action":"deploy"}` to rebuild
