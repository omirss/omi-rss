# omi-rss web (Neutron app: UI + API in one server; worker runs from the same image)
# Build from the repo root: podman build -f web/Dockerfile -t omi-rss-web web/
# (or let compose build it — the context is web/)

FROM node:22-alpine AS builder

# python3/make/g++: bcrypt compiles from source; sharp uses musl prebuilds
RUN apk add --no-cache python3 make g++

WORKDIR /app

# pnpm 10 matches the lockfile format (onlyBuiltDependencies)
RUN corepack enable && corepack prepare pnpm@10.26.1 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build:docker

FROM node:22-alpine AS runtime

# wget: container healthcheck probes /health
RUN apk add --no-cache wget

WORKDIR /app

# dist/          — server.mjs + SSR runtime + client statics (the prod artifact)
# node_modules/  — full tree: bcrypt/sharp natives, and vite + drizzle-kit
#                 (the worker entry runs via `neutron-ts worker`, which needs
#                 vite at runtime; migrations run drizzle-kit from the image)
# src/           — worker entry (src/worker.ts) + email templates (src/templates)
COPY --from=builder --chown=node:node /app/dist ./dist
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/src ./src
COPY --from=builder --chown=node:node /app/drizzle ./drizzle
COPY --from=builder --chown=node:node /app/package.json /app/pnpm-lock.yaml /app/neutron.config.ts /app/drizzle.config.mjs /app/tsconfig.json ./

RUN mkdir -p uploads/avatars && chown -R node:node uploads

USER node

ENV NODE_ENV=production \
    PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" || exit 1

CMD ["node", "dist/server.mjs"]
