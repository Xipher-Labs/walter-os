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

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Copy built output
COPY --from=builder --chown=nextjs:nodejs /app/apps/control-tower/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/control-tower/.next/static ./apps/control-tower/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/control-tower/public ./apps/control-tower/public

USER nextjs

EXPOSE 3000

ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["node", "apps/control-tower/server.js"]
