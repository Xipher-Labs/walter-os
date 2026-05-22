# Multi-stage Dockerfile for Walter Council Control Tower
# Stage 1: builder
FROM node:22-alpine AS builder

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
FROM node:22-alpine AS runner

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

# CT runs as root (NOT the previous nextjs UID 1001) so it can write to
# `/root/.config/walter-os/mode.json` via the host bind mount (#176).
# The host directory is mode 700 root:root by default; non-root container
# users cannot write to it without an operator-side chown deployment step,
# and Walter-VM is a single-operator private VM behind Tailscale + CF
# Access + admin-token gate — the security trade-off of running as root
# inside this container is acceptable for the simplification.
# Adopters running CT in a multi-tenant context should bake their own
# Dockerfile with a non-root user + chowned host path.

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
# WALTER_OS_HOME is where bin/walter-os looks for its libs (VERSION,
# scripts/agents/lib/mode.sh). It is NOT the place mode.json is written —
# that goes to $WALTER_CONFIG (default $HOME/.config/walter-os, which is
# mounted RW from the host at /root/.config/walter-os, see compose.yml).
ENV WALTER_OS_HOME=/opt/walter-os
ENV WALTER_CONFIG=/root/.config/walter-os

CMD ["node", "apps/control-tower/server.js"]
