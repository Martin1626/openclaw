---
name: noanon
description: "Bypass PII anonymization for the current message. Use when: user explicitly wants to send real names/addresses to the LLM for more accurate answers. The proxy will skip anonymization for this single request only."
user-invocable: false
metadata: { "openclaw": { "emoji": "🔓" } }
---

# No Anonymization (noanon)

Temporarily disable PII anonymization for the current request.

## When to Use

- User explicitly asks to skip anonymization for a specific question
- User needs precise answers about real people, addresses, or contacts
- User says "/noanon" followed by their question

## How It Works

The PII proxy automatically detects the `/noanon` marker in the user's message and skips all PII anonymization for that single API request. The marker is stripped from the message before sending to the LLM.

- Only affects the **current request** — next messages will be anonymized normally
- No commands to run — the proxy handles everything automatically

## Important

- Inform the user that this message will be sent to the cloud LLM **without anonymization** (real names, addresses, phone numbers will be visible to the LLM provider)
- Only use when the user explicitly requests it
