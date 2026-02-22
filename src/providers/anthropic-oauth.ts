import { createHash, randomBytes } from "node:crypto";
import type { OAuthCredentials } from "@mariozechner/pi-ai";

export const ANTHROPIC_OAUTH_CONFIG = {
  clientId: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  authorizeUrl: "https://claude.ai/oauth/authorize",
  tokenUrl: "https://console.anthropic.com/v1/oauth/token",
  redirectUri: "https://console.anthropic.com/oauth/code/callback",
  scopes: "org:create_api_key user:profile user:inference",
} as const;

const DEFAULT_EXPIRES_BUFFER_MS = 5 * 60 * 1000;

export type AnthropicPkce = { verifier: string; challenge: string };

export function generateAnthropicPkce(): AnthropicPkce {
  const verifier = randomBytes(32).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  return { verifier, challenge };
}

export function buildAnthropicAuthorizeUrl(pkce: AnthropicPkce): string {
  const params = new URLSearchParams({
    code: "true",
    client_id: ANTHROPIC_OAUTH_CONFIG.clientId,
    response_type: "code",
    redirect_uri: ANTHROPIC_OAUTH_CONFIG.redirectUri,
    scope: ANTHROPIC_OAUTH_CONFIG.scopes,
    code_challenge: pkce.challenge,
    code_challenge_method: "S256",
    state: pkce.verifier,
  });
  return `${ANTHROPIC_OAUTH_CONFIG.authorizeUrl}?${params}`;
}

export function parseAnthropicOAuthCallback(
  input: string,
  expectedState: string,
): { code: string; state: string } | { error: string } {
  const trimmed = input.trim();
  if (!trimmed) {
    return { error: "No input provided" };
  }

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    if (
      !/\s/.test(trimmed) &&
      !trimmed.includes("://") &&
      !trimmed.includes("?") &&
      !trimmed.includes("=")
    ) {
      return { error: "Paste the full redirect URL (must include code + state)." };
    }
    const qs = trimmed.startsWith("?") ? trimmed : `?${trimmed}`;
    try {
      url = new URL(`http://localhost/${qs}`);
    } catch {
      return { error: "Paste the full redirect URL (must include code + state)." };
    }
  }

  const code = url.searchParams.get("code")?.trim();
  const state = url.searchParams.get("state")?.trim();
  if (!code) {
    return { error: "Missing 'code' parameter in URL" };
  }
  if (!state) {
    return { error: "Missing 'state' parameter. Paste the full redirect URL." };
  }
  if (state !== expectedState) {
    return { error: "OAuth state mismatch - possible CSRF attack. Please retry login." };
  }
  return { code, state };
}

function coerceExpiresAt(expiresInSeconds: number, now: number): number {
  const value = now + Math.max(0, Math.floor(expiresInSeconds)) * 1000 - DEFAULT_EXPIRES_BUFFER_MS;
  return Math.max(value, now + 30_000);
}

export async function exchangeAnthropicCode(params: {
  code: string;
  codeVerifier: string;
  fetchFn?: typeof fetch;
  now?: number;
}): Promise<OAuthCredentials> {
  const fetchFn = params.fetchFn ?? fetch;
  const now = params.now ?? Date.now();

  const response = await fetchFn(ANTHROPIC_OAUTH_CONFIG.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "authorization_code",
      client_id: ANTHROPIC_OAUTH_CONFIG.clientId,
      code: params.code,
      state: params.codeVerifier,
      redirect_uri: ANTHROPIC_OAUTH_CONFIG.redirectUri,
      code_verifier: params.codeVerifier,
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Anthropic token exchange failed (${response.status}): ${text}`);
  }

  const data = (await response.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  };

  const access = data.access_token?.trim();
  const refresh = data.refresh_token?.trim();
  const expiresIn = data.expires_in ?? 0;

  if (!access) {
    throw new Error("Anthropic token exchange returned no access_token");
  }
  if (!refresh) {
    throw new Error("Anthropic token exchange returned no refresh_token");
  }

  return {
    access,
    refresh,
    expires: coerceExpiresAt(expiresIn, now),
  } as unknown as OAuthCredentials;
}

export async function refreshAnthropicTokens(params: {
  credential: OAuthCredentials;
  fetchFn?: typeof fetch;
  now?: number;
}): Promise<OAuthCredentials> {
  const fetchFn = params.fetchFn ?? fetch;
  const now = params.now ?? Date.now();

  const refreshToken = params.credential.refresh?.trim();
  if (!refreshToken) {
    throw new Error("Anthropic OAuth credential is missing refresh token");
  }

  const response = await fetchFn(ANTHROPIC_OAUTH_CONFIG.tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      grant_type: "refresh_token",
      client_id: ANTHROPIC_OAUTH_CONFIG.clientId,
      refresh_token: refreshToken,
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Anthropic token refresh failed (${response.status}): ${text}`);
  }

  const data = (await response.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
  };
  const access = data.access_token?.trim();
  const newRefresh = data.refresh_token?.trim();
  const expiresIn = data.expires_in ?? 0;

  if (!access) {
    throw new Error("Anthropic token refresh returned no access_token");
  }

  return {
    ...params.credential,
    access,
    refresh: newRefresh || refreshToken,
    expires: coerceExpiresAt(expiresIn, now),
  } as unknown as OAuthCredentials;
}
