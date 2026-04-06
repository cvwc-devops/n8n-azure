#!/usr/bin/env bash
set -euo pipefail

: "${N8N_BASE_URL:?N8N_BASE_URL is required}"
: "${AZURE_KEYVAULT_NAME:?AZURE_KEYVAULT_NAME is required}"

N8N_BASE_URL="${N8N_BASE_URL%/}"
API_KEY="$(az keyvault secret show --vault-name "$AZURE_KEYVAULT_NAME" --name n8n-api-key --query value -o tsv)"

for file in workflows/*.json; do
  [ -e "$file" ] || continue
  name="$(jq -r '.name' "$file")"
  existing_id="$(curl -fsS -H "X-N8N-API-KEY: $API_KEY" "$N8N_BASE_URL/api/v1/workflows" | jq -r --arg NAME "$name" '.data[] | select(.name==$NAME) | .id' | head -n1)"

  if [ -n "$existing_id" ]; then
    echo "Updating workflow: $name"
    curl -fsS -X PUT \
      -H "Content-Type: application/json" \
      -H "X-N8N-API-KEY: $API_KEY" \
      "$N8N_BASE_URL/api/v1/workflows/$existing_id" \
      --data-binary @"$file" >/dev/null
    curl -fsS -X POST \
      -H "X-N8N-API-KEY: $API_KEY" \
      "$N8N_BASE_URL/api/v1/workflows/$existing_id/activate" >/dev/null || true
  else
    echo "Creating workflow: $name"
    new_id="$(curl -fsS -X POST \
      -H "Content-Type: application/json" \
      -H "X-N8N-API-KEY: $API_KEY" \
      "$N8N_BASE_URL/api/v1/workflows" \
      --data-binary @"$file" | jq -r '.id')"
    curl -fsS -X POST \
      -H "X-N8N-API-KEY: $API_KEY" \
      "$N8N_BASE_URL/api/v1/workflows/$new_id/activate" >/dev/null || true
  fi

done
