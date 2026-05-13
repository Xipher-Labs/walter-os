# walter-os/wiki/

Operator's persistent, LLM-maintained knowledge base. Per
[Karpathy's "LLM Wiki" gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

## Files committed to the **public** walter-os repo

- `SCHEMA.md` — page-type contract, link rules, operations.
- `README.md` (this file) — what this directory is for.

## Files **NOT** committed to the public repo (gitignored)

Everything else under `wiki/` is private — `index.md`, `log.md`, all
content directories. They live in a separate private Forgejo repo:
`git.${WALTER_DOMAIN}/operator/walter-wiki`. See `SCHEMA.md` § Privacy.

## How it gets used

```
/ingest <url-or-path>      # slash command (Phase WK3)
walter-os wiki lint        # health check (Phase WK3)
```

## Where the cross-device sync lives

The wiki/ directory is **also** symlinked from
`~/sync/agent-memory/wiki/` so Syncthing replicates it cross-device.
The Forgejo private mirror is the authoritative source; Syncthing is
the everyday-fast layer.
