# syntax=docker/dockerfile:1

# ---------- base ----------
    FROM node:24-alpine AS base
    ENV npm_config_store_dir=/pnpm/store
    RUN corepack enable
    WORKDIR /app
    
    # ---------- dev: lo que usa docker-compose.yml (hot reload con volúmenes) ----------
    FROM base AS dev
    # Solo manifiestos: esta capa se cachea mientras no cambien las dependencias
    COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
    COPY apps/backend/package.json apps/backend/
    COPY apps/frontend/package.json apps/frontend/
    RUN --mount=type=cache,target=/pnpm/store \
        pnpm install --frozen-lockfile --filter backend...
    COPY apps/backend apps/backend
    WORKDIR /app/apps/backend
    CMD ["pnpm", "run", "start:dev"]
    
    # ---------- build: compila y prepara solo las deps de producción ----------
    FROM dev AS build
    WORKDIR /app
    RUN pnpm --filter backend build
    RUN --mount=type=cache,target=/pnpm/store \
        pnpm --filter backend deploy --prod /prod/backend
    
    # ---------- runtime: imagen final, mínima ----------
    FROM node:24-alpine AS runtime
    ENV NODE_ENV=production
    WORKDIR /app
    COPY --from=build --chown=node:node /prod/backend/node_modules ./node_modules
    COPY --from=build --chown=node:node /prod/backend/package.json ./package.json
    # dist se copia explícitamente: deploy puede omitirlo si está en .gitignore
    COPY --from=build --chown=node:node /app/apps/backend/dist ./dist
    USER node
    EXPOSE 3000
    CMD ["node", "dist/main.js"]
    