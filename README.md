# VoltaLuce Assistant

Voice customer-care agent for a fictional Italian electricity and gas utility.
An **ElevenLabs** conversational agent talks to the customer and calls three tools;
each tool is an **n8n** webhook that reads or writes **PostgreSQL**. When the call ends,
ElevenLabs posts the transcript to a fourth webhook, verified with an HMAC signature.
Unhandled failures are logged by an n8n error workflow.

Built in three days as an interview project. Everything runs locally with Docker Compose;
a Cloudflare quick tunnel exposes n8n to ElevenLabs.

## Architecture

```
caller ──voice──▶ ElevenLabs agent ──POST /webhook/<tool>──▶ n8n ──SQL──▶ PostgreSQL
                        │                   (x-api-key)       │
                        └──POST /webhook/post-call───────────▶┘  (HMAC signature)
                           after the call ends
```

See [docs/architettura.md](docs/architettura.md) for the Mermaid diagram, the data model and the design decisions.

| Tool (agent side) | n8n workflow | What it does | Status codes |
|---|---|---|---|
| `get_ultima_bolletta` | `get_ultima_bolletta` | latest issued bill of a customer | 200, 400, 401, 404 |
| `invia_autolettura` | `invia_autolettura` | registers a meter reading; rejects non-numeric, negative or lower-than-last values; idempotent | 200 (+`duplicate`), 400, 401, 404, 422 |
| `apri_ticket` | `apri_ticket` | opens a ticket for a human operator; one per conversation | 201, 200 (`duplicate`), 400, 401, 404 |
| post-call webhook | `post_call` | stores transcript, duration, outcome and analysis in `calls` | 200, 401 |
| (n8n internal) | `error_handler` | writes unhandled failures to `workflow_errors` | - |

## Repository layout

```
docker-compose.yml        n8n 2.42.3 + PostgreSQL 17, named volumes, healthcheck
.env.example              every variable, with how to generate the secrets
db/init/                  creates the "n8n" and "voltaluce" databases and roles (first start only)
db/schema.sql             application tables, constraints, indexes, least-privilege grants
db/seed.sql               5 customers, 8 supplies, 16 bills, readings, one ticket (re-runnable)
db/queries/               the SQL used by the workflows, with comments
workflows/*.json          n8n workflows, importable
agent/system-prompt.md    agent prompt, first message and the three tool definitions
scripts/                  tunnel starter and curl smoke tests for every webhook
docs/                     architecture: diagrams, data model, design decisions
```

## Quick start

Requirements: Docker Desktop, Git, an ElevenLabs account (free plan is enough), `cloudflared`
(`winget install Cloudflare.cloudflared`).

```bash
git clone <this repo> && cd voltaluce-assistant
cp .env.example .env            # then replace every CHANGE_ME (openssl rand -hex 32)
docker compose up -d            # first start creates the databases and roles
docker exec -i voltaluce_postgres psql -U postgres -d voltaluce < db/schema.sql
docker exec -i voltaluce_postgres psql -U postgres -d voltaluce < db/seed.sql
```

Then open `http://localhost:5679`, create the owner account and:

1. Credentials → add a Postgres credential: host `postgres`, port `5432`, database `voltaluce`,
   user `voltaluce_app`, password from `.env`.
2. Import every file in `workflows/`, select that credential in the Postgres nodes, **Publish** each
   workflow, and set `error_handler` as the Error Workflow in the settings of the other four.
3. Run the smoke tests against localhost:

```bash
bash scripts/test_get_ultima_bolletta.sh
bash scripts/test_invia_autolettura.sh
bash scripts/test_apri_ticket.sh
bash scripts/test_post_call.sh
```

## Connecting ElevenLabs

1. Start the tunnel and keep the window open: `powershell -File scripts/start_tunnel.ps1`.
   It prints the public URL. Put it in `.env` as `N8N_WEBHOOK_URL` and run `docker compose up -d n8n`.
2. In the ElevenLabs dashboard create the agent from `agent/system-prompt.md`: prompt, first message,
   Italian voice, and the three Webhook tools with the public URL, the `x-api-key` header and
   **Error handling mode = passthrough** (otherwise 4xx bodies never reach the LLM).
3. Agents → Settings → Post-call webhooks: URL `<public url>/webhook/post-call`. Copy the signing
   secret into `.env` as `ELEVENLABS_POSTCALL_SECRET` and restart n8n.
4. Publish the agent and test it with the "Test AI agent" widget.

The quick tunnel URL changes at every start: update the tool URLs and the post-call URL each time.
A named Cloudflare tunnel with a fixed domain removes this step in a real deployment.

## Data model

Seven tables in the `voltaluce` database, owned by the superuser; the workflows connect as
`voltaluce_app`, which can `SELECT`, `INSERT`, `UPDATE` and never `DELETE` (utility data is
deactivated, not deleted).

- `customers` ← `supplies` (one per customer per type, `electricity` or `gas`)
- `supplies` ← `bills`, `meter_readings`
- `customers` ← `tickets`, `calls` (nullable: the caller may not identify)
- `workflow_errors` with no foreign keys, so it can be written when everything else is broken

All foreign keys are `ON DELETE RESTRICT` (`SET NULL` on `calls.customer_id`). Idempotency keys:
`meter_readings.request_id` and `tickets.request_id` (`UNIQUE`, used with `ON CONFLICT DO NOTHING`),
`calls.conversation_id` (`ON CONFLICT DO UPDATE`, the post-call may be redelivered).
`calls.metadata` and `workflow_errors.details` are `JSONB`.

## Security notes

- Tools: shared secret in the `x-api-key` header, checked in a Code node so the response is a
  proper 401 with a JSON body. Trade-off: every bad request still costs an n8n execution; in
  production the check would move to the edge (rate limiting, native header auth).
- Post-call: `ElevenLabs-Signature` header, HMAC-SHA256 of `timestamp.rawBody`, 30-minute
  tolerance, constant-time comparison, raw body taken from the Webhook node's "Raw Body" option.
- SQL: every query uses `$1..$n` parameters (prepared statements); values are never concatenated.
- The tunnel exposes the n8n editor too: keep it running only during demos.
- Secrets live only in `.env`, which is git-ignored.

## Known limitations

- Quick tunnel: random URL, no uptime guarantee (QUIC drops on some networks: the script forces HTTP/2).
- `error_handler` logs to the same PostgreSQL the workflows use; a database outage would not be logged.
  A real deployment would also notify an external channel.
- One ticket per conversation (`request_id = conversation_id`).
- `bills.status = 'overdue'` is stored, not derived; a nightly job would maintain it.
