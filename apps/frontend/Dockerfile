# syntax=docker/dockerfile:1

# ---------- base ----------
    FROM node:24-alpine AS base
    ENV npm_config_store_dir=/pnpm/store
    # Compatibilidad con binarios nativos que Next.js puede necesitar en Alpine
    RUN apk add --no-cache libc6-compat && corepack enable
    WORKDIR /app
    
    # ---------- dev: lo que usa docker-compose.yml ----------
    FROM base AS dev
    COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
    COPY apps/backend/package.json apps/backend/
    COPY apps/frontend/package.json apps/frontend/
    RUN --mount=type=cache,target=/pnpm/store \
        pnpm install --frozen-lockfile --filter frontend...
    COPY apps/frontend apps/frontend
    WORKDIR /app/apps/frontend
    CMD ["pnpm", "run", "dev"]
    
    # ---------- build ----------
    FROM dev AS build
    # NEXT_PUBLIC_* se "hornea" en el JS del cliente al compilar: debe venir como build arg
    ARG NEXT_PUBLIC_API_URL
    ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
        NEXT_TELEMETRY_DISABLED=1
    RUN pnpm run build
    
    # ---------- runtime: solo el output standalone ----------
    FROM node:24-alpine AS runtime
    ENV NODE_ENV=production \
        NEXT_TELEMETRY_DISABLED=1 \
        PORT=3000 \
        HOSTNAME=0.0.0.0
    WORKDIR /app
    COPY --from=build --chown=node:node /app/apps/frontend/.next/standalone ./
    COPY --from=build --chown=node:node /app/apps/frontend/.next/static ./apps/frontend/.next/static
    COPY --from=build --chown=node:node /app/apps/frontend/public ./apps/frontend/public
    USER node
    EXPOSE 3000
    CMD ["node", "apps/frontend/server.js"]
    