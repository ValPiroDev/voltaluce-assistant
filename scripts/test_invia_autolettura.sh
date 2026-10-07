#!/bin/bash
# Smoke test for the invia_autolettura webhook. Reads WEBHOOK_API_KEY from .env.
# Usage: ./scripts/test_invia_autolettura.sh [base_url]   (default http://localhost:5679)
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="$(grep ^WEBHOOK_API_KEY .env | cut -d= -f2)"
URL="${1:-http://localhost:5679}/webhook/invia-autolettura"
CONV="curl-test-$(date +%s)"   # new conversation id per run, so the first insert is never a duplicate

call() {  # label, api-key, json body
  echo "=== $1"
  curl -s -w "\n-> HTTP %{http_code}\n\n" -X POST "$URL" \
       -H "Content-Type: application/json" -H "x-api-key: $2" -d "$3"
}
call "200 new reading (CL-00001 luce, last was 15644)"  "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"luce\",\"valore\":\"15800\",\"conversation_id\":\"$CONV\"}"
call "200 duplicate (same request repeated)"            "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"luce\",\"valore\":\"15800\",\"conversation_id\":\"$CONV\"}"
call "422 below last reading"                           "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"luce\",\"valore\":\"15000\",\"conversation_id\":\"$CONV\"}"
call "200 first reading ever (CL-00005 luce)"           "$KEY"  "{\"codice_cliente\":\"CL-00005\",\"tipo_fornitura\":\"luce\",\"valore\":\"120,5\",\"conversation_id\":\"$CONV\"}"
call "404 inactive supply (CL-00005 gas)"               "$KEY"  "{\"codice_cliente\":\"CL-00005\",\"tipo_fornitura\":\"gas\",\"valore\":\"10\",\"conversation_id\":\"$CONV\"}"
call "400 non-numeric value"                            "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"gas\",\"valore\":\"abc\",\"conversation_id\":\"$CONV\"}"
call "400 negative value"                               "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"gas\",\"valore\":\"-5\",\"conversation_id\":\"$CONV\"}"
call "400 bad supply type"                              "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"acqua\",\"valore\":\"5\",\"conversation_id\":\"$CONV\"}"
call "401 wrong api key"                                "wrong" "{\"codice_cliente\":\"CL-00001\",\"tipo_fornitura\":\"gas\",\"valore\":\"5\",\"conversation_id\":\"$CONV\"}"
