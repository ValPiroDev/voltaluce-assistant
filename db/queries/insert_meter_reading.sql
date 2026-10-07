-- Idempotent insert of a meter reading sent by the voice agent.
-- $1 = supply_id, $2 = value, $3 = request_id (unique per tool call).
-- Duplicate request_id => no row inserted, RETURNING yields zero rows (HTTP 200 with duplicate:true).
INSERT INTO meter_readings (supply_id, value, source, request_id)
VALUES ($1, $2::numeric, 'voice_agent', $3)
ON CONFLICT (request_id) DO NOTHING
RETURNING id, value, read_at;
