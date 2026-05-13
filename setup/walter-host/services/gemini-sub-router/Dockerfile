FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Gemini CLI from Google (https://github.com/google-gemini/gemini-cli)
RUN npm install -g @google/gemini-cli@latest

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

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
