# syntax=docker/dockerfile:1
FROM node:22-slim AS build
WORKDIR /app
# Toolchain in case better-sqlite3 has no prebuilt binary for the platform
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run typecheck

FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080 \
    DB_PATH=/data/opengym.db
# The server runs TypeScript through tsx (a devDependency), so node_modules is copied whole.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src
COPY package.json tsconfig.json ./
RUN mkdir -p /data && chown -R node:node /data /app
USER node
EXPOSE 8080
CMD ["node_modules/.bin/tsx", "src/server.ts"]
