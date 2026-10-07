-- Active supply of a customer for a given type, with its latest meter reading.
-- $1 = customer_code, $2 = supply type ('electricity' | 'gas').
-- Zero rows  => unknown customer or no active supply of that type (HTTP 404).
-- One row with last_value NULL => supply exists but was never read (first reading).
SELECT
    s.id          AS supply_id,      -- from supplies, so it is never NULL
    s.meter_code,
    r.value       AS last_value,     -- NULL when no reading exists (LEFT JOIN)
    r.read_at     AS last_read_at
FROM customers c
JOIN supplies s        ON s.customer_id = c.id      -- supply must exist
LEFT JOIN meter_readings r ON r.supply_id = s.id    -- reading is optional
WHERE c.customer_code = $1
  AND s.type = $2
  AND s.active = true
ORDER BY r.read_at DESC NULLS LAST, r.id DESC       -- latest in time, id breaks ties
LIMIT 1;
