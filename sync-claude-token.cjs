#!/usr/bin/env node
/**
 * sync-claude-token.cjs — Sync Claude Code OAuth token to OpenClaw
 *
 * Reads access token from Claude Code credentials, forces refresh if
 * expiring within REFRESH_BUFFER_MS, then writes to auth-profiles.json
 * and restarts gateway if the token changed.
 *
 * Designed to run via cron every 3 hours.
 */

var fs = require("fs");
var execSync = require("child_process").execSync;

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
var CLAUDE_CREDS = process.env.HOME + "/.claude/.credentials.json";
var OPENCLAW_AUTH = "/home/deploy/.openclaw-gw/agents/main/agent/auth-profiles.json";
var COMPOSE_DIR = "/home/deploy/openclaw";
var TAG = "[sync-claude-token]";

// Access token ~8h validity; refresh if less than 3.5h remains
var REFRESH_BUFFER_MS = 3.5 * 60 * 60 * 1000; // 3h 30min

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function log(msg) {
  console.log(new Date().toISOString() + " " + TAG + " " + msg);
}

function readCreds() {
  if (!fs.existsSync(CLAUDE_CREDS)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(CLAUDE_CREDS, "utf8"));
}

function forceRefresh() {
  log("Forcing token refresh via 'claude -p ping'...");
  try {
    // Set expiresAt to 0 so Claude Code CLI considers the token expired
    // and refreshes it using the refresh token
    var creds = readCreds();
    if (!creds || !creds.claudeAiOauth) {
      log("ERROR: Cannot force refresh — no credentials found");
      return false;
    }

    var origExpiry = creds.claudeAiOauth.expiresAt;
    creds.claudeAiOauth.expiresAt = 0;
    fs.writeFileSync(CLAUDE_CREDS, JSON.stringify(creds, null, 2));
    log("Set expiresAt=0 (was " + new Date(origExpiry).toISOString() + ")");

    // claude -p ping triggers the CLI, which refreshes the expired token
    execSync("claude -p ping", {
      timeout: 60000,
      stdio: "pipe",
      env: Object.assign({}, process.env, { HOME: process.env.HOME }),
    });
    log("Refresh triggered successfully");

    // Verify the token was actually refreshed
    var newCreds = readCreds();
    if (
      newCreds &&
      newCreds.claudeAiOauth &&
      newCreds.claudeAiOauth.expiresAt > Date.now()
    ) {
      log(
        "Token refreshed. New expiry: " +
          new Date(newCreds.claudeAiOauth.expiresAt).toISOString()
      );
      return true;
    } else {
      log("WARN: Token refresh may have failed — expiresAt not updated");
      // Restore original expiry so we don't break things
      if (creds.claudeAiOauth) {
        creds.claudeAiOauth.expiresAt = origExpiry;
        fs.writeFileSync(CLAUDE_CREDS, JSON.stringify(creds, null, 2));
        log("Restored original expiresAt");
      }
      return false;
    }
  } catch (e) {
    log("ERROR: Refresh failed: " + e.message);
    // Try to restore original expiry
    try {
      var fallback = readCreds();
      if (fallback && fallback.claudeAiOauth && fallback.claudeAiOauth.expiresAt === 0) {
        log("WARN: expiresAt stuck at 0, credentials may need manual repair");
      }
    } catch (_) {}
    return false;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
  var creds = readCreds();
  if (!creds) {
    log("ERROR: Claude credentials not found at " + CLAUDE_CREDS);
    process.exit(1);
  }

  var oauth = creds.claudeAiOauth;
  if (!oauth || !oauth.accessToken) {
    log("ERROR: No claudeAiOauth.accessToken in credentials");
    process.exit(1);
  }

  // Check if refresh token exists (required for automatic refresh)
  if (!oauth.refreshToken) {
    log(
      "WARN: No refreshToken in credentials. Token refresh won't work. " +
        "Run 'claude auth login' (not 'claude setup-token') to get refresh-capable credentials."
    );
  }

  var msLeft = oauth.expiresAt - Date.now();
  var hoursLeft = (msLeft / 3600000).toFixed(1);
  log("Access token expires in " + hoursLeft + "h (" + new Date(oauth.expiresAt).toISOString() + ")");

  // Force refresh if token expires within buffer
  if (msLeft < REFRESH_BUFFER_MS) {
    log("Token expires within " + (REFRESH_BUFFER_MS / 3600000) + "h buffer — refreshing...");
    if (!forceRefresh()) {
      log("ERROR: Could not refresh token. OpenClaw may lose API access soon.");
      // Continue anyway — sync whatever token we have
    }
    // Re-read credentials after refresh
    creds = readCreds();
    oauth = creds && creds.claudeAiOauth;
    if (!oauth || !oauth.accessToken) {
      log("ERROR: Credentials unreadable after refresh attempt");
      process.exit(1);
    }
  }

  // Read previous token from OpenClaw auth store
  var prevToken = null;
  var store;
  try {
    store = JSON.parse(fs.readFileSync(OPENCLAW_AUTH, "utf8"));
    if (store.profiles && store.profiles["anthropic:claude"]) {
      prevToken = store.profiles["anthropic:claude"].token;
    }
  } catch (e) {
    store = { version: 1, profiles: {} };
  }

  // Write token to OpenClaw auth-profiles.json
  store.profiles = store.profiles || {};
  store.profiles["anthropic:claude"] = {
    type: "token",
    provider: "anthropic",
    token: oauth.accessToken,
    expires: oauth.expiresAt,
  };
  store.lastGood = store.lastGood || {};
  store.lastGood.anthropic = "anthropic:claude";
  store.usageStats = store.usageStats || {};
  store.usageStats["anthropic:claude"] = {
    lastUsed: Date.now(),
    errorCount: 0,
  };

  // Clean up legacy profile names
  delete store.profiles["anthropic:oauth"];
  delete store.usageStats["anthropic:oauth"];

  fs.writeFileSync(OPENCLAW_AUTH, JSON.stringify(store, null, 2));

  var newMsLeft = (oauth.expiresAt - Date.now()) / 3600000;
  log("Token synced. Expires in " + newMsLeft.toFixed(1) + "h (" + new Date(oauth.expiresAt).toISOString() + ")");

  // Restart gateway only if token changed
  if (prevToken !== oauth.accessToken) {
    log("Token changed — restarting gateway...");
    try {
      execSync("cd " + COMPOSE_DIR + " && docker compose restart openclaw-gateway", {
        timeout: 60000,
        stdio: "pipe",
      });
      log("Gateway restarted successfully");
    } catch (e) {
      log("ERROR: Gateway restart failed: " + e.message);
    }
  } else {
    log("Token unchanged, no restart needed");
  }
}

main();
