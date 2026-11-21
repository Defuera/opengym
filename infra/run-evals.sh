#!/usr/bin/env bash
# Starts one run of the coach evals in the cloud and waits for it. Reports land in the bucket.
# Usage: GCP_PROJECT=gym-days-app [EVAL_MODEL=vendor/model] [GCLOUD_ACCOUNT=me@x.com] infra/run-evals.sh [runner flags]
# Example: EVAL_MODEL=anthropic/some-model infra/run-evals.sh --job build_session --samples 3
set -euo pipefail

: "${GCP_PROJECT:?set GCP_PROJECT}"
GCP_REGION="${GCP_REGION:-europe-west1}"
JOB="${JOB:-coach-evals}"

G=(gcloud --project "$GCP_PROJECT")
[ -n "${GCLOUD_ACCOUNT:-}" ] && G+=(--account "$GCLOUD_ACCOUNT")

EXTRA=()
[ -n "${EVAL_MODEL:-}" ] && EXTRA+=(--update-env-vars "EVAL_MODEL=${EVAL_MODEL}")
# The image's entrypoint already has "--out /reports"; the flags given here are added after it.
if [ "$#" -gt 0 ]; then
  IFS=, ; EXTRA+=("--args=$*") ; unset IFS
fi
"${G[@]}" run jobs execute "$JOB" --region "$GCP_REGION" --wait "${EXTRA[@]}"
