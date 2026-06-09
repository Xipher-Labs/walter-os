---
name: heygen-cli
description: Drive HeyGen's avatar-video generation REST API from the operator's terminal. Use this skill whenever the user asks to "generate a HeyGen video", "list HeyGen avatars", "make a talking-head avatar video", "poll a HeyGen job", or any HeyGen content task. Replaces the unmaintained `heygen-mcp@0.0.3` PyPI package (anonymous author, fails the minReleaseAge audit gate). SPENDS MONEY — per-second video generation. Confirmation required before any state-changing action.
---

# HeyGen REST API skill

HeyGen has no official CLI. The only third-party MCP on PyPI
(`heygen-mcp@0.0.3`) was published anonymously and would fail
`daily-supply-chain-audit`'s minReleaseAge + trust-score gates. This
skill instead drives HeyGen's REST API directly via `curl`, keeping
the supply-chain surface inside Walter-OS.

Closes issue #41 with the CLI + skill pattern Walter-OS already uses
for `hcloud`, `postgres-cli`, `forgejo-cli`, etc.

## Money-spending — operator confirmation REQUIRED

HeyGen bills per second of generated video. Every `heygen_generate_video`
call costs real money.

The approval-gate hook classifies paid HeyGen generation as the dedicated
`heygen-generate` category (see `hooks/approval-gate.sh::CATEGORY_MIN_TIER`).
That category requires a high-trust agent or an explicit operator-approved
path before paid generation can run. The guardrails are layered:

- **Code-level**: `_heygen_preflight` requires `HEYGEN_API_KEY`; an
  unauthenticated call exits 2 before any HTTP request.
- **Convention**: every state-changing call (`heygen_generate_video`,
  `heygen_generate_from_template`) MUST be preceded by explicit operator
  confirmation in chat per the multi-agent autonomy spec §7.1.
- **Approval gate**: paid functions and direct HeyGen generation endpoints
  are categorized as `heygen-generate`; read-only list/status functions are
  not blocked by this category.

Read-only functions (`heygen_list_avatars`, `heygen_get_video_status`,
`heygen_list_templates`, `heygen_list_voices`) are free and need no
confirmation.

## Setup

### 1. Provision API key

1. Open <https://app.heygen.com/settings?nav=Subscriptions>
2. Generate an API token (sidebar → API).
3. Store the secret in your secrets manager of choice (Infisical,
   Bitwarden/Vaultwarden, or macOS Keychain — depending on your
   operator overlay). Add `HEYGEN_API_KEY` to your shell environment
   via the manager-specific flow. Example:

```bash
# Infisical
infisical secrets set HEYGEN_API_KEY=hg_v2_... --project walter-shared
```

The current `walter-os secrets-pull` subcommand is the Bitwarden/
Vaultwarden bridge and is documented as DEPRECATED in `bin/walter-os`
— do NOT rely on it as the canonical sync path for new secrets.

4. Add `HEYGEN_API_KEY` to your env-allowlist if it's not already
   there (see the P1-09 env-loader docs):

```
# ~/.config/walter-os/overlay/env-allowlist.txt
HEYGEN_API_KEY
```

### 2. Source the function library + verify

The skill ships as a sourceable bash library, not as a CLI on PATH:

```bash
source "$WALTER_OS_HOME/skills/heygen-cli/heygen.sh"
heygen_list_avatars | jq '.data.avatars | length'
# → integer count of available avatars on your account
```

## Functions

The skill exports SIX bash functions sourceable from operator skills
and from `walter-os` subcommands. Each function reads `$HEYGEN_API_KEY`
for auth and uses `jq` for response parsing.

Read-only (free): `heygen_list_avatars`, `heygen_list_voices`,
`heygen_list_templates`, `heygen_get_video_status`.

State-changing (paid): `heygen_generate_video`,
`heygen_generate_from_template`.

### Read-only (free)

```bash
heygen_list_avatars
# GET /v2/avatars
# → JSON: list of avatar IDs + names + thumbnails

heygen_list_voices
# GET /v2/voices
# → JSON: list of voice IDs + language + sample URL

heygen_list_templates
# GET /v1/template.list
# → JSON: list of saved video templates (operator-defined)

heygen_get_video_status <video_id>
# GET /v1/video_status.get?video_id=...
# → JSON: status=processing|completed|failed, video_url if completed
```

### State-changing (paid — confirmation required)

```bash
heygen_generate_video --avatar <avatar_id> --voice <voice_id> \
                      --script "the words the avatar should say" \
                      [--background <hex>] [--ratio 16:9|9:16|1:1]
# POST /v2/video/generate
# → JSON: { video_id: "..." }
# Caller must poll heygen_get_video_status afterwards.

heygen_generate_from_template <template_id> --variables '{"key":"value"}'
# POST /v2/template/<id>/generate
# → JSON: { video_id: "..." }
```

### Stretch (not yet implemented — file an issue if needed)

- `heygen_clone_voice` — operator records 30s sample, HeyGen returns a voice id
- `heygen_create_avatar` — photo + name → custom avatar

Both endpoints exist but cost more and need legal review before
exposing them to autonomous agents.

## Workflow examples

### Generate a LinkedIn announcement video

```bash
walter_secrets_load
AVATAR_ID="$(heygen_list_avatars | jq -r '.data.avatars[] | select(.name | test("Spencer")) | .avatar_id')"
VOICE_ID="$(heygen_list_voices | jq -r '.data.voices[] | select(.language == "English (US)") | .voice_id' | head -1)"

# Confirm with operator before this line:
JOB="$(heygen_generate_video \
  --avatar "$AVATAR_ID" \
  --voice "$VOICE_ID" \
  --script "Walter-OS v0.4.0 ships today. Six P0 audit findings closed, founder-skills bundle complete, OpenRouter wired as a LiteLLM fallback. Link in bio." \
  --ratio 16:9 \
  --background "#0a0a0a")"
VIDEO_ID="$(echo "$JOB" | jq -r '.data.video_id')"

# Poll
while true; do
  STATUS="$(heygen_get_video_status "$VIDEO_ID")"
  state="$(echo "$STATUS" | jq -r '.data.status')"
  echo "Status: $state"
  [[ "$state" == "completed" ]] && { echo "$STATUS" | jq -r '.data.video_url'; break; }
  [[ "$state" == "failed" ]]    && { echo "$STATUS" | jq -r '.data.error'; exit 1; }
  sleep 10
done
```

### Compose with `content-writer` + `landing-page-fast`

The DevRel pipeline:

1. `content-writer` drafts the launch announcement text.
2. `heygen-cli` generates a talking-head version of the announcement.
3. `landing-page-fast` embeds the video on the launch landing page.
4. `marketing-video` (Remotion) generates a Twitter-format cutdown.

## Security + audit

- **Pinned API version**: all calls use `https://api.heygen.com/v2/...`
  (or `v1` where v2 is not yet available). Bump deliberately in this
  skill file, not transparently.
- **No fallback to plaintext key**: if `HEYGEN_API_KEY` is unset, every
  function exits 2 — set it via your secrets manager (Infisical /
  macOS Keychain) before sourcing.
- **No retries on 401**: a 401 means the key is wrong or revoked;
  bailing immediately avoids burning quota on a busted token.
- **No automatic retry on 429**: rate-limit responses are SURFACED but
  not auto-retried. The function reports the `retry_after` value from
  the response body (when present) and exits 4. Re-invocation is an
  explicit operator action — automatic retry on a paid endpoint is a
  recipe for runaway spend.
- **Fail-fast on `--ratio`**: invalid ratios exit 2 rather than
  silently falling back to 16:9. Paid endpoint should never bill the
  operator for a dimension they didn't ask for.
- **Approval-gate enforcement**: paid generation functions and direct
  generation endpoint calls are classified as `heygen-generate`, which
  requires high trust or explicit operator approval. Read-only list/status
  calls remain free to run.

## Why no MCP

`heygen-mcp@0.0.3` on PyPI:
- Anonymous author (`author: None` in PyPI metadata)
- Version 0.0.x — fails Walter-OS's typical minReleaseAge gate
- No GitHub repo linked

The `@heygenofficial/n8n-nodes-heygen-official@0.1.8` package IS from
HeyGen, but it's an n8n node, not an MCP. If HeyGen ships an official
MCP later (`@heygen/mcp` or similar), the right move is to evaluate it
and migrate this skill to thin wrappers around the MCP calls. Until
then, REST is the safer floor.

## Files

- `skills/heygen-cli/heygen.sh` — function library (sourced by the skill).
- `skills/heygen-cli/SKILL.md` — this file.

## Refs

- Issue #41 (the original ask)
- `docs/specs/p1-hardening-epic.md` (P1-07 audit-perimeter discipline)
- `hooks/approval-gate.sh` `CATEGORY_MIN_TIER` table
- HeyGen API docs: <https://docs.heygen.com/reference/getting-started>
