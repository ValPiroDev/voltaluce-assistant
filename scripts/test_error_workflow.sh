#!/bin/bash
# Triggers an unhandled failure in post_call (valid signature, but data.transcript is a string,
# so the Code node's .map() throws) and checks that error_handler logged it in workflow_errors.
set -euo pipefail
cd "$(dirname "$0")/.."
SECRET="$(grep ^ELEVENLABS_POSTCALL_SECRET .env | cut -d= -f2)"
URL="${1:-http://localhost:5679}/webhook/post-call"
TS=$(date +%s)
BODY="{\"type\":\"post_call_transcription\",\"event_timestamp\":$TS,\"data\":{\"conversation_id\":\"conv_broken_$TS\",\"transcript\":\"not-an-array\",\"metadata\":{},\"analysis\":{}}}"
SIG=$(printf '%s.%s' "$TS" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.* //')
echo "=== malformed payload with valid signature (expect 500 from n8n)"
curl -s -w "\n-> HTTP %{http_code}\n" -X POST "$URL" -H "Content-Type: application/json" \
     -H "ElevenLabs-Signature: t=$TS,v0=$SIG" --data-raw "$BODY"
sleep 3
echo "=== workflow_errors (last row)"
docker exec voltaluce_postgres psql -U postgres -d voltaluce -c \
  "select id, workflow_name, node_name, left(message, 70) as message, created_at from workflow_errors order by id desc limit 1"
