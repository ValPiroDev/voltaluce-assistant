#!/bin/bash
# Simulates an ElevenLabs post-call webhook delivery with a valid HMAC signature.
# Reads ELEVENLABS_POSTCALL_SECRET from .env. Usage: ./scripts/test_post_call.sh [base_url]
set -euo pipefail
cd "$(dirname "$0")/.."
SECRET="$(grep ^ELEVENLABS_POSTCALL_SECRET .env | cut -d= -f2)"
URL="${1:-http://localhost:5679}/webhook/post-call"
CONV="conv_test_$(date +%s)"

# Minimal payload with the fields the workflow uses (real payloads carry many more).
BODY=$(cat <<JSON
{"type":"post_call_transcription","event_timestamp":$(date +%s),"data":{"agent_id":"agent_test","conversation_id":"$CONV","status":"done","transcript":[{"role":"agent","message":"Buongiorno, sono l'assistente di VoltaLuce.","time_in_call_secs":0},{"role":"user","message":"Codice CL-00002, quanto devo pagare?","time_in_call_secs":4},{"role":"agent","message":"La sua ultima bolletta e' di 71 euro e 80, scaduta il 31 agosto.","time_in_call_secs":9,"tool_calls":[{"tool_name":"get_ultima_bolletta","params_as_json":"{\"codice_cliente\":\"CL-00002\"}"}]}],"metadata":{"start_time_unix_secs":$(date +%s),"call_duration_secs":23,"termination_reason":"user hung up"},"analysis":{"call_successful":"success","transcript_summary":"Il cliente CL-00002 ha chiesto l'ultima bolletta.","evaluation_criteria_results":{},"data_collection_results":{"codice_cliente":{"value":"CL-00002"}}}}}
JSON
)

sign() {  # timestamp, body -> signature header value
  local sig; sig=$(printf '%s.%s' "$1" "$2" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.* //')
  printf 't=%s,v0=%s' "$1" "$sig"
}
TS=$(date +%s)

call() {  # label, signature header, body
  echo "=== $1"
  curl -s -w "\n-> HTTP %{http_code}\n\n" -X POST "$URL" -H "Content-Type: application/json" \
       -H "ElevenLabs-Signature: $2" --data-raw "$3"
}
call "200 valid signature"            "$(sign "$TS" "$BODY")"                 "$BODY"
call "200 redelivery (same conversation, upsert)" "$(sign "$TS" "$BODY")"    "$BODY"
call "401 wrong signature"            "t=$TS,v0=deadbeef"                     "$BODY"
call "401 stale timestamp (2h old)"   "$(sign $((TS-7200)) "$BODY")"          "$BODY"
call "401 tampered body"              "$(sign "$TS" "$BODY")"                 "${BODY/23/999}"
call "401 missing header"             ""                                      "$BODY"
