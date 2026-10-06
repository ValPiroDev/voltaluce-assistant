-- Latest issued bill for a customer, across all their supplies.
-- $1 = customer_code. Zero rows => customer unknown or no bills (HTTP 404).
SELECT
    c.customer_code,
    c.first_name,
    s.type        AS supply_type,
    s.meter_code,
    b.amount,
    b.period_start,
    b.period_end,
    b.due_date,
    b.status,
    b.issued_on
FROM customers c
JOIN supplies  s ON s.customer_id = c.id
JOIN bills     b ON b.supply_id   = s.id
WHERE c.customer_code = $1
ORDER BY b.issued_on DESC, b.id DESC   -- id breaks ties on same-day bills
LIMIT 1;
