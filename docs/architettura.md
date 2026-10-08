# Architettura

## Componenti

```mermaid
flowchart LR
    C[Cliente al telefono / widget] -->|voce| EL[ElevenLabs Agent<br/>STT + LLM + TTS]
    EL -->|"POST /webhook/get-ultima-bolletta<br/>x-api-key"| W1
    EL -->|"POST /webhook/invia-autolettura<br/>x-api-key"| W2
    EL -->|"POST /webhook/apri-ticket<br/>x-api-key"| W3
    EL -.->|"POST /webhook/post-call<br/>ElevenLabs-Signature (HMAC)<br/>a chiamata finita"| W4

    subgraph TUN[Cloudflare quick tunnel]
    end
    EL --- TUN

    subgraph N8N[n8n 2.42.3 - Docker]
        W1[get_ultima_bolletta]
        W2[invia_autolettura]
        W3[apri_ticket]
        W4[post_call]
        W5[error_handler<br/>Error Trigger]
        W1 -.->|errore non gestito| W5
        W2 -.-> W5
        W3 -.-> W5
        W4 -.-> W5
    end

    subgraph PG[PostgreSQL 17 - Docker]
        DBN[(db n8n<br/>tabelle interne)]
        DBA[(db voltaluce<br/>customers, supplies, bills,<br/>meter_readings, tickets,<br/>calls, workflow_errors)]
    end

    N8N -->|ruolo n8n| DBN
    W1 & W2 & W3 & W4 & W5 -->|ruolo voltaluce_app<br/>SELECT INSERT UPDATE| DBA
```

## Flusso di un tool call

```mermaid
sequenceDiagram
    participant U as Cliente
    participant EL as ElevenLabs
    participant N as n8n (invia_autolettura)
    participant PG as PostgreSQL

    U->>EL: "lettura luce 15900, codice CL-00001"
    EL->>EL: STT, LLM decide il tool
    EL->>N: POST /webhook/invia-autolettura {codice_cliente, tipo_fornitura, valore, conversation_id}
    N->>N: Code: x-api-key, regex, numero, request_id = conv:tipo:valore
    N->>PG: SELECT fornitura attiva + ultima lettura ($1, $2)
    PG-->>N: supply_id, last_value
    N->>N: IF valore >= last_value
    N->>PG: INSERT ... ON CONFLICT (request_id) DO NOTHING RETURNING
    PG-->>N: riga oppure niente (duplicato)
    N-->>EL: 200 {registered, duplicate, previous_value} | 422 | 404 | 400 | 401
    EL->>EL: LLM legge il JSON (passthrough), TTS
    EL-->>U: "Registrata la lettura 15900, la precedente era 15800"
```

## Modello dati

```mermaid
erDiagram
    customers ||--o{ supplies : has
    supplies ||--o{ bills : issues
    supplies ||--o{ meter_readings : records
    customers ||--o{ tickets : opens
    customers |o--o{ calls : "may identify"

    customers {
        bigint id PK
        text customer_code UK
        text first_name
        text last_name
        text email
        text phone
        timestamptz created_at
    }
    supplies {
        bigint id PK
        bigint customer_id FK
        text type "electricity | gas"
        text meter_code UK
        text address
        boolean active
    }
    bills {
        bigint id PK
        bigint supply_id FK
        date period_start
        date period_end
        numeric amount
        date due_date
        text status "paid | unpaid | overdue"
        date issued_on
    }
    meter_readings {
        bigint id PK
        bigint supply_id FK
        numeric value
        timestamptz read_at
        text source
        text request_id UK "idempotency"
    }
    tickets {
        bigint id PK
        bigint customer_id FK
        text description
        text status
        text priority
        text request_id UK "idempotency"
        timestamptz created_at
    }
    calls {
        bigint id PK
        text conversation_id UK
        bigint customer_id FK "nullable"
        integer duration_sec
        text outcome
        text transcript
        jsonb metadata
        timestamptz created_at
    }
    workflow_errors {
        bigint id PK
        text workflow_name
        text execution_id
        text node_name
        text message
        jsonb details
        timestamptz created_at
    }
```

## Scelte tecniche

| Scelta | Motivo | Alternativa scartata |
|---|---|---|
| Due database Postgres (`n8n`, `voltaluce`) nello stesso container | n8n possiede il suo schema con decine di tabelle migrate automaticamente; il ruolo dei workflow non può nemmeno vedere quelle tabelle | Due schemi nello stesso database: isolamento più debole |
| Ruolo `voltaluce_app` senza `DELETE` | I dati di una utility si disattivano, non si cancellano; l'agente vocale non può distruggere nulla | Ruolo owner delle tabelle |
| `ON DELETE RESTRICT` ovunque, `SET NULL` su `calls` | Bollette e letture hanno valore fiscale; la FK vive sul figlio e protegge il padre | `CASCADE`: un `DELETE` sbagliato cancellerebbe lo storico |
| Autenticazione dei tool nel Code node | 401 con body JSON coerente; un solo nodo per auth e validazione | Header Auth nativa: 403 generico, ma rifiuta prima di creare l'esecuzione (meglio in produzione, al bordo) |
| Idempotenza con `request_id` derivato da `conversation_id` | ElevenLabs non espone un id per tool call; la chiave identifica l'intenzione (stessa conversazione, stessa fornitura, stesso valore) | Chiave generata dall'LLM: inaffidabile |
| `ON CONFLICT DO NOTHING RETURNING` | Un solo statement dice se ha inserito; rende sicuri i retry | `SELECT` poi `INSERT`: race condition |
| Date castate `::text` nelle query | Il driver `pg` trasformerebbe `DATE` in `Date` JavaScript e la serializzazione UTC può spostare il giorno | Convertire nel Code node |
| Status code HTTP semantici + `passthrough` nei tool ElevenLabs | Status per le macchine (log, retry), body per l'LLM; senza passthrough i 4xx arrivano all'LLM come errore generico | Rispondere sempre 200 con `ok:false` |
| Campo `say_to_customer` nelle risposte di errore | L'LLM parafrasava male i messaggi tecnici; una frase pronta in italiano riduce le invenzioni | Solo `message` tecnico |
| HMAC sul post-call, API key sui tool | Il post-call lo firma ElevenLabs con il suo schema; per i tool definiamo noi il contratto | Nessuna verifica: endpoint aperto a payload inventati |
| Error workflow che scrive in `workflow_errors` senza FK | Deve funzionare anche se le tabelle applicative sono rotte | Log solo in n8n: non interrogabile via SQL |
| Cloudflare quick tunnel con `--protocol http2` | Nessun account, un comando; QUIC cadeva sulla rete domestica | ngrok (account, interstitial), named tunnel (dominio) |

## Debug di una catena distribuita

Ogni chiamata lascia tracce in quattro posti collegati da un identificativo comune, il `conversation_id` di ElevenLabs:

1. **ElevenLabs**: storico conversazioni con trascrizione e tool call.
2. **n8n**: esecuzioni (solo quelle fallite sono salvate), con input e output di ogni nodo.
3. **PostgreSQL**: `meter_readings.request_id` e `tickets.request_id` contengono il `conversation_id`; `calls.conversation_id` è la chiave; `workflow_errors.details.execution_url` punta all'esecuzione n8n.
4. **Tunnel**: il log di cloudflared mostra se la richiesta è arrivata.

Metodo usato durante lo sviluppo: partire dal sintomo (l'agente dice "errore tecnico"), verificare se la richiesta è arrivata a n8n (esecuzioni, tabella), poi al tunnel (log), poi all'agente (versione pubblicata). Ogni volta il problema era nel livello più esterno non ancora verificato.
