# /session

Manage Walter-OS time-bounded session state.

## Usage

```bash
walter-os session status
walter-os session restart
```

Use `restart` after the session-timeout hook blocks a prompt with
`max-hours`, `max-idle`, or invalid session state. The command clears the
current repo's session state; the next prompt starts a fresh session.

`status` prints the current session state JSON for the current repo.
