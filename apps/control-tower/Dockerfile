# Multi-stage Dockerfile for Walter Council Control Tower
# Stage 1: builder
# tag: node:22-alpine
FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920 AS builder

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy workspace package files first for better Docker layer caching. The build
# context is the repo root so the image uses the canonical monorepo lockfile and
# pnpm-workspace.yaml overrides.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/control-tower/package.json ./apps/control-tower/package.json

# Install deps without running build scripts (sharp)
RUN pnpm install --frozen-lockfile --ignore-scripts

# Copy source
COPY apps/control-tower ./apps/control-tower

# Build Next.js
WORKDIR /app/apps/control-tower
RUN pnpm build

# Stage 2: runner
# tag: node:22-alpine
FROM node:22-alpine@sha256:968df39aedcea65eeb078fb336ed7191baf48f972b4479711397108be0966920 AS runner

WORKDIR /app

ENV NODE_ENV=production

# Council toggle (#176) needs bash + jq + the walter-os CLI to call
# `walter-os mode consensus on|off` via execFile from /api/mode.
# node:22-alpine is BusyBox-based; install bash + jq explicitly.
RUN apk add --no-cache bash jq

# Copy built output
COPY --from=builder /app/apps/control-tower/.next/standalone ./
COPY --from=builder /app/apps/control-tower/.next/static ./apps/control-tower/.next/static
COPY --from=builder /app/apps/control-tower/public ./apps/control-tower/public

# Bundle the walter-os CLI + its mode-management library so the Council
# toggle (#176) can call `walter-os mode consensus on|off` at runtime.
# WALTER_OS_HOME points at /opt/walter-os; bin/walter-os sources
# scripts/agents/lib/mode.sh from it. Closes #176 (Council toggle fails
# when CLI is missing).
COPY bin/walter-os /usr/local/bin/walter-os
COPY scripts/agents/lib/mode.sh /opt/walter-os/scripts/agents/lib/mode.sh
COPY VERSION /opt/walter-os/VERSION
RUN chmod +x /usr/local/bin/walter-os

# Keep Control Tower's mutable Walter state separate from the operator's
# private config directory. The Council toggle only needs mode.json, so the
# container writes to a dedicated volume and can run as the unprivileged
# node user instead of mounting /root/.config/walter-os.
RUN mkdir -p /var/lib/walter-os/control-tower \
  && chown -R node:node /var/lib/walter-os/control-tower

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
# WALTER_OS_HOME is where bin/walter-os looks for its libs (VERSION,
# scripts/agents/lib/mode.sh). Mutable runtime state is intentionally
# constrained to the Control Tower state volume.
ENV WALTER_OS_HOME=/opt/walter-os
# Both env vars must point at the same place — the route handler in
# apps/control-tower/app/api/mode/route.ts reads `WALTER_CONFIG_DIR`
# while bin/walter-os + scripts/agents/lib/mode.sh read `WALTER_CONFIG`.
# Setting both pins them together so an operator override of one
# doesn't silently desync the read/write paths (Copilot R1 #194).
ENV WALTER_CONFIG=/var/lib/walter-os/control-tower
ENV WALTER_CONFIG_DIR=/var/lib/walter-os/control-tower

USER node

CMD ["node", "apps/control-tower/server.js"]
