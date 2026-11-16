#!/usr/bin/env bash
# Deploys backend/api to Cloud Run with a Cloud Storage bucket mounted at /data.
# Usage: GCP_PROJECT=my-proj BUCKET=my-proj-opengym-data [GCLOUD_ACCOUNT=me@x.com] infra/deploy-cloud-run.sh
# Secrets must already exist in Secret Manager (names below); this script never takes secret values.
set -euo pipefail

: "${GCP_PROJECT:?set GCP_PROJECT}"
: "${BUCKET:?set BUCKET (globally unique bucket name)}"
GCP_REGION="${GCP_REGION:-europe-west1}"
SERVICE="${SERVICE:-opengym-api}"
AI_PROVIDER="${AI_PROVIDER:-anthropic}"          # anthropic | openai | deepseek | mock | none
AI_MODEL="${AI_MODEL:-}"                          # model id, required unless AI_PROVIDER is mock/none
TOKEN_SECRET="${TOKEN_SECRET:-opengym-app-token}" # Secret Manager secret holding APP_TOKEN
AI_KEY_SECRET="${AI_KEY_SECRET:-opengym-ai-key}"  # Secret Manager secret holding the provider API key

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/cloud-run-source-deploy/${SERVICE}:$(date +%Y%m%d%H%M%S)"

G=(gcloud --project "$GCP_PROJECT")
[ -n "${GCLOUD_ACCOUNT:-}" ] && G+=(--account "$GCLOUD_ACCOUNT")

echo "== Enable APIs"
"${G[@]}" services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  secretmanager.googleapis.com storage.googleapis.com

echo "== Artifact Registry repo"
"${G[@]}" artifacts repositories describe cloud-run-source-deploy --location "$GCP_REGION" >/dev/null 2>&1 ||
  "${G[@]}" artifacts repositories create cloud-run-source-deploy --repository-format docker --location "$GCP_REGION"

echo "== Bucket gs://$BUCKET"
"${G[@]}" storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 ||
  "${G[@]}" storage buckets create "gs://$BUCKET" --location "$GCP_REGION" --uniform-bucket-level-access

echo "== Check secrets exist"
NEED=("$TOKEN_SECRET")
[[ "$AI_PROVIDER" == "mock" || "$AI_PROVIDER" == "none" ]] || NEED+=("$AI_KEY_SECRET")
for s in "${NEED[@]}"; do
  "${G[@]}" secrets describe "$s" >/dev/null 2>&1 || { echo "Missing Secret Manager secret: $s" >&2; exit 1; }
done

echo "== Build image"
"${G[@]}" builds submit "$ROOT/backend/api" --tag "$IMAGE"

ENV_VARS="AI_PROVIDER=${AI_PROVIDER},DB_PATH=/data/opengym.db,SQLITE_JOURNAL_MODE=DELETE"
SECRETS="APP_TOKEN=${TOKEN_SECRET}:latest"
case "$AI_PROVIDER" in
  anthropic) KEY=ANTHROPIC ;; openai) KEY=OPENAI ;; deepseek) KEY=DEEPSEEK ;; *) KEY="" ;;
esac
if [ -n "$KEY" ]; then
  : "${AI_MODEL:?set AI_MODEL for provider $AI_PROVIDER}"
  ENV_VARS="${ENV_VARS},${KEY}_MODEL=${AI_MODEL}"
  SECRETS="${SECRETS},${KEY}_API_KEY=${AI_KEY_SECRET}:latest"
fi

echo "== Deploy $SERVICE"
# The runtime service account needs roles/secretmanager.secretAccessor on the secrets and
# roles/storage.objectUser on the bucket.
"${G[@]}" run deploy "$SERVICE" \
  --image "$IMAGE" --region "$GCP_REGION" \
  --execution-environment gen2 \
  --max-instances 1 --min-instances 0 \
  --allow-unauthenticated \
  --add-volume "name=data,type=cloud-storage,bucket=${BUCKET}" \
  --add-volume-mount "volume=data,mount-path=/data" \
  --set-env-vars "$ENV_VARS" \
  --set-secrets "$SECRETS"

URL="$("${G[@]}" run services describe "$SERVICE" --region "$GCP_REGION" --format 'value(status.url)')"
echo "Deployed: $URL  (health: $URL/v1/health)"
