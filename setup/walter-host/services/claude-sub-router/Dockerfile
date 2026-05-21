FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — pinned to a specific version to close audit P1-01
# (no `@latest` in runtime-installed deps with execution context). The
# weekly upgrade.sh bumps this string deliberately after diffing the
# release notes; do not switch back to `@latest`.
RUN npm install -g @anthropic-ai/claude-code@2.1.146

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY server.js ./

# Auth dir — bind-mounted at runtime from host ~/.claude
# Use uid 1001 to avoid running as root.
RUN useradd -m -u 1001 -s /bin/bash appuser || true \
    && mkdir -p /home/appuser/.claude \
    && chown -R appuser:appuser /home/appuser /app

EXPOSE 1457

ENV PORT=1457
ENV HOME=/home/appuser

USER appuser

CMD ["node", "server.js"]
