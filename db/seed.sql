-- Test data for VoltaLuce Assistant (fictional). Re-runnable: wipes app tables first.
-- Apply as the superuser:  docker exec -i voltaluce_postgres psql -U postgres -d voltaluce < db/seed.sql
-- Reference date for the scenario: 2026-10-06.
BEGIN;

TRUNCATE calls, tickets, meter_readings, bills, supplies, customers, workflow_errors
    RESTART IDENTITY;

-- ---------------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------------
INSERT INTO customers (customer_code, first_name, last_name, email, phone) VALUES
    ('CL-00001', 'Marco',     'Bianchi',  'marco.bianchi@example.com',     '+39 333 1234567'),
    ('CL-00002', 'Giulia',    'Rossi',    'giulia.rossi@example.com',      '+39 347 2345678'),
    ('CL-00003', 'Antonio',   'Esposito', 'antonio.esposito@example.com',  '+39 320 3456789'),
    ('CL-00004', 'Francesca', 'Colombo',  'francesca.colombo@example.com', '+39 338 4567890'),
    ('CL-00005', 'Luca',      'Ferrari',  'luca.ferrari@example.com',      '+39 329 5678901');

-- ---------------------------------------------------------------------------
-- Supplies: POD (electricity, "IT...E...") and PDR (gas, 14 digits)
-- Subselects on customer_code avoid hard-coding generated ids.
-- ---------------------------------------------------------------------------
INSERT INTO supplies (customer_id, type, meter_code, address, active) VALUES
    ((SELECT id FROM customers WHERE customer_code = 'CL-00001'), 'electricity', 'IT001E10000001', 'Via Roma 12, 20121 Milano',          true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00001'), 'gas',         '00881000000001', 'Via Roma 12, 20121 Milano',          true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00002'), 'electricity', 'IT001E10000002', 'Corso Vittorio Emanuele 45, 10121 Torino', true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00003'), 'electricity', 'IT001E10000003', 'Via Toledo 88, 80134 Napoli',        true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00003'), 'gas',         '00881000000003', 'Via Toledo 88, 80134 Napoli',        true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00004'), 'gas',         '00881000000004', 'Via Garibaldi 7, 40124 Bologna',     true),
    ((SELECT id FROM customers WHERE customer_code = 'CL-00005'), 'electricity', 'IT001E10000005', 'Via Dante 3, 50122 Firenze',         true),
    -- Closed gas supply: still in the archive, flagged inactive
    ((SELECT id FROM customers WHERE customer_code = 'CL-00005'), 'gas',         '00881000000005', 'Via Dante 3, 50122 Firenze',         false);

-- ---------------------------------------------------------------------------
-- Bills: bimonthly. Statuses mixed so every workflow branch can be tested.
-- ---------------------------------------------------------------------------
INSERT INTO bills (supply_id, period_start, period_end, amount, due_date, status, issued_on) VALUES
    -- CL-00001 electricity: latest is unpaid, not yet due
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000001'), '2026-04-01', '2026-05-31',  87.40, '2026-06-30', 'paid',    '2026-06-10'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000001'), '2026-06-01', '2026-07-31', 112.95, '2026-08-31', 'paid',    '2026-08-10'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000001'), '2026-08-01', '2026-09-30',  98.20, '2026-10-31', 'unpaid',  '2026-10-05'),
    -- CL-00001 gas: summer bills are low
    ((SELECT id FROM supplies WHERE meter_code = '00881000000001'), '2026-06-01', '2026-07-31',  24.10, '2026-08-31', 'paid',    '2026-08-12'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000001'), '2026-08-01', '2026-09-30',  31.75, '2026-10-31', 'unpaid',  '2026-10-05'),
    -- CL-00002 electricity: latest bill is OVERDUE
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000002'), '2026-04-01', '2026-05-31',  64.30, '2026-06-30', 'paid',    '2026-06-11'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000002'), '2026-06-01', '2026-07-31',  71.80, '2026-08-31', 'overdue', '2026-08-11'),
    -- CL-00003 electricity + gas: all paid
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000003'), '2026-06-01', '2026-07-31', 143.60, '2026-08-31', 'paid',    '2026-08-10'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000003'), '2026-08-01', '2026-09-30', 129.15, '2026-10-31', 'paid',    '2026-10-03'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000003'), '2026-06-01', '2026-07-31',  18.90, '2026-08-31', 'paid',    '2026-08-12'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000003'), '2026-08-01', '2026-09-30',  22.40, '2026-10-31', 'paid',    '2026-10-03'),
    -- CL-00004 gas only
    ((SELECT id FROM supplies WHERE meter_code = '00881000000004'), '2026-04-01', '2026-05-31',  58.20, '2026-06-30', 'paid',    '2026-06-12'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000004'), '2026-06-01', '2026-07-31',  19.60, '2026-08-31', 'paid',    '2026-08-12'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000004'), '2026-08-01', '2026-09-30',  27.35, '2026-10-31', 'unpaid',  '2026-10-05'),
    -- CL-00005 electricity: two bills, latest unpaid
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000005'), '2026-06-01', '2026-07-31',  92.70, '2026-08-31', 'paid',    '2026-08-10'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000005'), '2026-08-01', '2026-09-30',  84.05, '2026-10-31', 'unpaid',  '2026-10-05');
    -- CL-00005 gas (inactive) has no bills on purpose: tests the "no bill found" branch.

-- ---------------------------------------------------------------------------
-- Meter readings: historical, from the portal. Used to reject lower readings.
-- Electricity in kWh, gas in Smc. request_id NULL: not created by the agent.
-- ---------------------------------------------------------------------------
INSERT INTO meter_readings (supply_id, value, read_at, source) VALUES
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000001'), 15230.000, '2026-07-31 09:15:00+02', 'web_portal'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000001'), 15644.000, '2026-09-30 08:40:00+02', 'web_portal'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000001'),  2310.512, '2026-09-30 08:42:00+02', 'web_portal'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000002'),  8902.000, '2026-07-31 18:05:00+02', 'web_portal'),
    ((SELECT id FROM supplies WHERE meter_code = 'IT001E10000003'), 21077.000, '2026-09-30 07:55:00+02', 'web_portal'),
    ((SELECT id FROM supplies WHERE meter_code = '00881000000004'),  4120.000, '2026-09-29 19:20:00+02', 'web_portal');
    -- CL-00005 electricity has no reading: tests the "first reading" case.

-- ---------------------------------------------------------------------------
-- One existing ticket, so the agent's "open ticket" result is not the only row
-- ---------------------------------------------------------------------------
INSERT INTO tickets (customer_id, description, status, priority, request_id) VALUES
    ((SELECT id FROM customers WHERE customer_code = 'CL-00002'),
     'Bolletta di luglio piu alta del solito, richiesta verifica dei consumi',
     'in_progress', 'medium', 'seed-ticket-0001');

COMMIT;
