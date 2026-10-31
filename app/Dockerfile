# =====================================================================
# AEGIS - Next.js application image
#
# Multi-stage build:
#   deps    - install node_modules only (cached unless package.json changes)
#   builder - compile the Next.js production build
#   runner  - minimal runtime image, non-root, no build tooling
#
# The final image uses Next.js "standalone" output, which bundles only
# the server files and the node_modules actually reached at runtime.
# =====================================================================

# ---------- Stage 1: dependencies ----------
FROM node:22-alpine AS deps
WORKDIR /app

# Copy only the manifests first. Docker caches this layer, so
# node_modules is reinstalled only when a dependency actually changes,
# not on every source edit.
COPY package.json package-lock.json ./
RUN npm ci


# ---------- Stage 2: build ----------
FROM node:22-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# The build does not connect to the database. lib/db.js creates its pool
# lazily, so DATABASE_URL is only required when the server actually
# starts and handles a request.
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build


# ---------- Stage 3: runtime ----------
FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# Run as a non-root user. If the container is ever compromised, the
# process has no write access to its own application files.
RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 nextjs

# standalone output already contains the server and its dependencies
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]
