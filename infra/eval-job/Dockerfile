# The coach evals as a container (Cloud Run Job). Build context: backend/convex.
# The job calls a model provider only. It never touches the app's database.
FROM node:22-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY convex.json ./
COPY functions ./functions
COPY evals ./evals
# Reports go to /reports: the bucket is mounted there. Extra flags come from the job's args.
ENTRYPOINT ["npx", "tsx", "evals/runner/main.ts", "--out", "/reports"]
