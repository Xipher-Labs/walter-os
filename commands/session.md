---
description: Inspect or restart Walter-OS time-bounded session state.
argument-hint: status|restart
---

Manage Walter-OS time-bounded session state via the `walter-os` CLI.

## Usage

```bash
walter-os session $ARGUMENTS
```

If `$ARGUMENTS` is empty, run:

```bash
walter-os session status
```

If `$ARGUMENTS` is `restart`, run:

```bash
walter-os session restart
```

Use `restart` after the session-timeout hook blocks a prompt with `max-hours`,
`max-idle`, or invalid session state. It clears the current repo's session
state; the next prompt starts a fresh session.
