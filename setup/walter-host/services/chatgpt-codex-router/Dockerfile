FROM node:22-slim

# Install system deps for curl (used by healthcheck) and codex CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Codex CLI globally
RUN npm install -g @openai/codex@latest

WORKDIR /app

# Install production dependencies
COPY package.json ./
RUN npm install --omit=dev

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
