#!/usr/bin/env bash
# Usage: BASE_URL=http://localhost:8787 TOKEN=xxx scripts/smoke.sh
# Starts nothing; talks to a running server.
set -euo pipefail
: "${BASE_URL:?set BASE_URL}"
: "${TOKEN:?set TOKEN}"

AUTH=(-H "Authorization: Bearer $TOKEN")
JSON=(-H "Content-Type: application/json")
NOW=$(($(date +%s) * 1000))
SID="smoke-$NOW"

step() { printf '\n== %s\n' "$1"; }
req() { # method path [body]
  local method=$1 path=$2 body=${3:-}
  local out status
  if [ -n "$body" ]; then
    out=$(curl -sS -w '\n%{http_code}' -X "$method" "${AUTH[@]}" "${JSON[@]}" -d "$body" "$BASE_URL$path")
  else
    out=$(curl -sS -w '\n%{http_code}' -X "$method" "${AUTH[@]}" "$BASE_URL$path")
  fi
  status=${out##*$'\n'}
  printf '%s\n' "${out%$'\n'*}" | cut -c1-300
  if [ "${status:0:1}" != "2" ]; then echo "FAILED: $method $path -> HTTP $status" >&2; exit 1; fi
}

step "health (no auth)"
curl -sSf "$BASE_URL/v1/health"; echo

step "401 without token"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/v1/goals")
[ "$code" = "401" ] || { echo "expected 401, got $code" >&2; exit 1; }
echo "401 ok"

step "put session"
req PUT "/v1/sessions/$SID" "{\"id\":\"$SID\",\"kind\":\"gym\",\"type\":\"Push\",\"startedAt\":$((NOW-3600000)),\"endedAt\":$NOW,\"exercises\":[{\"name\":\"Bench press\",\"sets\":[{\"reps\":6,\"kg\":40,\"max\":false},{\"reps\":6,\"kg\":60,\"max\":false},{\"reps\":1,\"kg\":65,\"max\":true}]}],\"source\":\"app\"}"

step "start"
req GET /v1/start
step "plan"
req GET "/v1/plans/next?type=Push"
step "dashboard"
req GET "/v1/dashboard?days=7"

step "create goal"
req POST /v1/goals '{"title":"Bench 80 kg","kind":"strength","exercise":"Bench press","targetKg":80}'

step "chat"
THREAD=$(curl -sSf -X POST "${AUTH[@]}" "${JSON[@]}" -d '{"title":"Smoke"}' "$BASE_URL/v1/threads" | sed -E 's/.*"thread":\{"id":"([^"]+)".*/\1/')
echo "thread $THREAD"
req POST "/v1/threads/$THREAD/messages" '{"text":"ankle felt tight after squats"}'

step "review (may be empty until background job finishes)"
sleep 1
req GET "/v1/sessions/$SID/review"

echo; echo "SMOKE OK"
