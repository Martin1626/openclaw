import { upsertAuthProfile } from "../agents/auth-profiles.js";
import { normalizeApiKeyInput, validateApiKeyInput } from "./auth-choice.api-key.js";
import {
  buildAnthropicAuthorizeUrl,
  exchangeAnthropicCode,
  generateAnthropicPkce,
  parseAnthropicOAuthCallback,
} from "../providers/anthropic-oauth.js";
import {
  normalizeSecretInputModeInput,
  ensureApiKeyFromOptionEnvOrPrompt,
} from "./auth-choice.apply-helpers.js";
import type { ApplyAuthChoiceParams, ApplyAuthChoiceResult } from "./auth-choice.apply.js";
import { buildTokenProfileId, validateAnthropicSetupToken } from "./auth-token.js";
import { applyAgentDefaultModelPrimary } from "./onboard-auth.config-shared.js";
import { applyAuthProfileConfig, setAnthropicApiKey } from "./onboard-auth.js";

const DEFAULT_ANTHROPIC_MODEL = "anthropic/claude-sonnet-4-6";

export async function applyAuthChoiceAnthropic(
  params: ApplyAuthChoiceParams,
): Promise<ApplyAuthChoiceResult | null> {
  if (params.authChoice === "anthropic-oauth") {
    let nextConfig = params.config;
    const pkce = generateAnthropicPkce();
    const authorizeUrl = buildAnthropicAuthorizeUrl(pkce);

    await params.prompter.note(
      [
        "Open this URL in your browser to sign in with your Claude account:",
        "",
        authorizeUrl,
        "",
        "After signing in, you will be redirected to a page with an authorization code.",
        "Copy the full redirect URL and paste it below.",
      ].join("\n"),
      "Anthropic OAuth",
    );

    const callbackInput = await params.prompter.text({
      message: "Paste the redirect URL",
      validate: (value) => {
        const parsed = parseAnthropicOAuthCallback(String(value ?? ""), pkce.verifier);
        if ("error" in parsed) {
          return parsed.error;
        }
        return undefined;
      },
    });

    const parsed = parseAnthropicOAuthCallback(String(callbackInput ?? ""), pkce.verifier);
    if ("error" in parsed) {
      throw new Error(parsed.error);
    }

    const credentials = await exchangeAnthropicCode({
      code: parsed.code,
      codeVerifier: pkce.verifier,
    });

    const provider = "anthropic";
    const profileId = `${provider}:oauth`;

    upsertAuthProfile({
      profileId,
      agentDir: params.agentDir,
      credential: {
        type: "oauth",
        provider,
        access: credentials.access,
        refresh: credentials.refresh,
        expires: credentials.expires,
      },
    });

    nextConfig = applyAuthProfileConfig(nextConfig, {
      profileId,
      provider,
      mode: "oauth",
    });
    if (params.setDefaultModel) {
      nextConfig = applyAgentDefaultModelPrimary(nextConfig, DEFAULT_ANTHROPIC_MODEL);
    }
    return { config: nextConfig };
  }

  const requestedSecretInputMode = normalizeSecretInputModeInput(params.opts?.secretInputMode);
  if (
    params.authChoice === "setup-token" ||
    params.authChoice === "oauth" ||
    params.authChoice === "token"
  ) {
    let nextConfig = params.config;
    await params.prompter.note(
      ["Run `claude setup-token` in your terminal.", "Then paste the generated token below."].join(
        "\n",
      ),
      "Anthropic setup-token",
    );

    const tokenRaw = await params.prompter.text({
      message: "Paste Anthropic setup-token",
      validate: (value) => validateAnthropicSetupToken(String(value ?? "")),
    });
    const token = String(tokenRaw ?? "").trim();

    const profileNameRaw = await params.prompter.text({
      message: "Token name (blank = default)",
      placeholder: "default",
    });
    const provider = "anthropic";
    const namedProfileId = buildTokenProfileId({
      provider,
      name: String(profileNameRaw ?? ""),
    });

    upsertAuthProfile({
      profileId: namedProfileId,
      agentDir: params.agentDir,
      credential: {
        type: "token",
        provider,
        token,
      },
    });

    nextConfig = applyAuthProfileConfig(nextConfig, {
      profileId: namedProfileId,
      provider,
      mode: "token",
    });
    if (params.setDefaultModel) {
      nextConfig = applyAgentDefaultModelPrimary(nextConfig, DEFAULT_ANTHROPIC_MODEL);
    }
    return { config: nextConfig };
  }

  if (params.authChoice === "apiKey") {
    if (params.opts?.tokenProvider && params.opts.tokenProvider !== "anthropic") {
      return null;
    }

    let nextConfig = params.config;
    await ensureApiKeyFromOptionEnvOrPrompt({
      token: params.opts?.token,
      tokenProvider: params.opts?.tokenProvider ?? "anthropic",
      secretInputMode: requestedSecretInputMode,
      config: nextConfig,
      expectedProviders: ["anthropic"],
      provider: "anthropic",
      envLabel: "ANTHROPIC_API_KEY",
      promptMessage: "Enter Anthropic API key",
      normalize: normalizeApiKeyInput,
      validate: validateApiKeyInput,
      prompter: params.prompter,
      setCredential: async (apiKey, mode) =>
        setAnthropicApiKey(apiKey, params.agentDir, { secretInputMode: mode }),
    });
    nextConfig = applyAuthProfileConfig(nextConfig, {
      profileId: "anthropic:default",
      provider: "anthropic",
      mode: "api_key",
    });
    if (params.setDefaultModel) {
      nextConfig = applyAgentDefaultModelPrimary(nextConfig, DEFAULT_ANTHROPIC_MODEL);
    }
    return { config: nextConfig };
  }

  return null;
}
