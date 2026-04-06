#!/usr/bin/env bash
set -euo pipefail

: "${N8N_BASE_URL:?N8N_BASE_URL is required}"
: "${N8N_API_KEY:?N8N_API_KEY is required}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

base="${N8N_BASE_URL%/}"
api="$base/api/v1"

request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -fsS -X "$method" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      -H "Content-Type: application/json" \
      "$api$path" \
      --data-binary "$data"
  else
    curl -fsS -X "$method" \
      -H "X-N8N-API-KEY: $N8N_API_KEY" \
      "$api$path"
  fi
}

for file in workflows/*.json; do
  [[ -e "$file" ]] || continue

  echo "Processing $file"

  name=$(jq -r '.name' "$file")
  active=$(jq -r '.active // false' "$file")

  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "Skipping $file: missing .name"
    continue
  fi

  existing=$(request GET "/workflows" | jq -r --arg NAME "$name" '.data[]? | select(.name == $NAME) | .id' | head -n1 || true)

  payload=$(jq '{
    name,
    nodes,
    connections,
    settings: (.settings // {}),
    staticData: (.staticData // null),
    pinData: (.pinData // {}),
    versionId: (.versionId // null),
    meta: (.meta // null),
    tags: (.tags // [])
  }' "$file")

  if [[ -n "$existing" ]]; then
    echo "Updating workflow: $name ($existing)"
    request PUT "/workflows/$existing" "$payload" >/dev/null
    id="$existing"
  else
    echo "Creating workflow: $name"
    id=$(request POST "/workflows" "$payload" | jq -r '.id')
  fi

  if [[ "$active" == "true" ]]; then
    echo "Activating workflow: $name ($id)"
    request POST "/workflows/$id/activate" >/dev/null || {
      echo "Activation call failed for $name"
      exit 1
    }
  fi

done
