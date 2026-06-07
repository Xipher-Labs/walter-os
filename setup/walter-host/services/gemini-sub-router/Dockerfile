# tag: node:22-slim
FROM node:22-slim@sha256:7af03b14a13c8cdd38e45058fd957bf00a72bbe17feac43b1c15a689c029c732

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Gemini CLI from Google (https://github.com/google-gemini/gemini-cli)
# Pinned to a specific version to close audit P1-01 (no `@latest` in
# runtime-installed deps with execution context). Bump deliberately
# after diffing the release notes; do not switch back to `@latest`.
RUN npm install -g @google/gemini-cli@0.42.0

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts

COPY server.js ./

# Auth dir — bind-mounted at runtime from host ~/.gemini
# Use uid 1001 to avoid running as root.
RUN useradd -m -u 1001 -s /bin/bash appuser || true \
    && mkdir -p /home/appuser/.gemini \
    && chown -R appuser:appuser /home/appuser /app

EXPOSE 1458

ENV PORT=1458
ENV HOME=/home/appuser
# Disable terminal warnings in non-interactive runs.
ENV NO_COLOR=1
ENV TERM=dumb

USER appuser

CMD ["node", "server.js"]
