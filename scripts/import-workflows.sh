#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_DIR="${1:-workflows}"
: "${N8N_BASE_URL:?N8N_BASE_URL is required}"
: "${N8N_API_KEY:?N8N_API_KEY is required}"

API_BASE="${N8N_BASE_URL%/}/api/v1"
AUTH_HEADER="X-N8N-API-KEY: ${N8N_API_KEY}"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

get_existing_id_by_name() {
  local name="$1"
  curl -fsS \
    -H "$AUTH_HEADER" \
    "$API_BASE/workflows?limit=250" | jq -r --arg NAME "$name" '.data[]? | select(.name == $NAME) | .id' | head -n1
}

upsert_workflow() {
  local file="$1"
  local workflow_name workflow_id payload

  workflow_name=$(jq -r '.name' "$file")
  if [[ -z "$workflow_name" || "$workflow_name" == "null" ]]; then
    echo "Skipping $file because it has no .name" >&2
    return 1
  fi

  workflow_id=$(get_existing_id_by_name "$workflow_name" || true)
  payload=$(jq 'del(.id, .versionId, .createdAt, .updatedAt)' "$file")

  if [[ -n "${workflow_id:-}" ]]; then
    echo "Updating workflow: $workflow_name ($workflow_id)"
    curl -fsS -X PUT \
      -H "$AUTH_HEADER" \
      -H 'Content-Type: application/json' \
      "$API_BASE/workflows/$workflow_id" \
      --data "$payload" >/dev/null
  else
    echo "Creating workflow: $workflow_name"
    curl -fsS -X POST \
      -H "$AUTH_HEADER" \
      -H 'Content-Type: application/json' \
      "$API_BASE/workflows" \
      --data "$payload" >/dev/null
  fi
}

shopt -s nullglob
for file in "$WORKFLOW_DIR"/*.json; do
  upsert_workflow "$file"
done
