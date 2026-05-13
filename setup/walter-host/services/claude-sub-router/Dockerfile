FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — pinned to latest on build. The weekly upgrade.sh
# rebuilds with --no-cache to pull a fresh version.
RUN npm install -g @anthropic-ai/claude-code@latest

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
