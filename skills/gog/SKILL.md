---
name: gog
description: Google Workspace CLI for Gmail, Calendar, Drive, Contacts, Sheets, and Docs.
homepage: https://gogcli.sh
metadata:
  {
    "openclaw":
      {
        "emoji": "🎮",
        "requires": { "bins": ["gog"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "steipete/tap/gogcli",
              "bins": ["gog"],
              "label": "Install gog (brew)",
            },
          ],
      },
  }
---

# gog

## ⚠️ CRITICAL: Account Configuration — READ FIRST!

There are TWO separate Google accounts with DIFFERENT purposes and DIFFERENT OAuth clients. Using the wrong account WILL fail with auth errors.

| Service    | Account                      | OAuth client flag | Example |
|------------|------------------------------|-------------------|---------|
| **Calendar** | `tomis.martin@gmail.com`   | *(none, default)* | `gog calendar events primary --account tomis.martin@gmail.com` |
| **Gmail**    | `claudie.tomis@gmail.com`  | `--client claudie` | `gog gmail search "newer_than:7d" --account claudie.tomis@gmail.com --client claudie` |

### Rules (MUST follow):
1. **Gmail** commands → ALWAYS use `--account claudie.tomis@gmail.com --client claudie`
2. **Calendar** commands → ALWAYS use `--account tomis.martin@gmail.com` (no --client flag)
3. **NEVER** use `tomis.martin@gmail.com` for Gmail — that account has NO Gmail permissions
4. **NEVER** use `claudie.tomis@gmail.com` for Calendar — that account has NO Calendar permissions
5. **NEVER** omit `--client claudie` when using `claudie.tomis@gmail.com` — it will use the wrong OAuth app and fail

---

Use `gog` for Gmail/Calendar/Drive/Contacts/Sheets/Docs. Requires OAuth setup.

Setup (once)

- `gog auth credentials /path/to/client_secret.json`
- `gog auth add you@gmail.com --services gmail,calendar,drive,contacts,docs,sheets`
- `gog auth list`

Common commands

- Gmail search: `gog gmail search 'newer_than:7d' --max 10 --account claudie.tomis@gmail.com --client claudie`
- Gmail messages search (per email, ignores threading): `gog gmail messages search "in:inbox from:ryanair.com" --max 20 --account claudie.tomis@gmail.com --client claudie`
- Gmail send (plain): `gog gmail send --to a@b.com --subject "Hi" --body "Hello" --account claudie.tomis@gmail.com --client claudie`
- Gmail send (multi-line): `gog gmail send --to a@b.com --subject "Hi" --body-file ./message.txt --account claudie.tomis@gmail.com --client claudie`
- Gmail send (stdin): `gog gmail send --to a@b.com --subject "Hi" --body-file - --account claudie.tomis@gmail.com --client claudie`
- Gmail send (HTML): `gog gmail send --to a@b.com --subject "Hi" --body-html "<p>Hello</p>" --account claudie.tomis@gmail.com --client claudie`
- Gmail draft: `gog gmail drafts create --to a@b.com --subject "Hi" --body-file ./message.txt --account claudie.tomis@gmail.com --client claudie`
- Gmail send draft: `gog gmail drafts send <draftId> --account claudie.tomis@gmail.com --client claudie`
- Gmail reply: `gog gmail send --to a@b.com --subject "Re: Hi" --body "Reply" --reply-to-message-id <msgId> --account claudie.tomis@gmail.com --client claudie`
- Calendar list events: `gog calendar events <calendarId> --from <iso> --to <iso> --account tomis.martin@gmail.com`
- Calendar create event: `gog calendar create <calendarId> --summary "Title" --from <iso> --to <iso> --account tomis.martin@gmail.com`
- Calendar create with color: `gog calendar create <calendarId> --summary "Title" --from <iso> --to <iso> --event-color 7 --account tomis.martin@gmail.com`
- Calendar update event: `gog calendar update <calendarId> <eventId> --summary "New Title" --event-color 4 --account tomis.martin@gmail.com`
- Calendar show colors: `gog calendar colors`
- Drive search: `gog drive search "query" --max 10`
- Contacts: `gog contacts list --max 20`
- Sheets get: `gog sheets get <sheetId> "Tab!A1:D10" --json`
- Sheets update: `gog sheets update <sheetId> "Tab!A1:B2" --values-json '[["A","B"],["1","2"]]' --input USER_ENTERED`
- Sheets append: `gog sheets append <sheetId> "Tab!A:C" --values-json '[["x","y","z"]]' --insert INSERT_ROWS`
- Sheets clear: `gog sheets clear <sheetId> "Tab!A2:Z"`
- Sheets metadata: `gog sheets metadata <sheetId> --json`
- Docs export: `gog docs export <docId> --format txt --out /tmp/doc.txt`
- Docs cat: `gog docs cat <docId>`

Calendar Colors

- Use `gog calendar colors` to see all available event colors (IDs 1-11)
- Add colors to events with `--event-color <id>` flag
- Event color IDs (from `gog calendar colors` output):
  - 1: #a4bdfc
  - 2: #7ae7bf
  - 3: #dbadff
  - 4: #ff887c
  - 5: #fbd75b
  - 6: #ffb878
  - 7: #46d6db
  - 8: #e1e1e1
  - 9: #5484ed
  - 10: #51b749
  - 11: #dc2127

Email Formatting

- Prefer plain text. Use `--body-file` for multi-paragraph messages (or `--body-file -` for stdin).
- Same `--body-file` pattern works for drafts and replies.
- `--body` does not unescape `\n`. If you need inline newlines, use a heredoc or `$'Line 1\n\nLine 2'`.
- Use `--body-html` only when you need rich formatting.
- HTML tags: `<p>` for paragraphs, `<br>` for line breaks, `<strong>` for bold, `<em>` for italic, `<a href="url">` for links, `<ul>`/`<li>` for lists.
- Example (plain text via stdin):

  ```bash
  gog gmail send --to recipient@example.com \
    --subject "Meeting Follow-up" \
    --account claudie.tomis@gmail.com --client claudie \
    --body-file - <<'EOF'
  Hi Name,

  Thanks for meeting today. Next steps:
  - Item one
  - Item two

  Best regards,
  Your Name
  EOF
  ```

- Example (HTML list):
  ```bash
  gog gmail send --to recipient@example.com \
    --subject "Meeting Follow-up" \
    --account claudie.tomis@gmail.com --client claudie \
    --body-html "<p>Hi Name,</p><p>Thanks for meeting today. Here are the next steps:</p><ul><li>Item one</li><li>Item two</li></ul><p>Best regards,<br>Your Name</p>"
  ```

Notes

- For scripting, prefer `--json` plus `--no-input`.
- Sheets values can be passed via `--values-json` (recommended) or as inline rows.
- Docs supports export/cat/copy. In-place edits require a Docs API client (not in gog).
- Confirm before sending mail or creating events.
- `gog gmail search` returns one row per thread; use `gog gmail messages search` when you need every individual email returned separately.
