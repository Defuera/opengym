#!/usr/bin/env bash
# Builds and deploys the coach evals as a Cloud Run Job. Reports land in a Cloud Storage bucket.
# Usage: GCP_PROJECT=gym-days-app [GCLOUD_ACCOUNT=me@x.com] infra/deploy-eval-job.sh
# The key must already be in Secret Manager (name below); this script never takes a secret value.
set -euo pipefail

: "${GCP_PROJECT:?set GCP_PROJECT}"
GCP_REGION="${GCP_REGION:-europe-west1}"
JOB="${JOB:-coach-evals}"
BUCKET="${BUCKET:-${GCP_PROJECT}-eval-reports}"
KEY_SECRET="${KEY_SECRET:-openrouter-api-key}"          # Secret Manager secret holding the OpenRouter key
BASE_URL="${BASE_URL:-https://openrouter.ai/api}"        # OpenRouter speaks the OpenAI protocol
MODEL="${MODEL:?set MODEL (the default model, as the provider names it, e.g. vendor/model)}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/cloud-run-source-deploy/${JOB}:$(date +%Y%m%d%H%M%S)"

G=(gcloud --project "$GCP_PROJECT")
[ -n "${GCLOUD_ACCOUNT:-}" ] && G+=(--account "$GCLOUD_ACCOUNT")

echo "== Enable APIs"
"${G[@]}" services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com storage.googleapis.com

echo "== Check the secret and the bucket"
"${G[@]}" secrets describe "$KEY_SECRET" >/dev/null 2>&1 || { echo "Missing Secret Manager secret: $KEY_SECRET" >&2; exit 1; }
"${G[@]}" storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 ||
  "${G[@]}" storage buckets create "gs://$BUCKET" --location "$GCP_REGION" --uniform-bucket-level-access

echo "== Build $IMAGE"
# The Dockerfile lives in infra/; the build context is backend/convex, so a copy goes in for the build.
cp "$ROOT/infra/eval-job/Dockerfile" "$ROOT/backend/convex/eval-job.Dockerfile"
trap 'rm -f "$ROOT/backend/convex/eval-job.Dockerfile"' EXIT
"${G[@]}" builds submit "$ROOT/backend/convex" --config "$ROOT/infra/eval-job/cloudbuild.yaml" --substitutions "_IMAGE=$IMAGE"

echo "== Deploy job $JOB"
# The runtime service account needs roles/secretmanager.secretAccessor on the secret and
# roles/storage.objectUser on the bucket.
"${G[@]}" run jobs deploy "$JOB" \
  --image "$IMAGE" --region "$GCP_REGION" \
  --max-retries 0 --task-timeout 30m --memory 1Gi \
  --add-volume "name=reports,type=cloud-storage,bucket=${BUCKET}" \
  --add-volume-mount "volume=reports,mount-path=/reports" \
  --set-env-vars "AI_PROVIDER=openai,OPENAI_BASE_URL=${BASE_URL},OPENAI_MODEL=${MODEL}" \
  --set-secrets "OPENAI_API_KEY=${KEY_SECRET}:latest"

echo "Deployed. Run it with infra/run-evals.sh. Reports: gs://$BUCKET"
