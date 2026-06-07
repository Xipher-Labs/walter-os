# tag: node:22-slim
FROM node:22-slim@sha256:7af03b14a13c8cdd38e45058fd957bf00a72bbe17feac43b1c15a689c029c732

# Install system deps for curl (used by healthcheck) and codex CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Codex CLI globally. Pinned to a specific version to close
# audit P1-01 (no `@latest` in runtime-installed deps with execution
# context). Bump deliberately after diffing the release notes; do not
# switch back to `@latest`.
RUN npm install -g @openai/codex@0.132.0

WORKDIR /app

# Install production dependencies from the committed lockfile.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

# Copy server code
COPY server.js ./

# Auth volume mount point — bind-mounted from host's ~/.codex at runtime.
# Use uid 1001 to avoid running as root and to avoid colliding with the
# node image's built-in `node` user (uid 1000).
RUN useradd -m -u 1001 -s /bin/bash appuser || true \
    && mkdir -p /home/appuser/.codex \
    && chown -R appuser:appuser /home/appuser /app

EXPOSE 1456

ENV PORT=1456
ENV HOME=/home/appuser

USER appuser

CMD ["node", "server.js"]
