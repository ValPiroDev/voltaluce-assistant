-- Upsert of a finished conversation sent by the ElevenLabs post-call webhook.
-- $1 conversation_id, $2 customer_code (nullable), $3 duration_sec, $4 outcome,
-- $5 transcript (text), $6 metadata (jsonb as text).
-- ON CONFLICT DO UPDATE: ElevenLabs may redeliver the same event; the last delivery wins.
INSERT INTO calls (conversation_id, customer_id, duration_sec, outcome, transcript, metadata)
VALUES (
    $1,
    (SELECT id FROM customers WHERE customer_code = $2),   -- NULL when not identified
    $3::integer,
    $4,
    $5,
    $6::jsonb
)
ON CONFLICT (conversation_id) DO UPDATE SET
    customer_id  = EXCLUDED.customer_id,
    duration_sec = EXCLUDED.duration_sec,
    outcome      = EXCLUDED.outcome,
    transcript   = EXCLUDED.transcript,
    metadata     = EXCLUDED.metadata
RETURNING id, (xmax = 0) AS inserted;   -- xmax = 0 means a fresh row, otherwise an update
