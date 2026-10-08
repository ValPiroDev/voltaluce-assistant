#!/bin/bash
# Smoke test for the apri_ticket webhook. Reads WEBHOOK_API_KEY from .env.
# Usage: ./scripts/test_apri_ticket.sh [base_url]   (default http://localhost:5679)
set -euo pipefail
cd "$(dirname "$0")/.."
KEY="$(grep ^WEBHOOK_API_KEY .env | cut -d= -f2)"
URL="${1:-http://localhost:5679}/webhook/apri-ticket"
CONV="curl-ticket-$(date +%s)"

call() {  # label, api-key, json body
  echo "=== $1"
  curl -s -w "\n-> HTTP %{http_code}\n\n" -X POST "$URL" \
       -H "Content-Type: application/json" -H "x-api-key: $2" -d "$3"
}
call "201 new ticket (priority alta)"      "$KEY"  "{\"codice_cliente\":\"CL-00003\",\"descrizione\":\"Il contatore del gas fa un rumore strano da due giorni\",\"priorita\":\"alta\",\"conversation_id\":\"$CONV\"}"
call "200 duplicate (same conversation)"   "$KEY"  "{\"codice_cliente\":\"CL-00003\",\"descrizione\":\"Il contatore del gas fa un rumore strano da due giorni\",\"priorita\":\"alta\",\"conversation_id\":\"$CONV\"}"
call "201 no priority -> medium"           "$KEY"  "{\"codice_cliente\":\"CL-00004\",\"descrizione\":\"Vorrei cambiare l'indirizzo di fatturazione\",\"conversation_id\":\"$CONV-b\"}"
call "404 unknown customer"                "$KEY"  "{\"codice_cliente\":\"CL-99999\",\"descrizione\":\"Descrizione abbastanza lunga per passare\",\"conversation_id\":\"$CONV-c\"}"
call "400 description too short"           "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"descrizione\":\"corta\",\"conversation_id\":\"$CONV-d\"}"
call "400 missing conversation_id"         "$KEY"  "{\"codice_cliente\":\"CL-00001\",\"descrizione\":\"Descrizione abbastanza lunga per passare\"}"
call "401 wrong api key"                   "wrong" "{\"codice_cliente\":\"CL-00001\",\"descrizione\":\"Descrizione abbastanza lunga per passare\",\"conversation_id\":\"$CONV-e\"}"
