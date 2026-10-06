#!/bin/bash
# Smoke test for the get_ultima_bolletta webhook. Reads WEBHOOK_API_KEY from .env.
# Usage: ./scripts/test_get_ultima_bolletta.sh [base_url]   (default http://localhost:5679)
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="$(grep ^WEBHOOK_API_KEY .env | cut -d= -f2)"
URL="${1:-http://localhost:5679}/webhook/get-ultima-bolletta"

call() {  # label, api-key, json body
  echo "=== $1"
  curl -s -w "\n-> HTTP %{http_code}\n\n" -X POST "$URL" \
       -H "Content-Type: application/json" -H "x-api-key: $2" -d "$3"
}
call "200 latest bill"        "$KEY"  '{"codice_cliente":"CL-00001"}'
call "404 unknown customer"   "$KEY"  '{"codice_cliente":"CL-99999"}'
call "401 wrong api key"      "wrong" '{"codice_cliente":"CL-00001"}'
call "400 malformed code"     "$KEY"  '{"codice_cliente":"pippo"}'
call "200 normalized input"   "$KEY"  '{"codice_cliente":"  cl-00005 "}'
