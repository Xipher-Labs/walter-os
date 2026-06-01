# Live Flow Unavailable in Walter-OS

The upstream Impeccable live-preview flow is **not bundled** in Walter-OS.

This vendored skill does not include the Node helper scripts that power live
mode (`live.mjs`, `live-poll.mjs`, `live-server.mjs`, `live-wrap.mjs`,
`live-accept.mjs`, `live-complete.mjs`, `detect-csp.mjs`, or related helpers).
Do not run `node {{scripts_path}}/*.mjs`, do not run `npx impeccable`, and do
not request elevated sandbox permissions for live mode. Those commands cannot
work from this repository tree.

## What to do instead

- Treat live mode as an upstream-only capability for this vendored copy.
- Use the normal browser/testing tools available in the current harness.
- Inspect the app manually, take screenshots where useful, patch source files
  directly, and re-run the project's own validation commands.
- Apply the design judgment from the other Impeccable reference files
  (`layout.md`, `typeset.md`, `colorize.md`, `interaction-design.md`,
  `animate.md`, `adapt.md`, `clarify.md`, and the command-specific references).

## What is intentionally not preserved here

The original live reference described a loopback helper server, injected browser
script, long-poll event loop, generated variant wrappers, accept/discard cleanup,
CSP detection, and durable live-session journal. All of that depends on the
un-vendored upstream Node CLI. Keeping those executable instructions in this
tree would route agents into missing tooling, so Walter-OS carries this explicit
unavailability note instead.

For the adoption decision and tooling boundary, see
`docs/specs/ux-skills-adoption.md`.
