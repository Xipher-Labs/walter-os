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
call costs real money. The `approval-gate.sh` hook treats all
state-changing HeyGen calls as confirmation-required (operator must
type "go" in chat per the multi-agent autonomy spec §7.1).

Read-only endpoints (`list_avatars`, `get_video_status`,
`list_templates`) are free and need no confirmation.

## Setup

### 1. Provision API key

1. Open <https://app.heygen.com/settings?nav=Subscriptions>
2. Generate an API token (sidebar → API).
3. Store in Infisical:

```bash
infisical secrets set HEYGEN_API_KEY=hg_v2_... --project walter-shared
```

4. Pull into the local env via the standard secrets flow:

```bash
walter-os secrets-pull
# HEYGEN_API_KEY is now in $secret_env
```

`HEYGEN_API_KEY` is **already in the `WALTER_ENV_ALLOWLIST` extension
list** at `~/.config/walter-os/overlay/env-allowlist.txt` — see the
P1-09 env-loader docs.

### 2. Verify

```bash
heygen_list_avatars | jq '.data.avatars | length'
# → integer count of available avatars on your account
```

## Functions

The skill exports four bash functions sourceable from operator skills
and from `walter-os` subcommands. Each function defaults to
`$HEYGEN_API_KEY` for auth and uses `jq` for response parsing.

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
  function exits 2 with `heygen-cli: HEYGEN_API_KEY not set — run walter-os secrets-pull`.
- **No retries on 401**: a 401 means the key is wrong or revoked;
  bailing immediately avoids burning quota on a busted token.
- **Rate-limit awareness**: HeyGen returns 429 with `Retry-After`; the
  functions honor it and exit 4 if retry-after > 60 (operator decides
  whether to wait).
- **Audit-gate integration**: `state-changing` calls are listed in
  `hooks/approval-gate.sh` under `CATEGORY_MIN_TIER` as
  `heygen-generate=high` so any agent running with `tier=medium`
  cannot trigger them without the operator's explicit go.

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
