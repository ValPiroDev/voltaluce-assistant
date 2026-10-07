# VoltaLuce Assistant - ElevenLabs agent configuration

Everything in this file is entered by hand in the ElevenLabs dashboard (Agents section).
Field labels may change: check https://elevenlabs.io/docs/eleven-agents when something does not match.

## Agent settings

| Field | Value |
|---|---|
| Name | VoltaLuce Assistant |
| Language | Italian |
| LLM | the default suggested by ElevenLabs (a tool-capable model) |
| Voice | any Italian voice from the library |
| First message | see below |
| System prompt | see below |

### First message

```
Buongiorno, sono l'assistente virtuale di VoltaLuce. Posso darti informazioni sulla tua ultima bolletta, registrare un'autolettura del contatore o aprire una segnalazione. Per iniziare, mi dici il tuo codice cliente?
```

### System prompt

```
Sei l'assistente vocale di VoltaLuce, un fornitore italiano di luce e gas. Parli in italiano, con tono cordiale e professionale, frasi brevi adatte al telefono.

COSA PUOI FARE
1. Dire al cliente importo, periodo, scadenza e stato di pagamento della sua ultima bolletta (tool get_ultima_bolletta).
2. Registrare un'autolettura del contatore (tool invia_autolettura).
3. Aprire una segnalazione per un operatore umano (tool apri_ticket).

REGOLE
- Prima di usare qualsiasi tool devi avere il codice cliente. Ha il formato "CL" seguito da cinque cifre, per esempio CL-00001. Se il cliente lo detta a voce, ripetilo per conferma prima di procedere ("Confermo: CL zero zero zero zero uno, corretto?").
- Non inventare mai dati: importi, date e stati arrivano solo dai tool. Se un tool fallisce o non trova nulla, dillo chiaramente e proponi di aprire una segnalazione.
- Leggi gli importi in euro con i centesimi ("98 euro e 20") e le date in forma parlata ("31 ottobre 2026").
- Se lo stato della bolletta è "unpaid" di' "ancora da pagare"; se è "overdue" di' "scaduta e non ancora pagata"; se è "paid" di' "regolarmente pagata".
- Per il tipo di fornitura: "electricity" si dice "luce", "gas" si dice "gas".
- Per l'autolettura chiedi sempre: tipo di fornitura (luce o gas) e il valore letto sul contatore, solo le cifre intere prima della virgola. Ripeti il valore prima di inviarlo.
- Se il cliente corregge un valore appena comunicato, invia SEMPRE la nuova lettura con il tool invia_autolettura: è il sistema a decidere se accettarla. Non dire mai che una lettura non si può correggere o modificare.
- Se il tool risponde che il valore è inferiore all'ultima lettura registrata, riferisci al cliente quel valore e quella data e chiedi di ricontrollare il contatore; non suggerire mai di comunicare un valore piu basso in futuro.
- Se il cliente chiede qualcosa fuori da questi tre servizi, o se non sai rispondere, offri di aprire una segnalazione e chiedi una breve descrizione del problema.
- Non chiedere mai dati di pagamento, IBAN o documenti.
- Chiudi la conversazione riassumendo in una frase cosa è stato fatto.
```

## Tool 1: get_ultima_bolletta (Webhook tool)

| Field | Value |
|---|---|
| Tool type | Webhook |
| Name | `get_ultima_bolletta` |
| Description | `Restituisce l'ultima bolletta emessa per un cliente: importo, periodo, scadenza, stato di pagamento e tipo di fornitura. Usalo quando il cliente chiede informazioni sulla sua bolletta. Richiede il codice cliente nel formato CL-00000.` |
| Method | `POST` |
| URL | the public tunnel URL printed by `scripts/start_tunnel.ps1`, followed by `/webhook/get-ultima-bolletta`. Type it literally, e.g. `https://xxxx-yyyy.trycloudflare.com/webhook/get-ultima-bolletta`. Do not use `{{ }}`: ElevenLabs treats that as a dynamic variable. |
| Headers | `Content-Type: application/json` and `x-api-key: <value of WEBHOOK_API_KEY from .env>` |
| Body parameters | one parameter, see below |

Body parameter:

| Field | Value |
|---|---|
| Identifier | `codice_cliente` |
| Data type | String |
| Value type | LLM prompt (the model fills it from the conversation) |
| Description | `Codice cliente nel formato CL seguito da trattino e cinque cifre, per esempio CL-00001. Normalizza quello che il cliente ha dettato: maiuscole, nessuno spazio.` |
| Required | yes |

Response handling: the JSON body is returned to the LLM as-is. Status 404 means no bill for that code; the agent must tell the customer and offer a ticket.

Tool-level options to look for in the UI (names may differ): a timeout (set 10 s), and "tool interruptions" (leave the default).

## Tool 2: invia_autolettura (Webhook tool)

| Field | Value |
|---|---|
| Tool type | Webhook |
| Name | `invia_autolettura` |
| Description | `Registra l'autolettura del contatore di un cliente per una fornitura (luce o gas). Usalo solo dopo aver ripetuto al cliente il valore letto e ottenuto conferma. Richiede codice cliente, tipo di fornitura e valore numerico intero letto sul contatore.` |
| Method | `POST` |
| URL | same tunnel base URL as tool 1, followed by `/webhook/invia-autolettura` |
| Headers | `Content-Type: application/json` and `x-api-key: <value of WEBHOOK_API_KEY from .env>` |
| Body parameters | four parameters, see below |

Body parameters:

| Identifier | Data type | Value type | Description (LLM prompt) / value |
|---|---|---|---|
| `codice_cliente` | String | LLM prompt | `Codice cliente nel formato CL-00000, maiuscolo, senza spazi.` |
| `tipo_fornitura` | String | LLM prompt | `Tipo di fornitura: esattamente "luce" oppure "gas".` |
| `valore` | String | LLM prompt | `Valore letto sul contatore, solo cifre, senza unità di misura. Esempio: 15800.` |
| `conversation_id` | String | Dynamic variable | `system__conversation_id` (built-in ElevenLabs variable, used as idempotency key) |

Response handling: 200 with `duplicate:false` => confirm to the customer with the registered value; 200 with `duplicate:true` => tell the customer the reading was already registered; 422 => read `message`, explain that the value is lower than the last reading (`last_value`) and ask to check the meter; 404 => no active supply of that type; 400 => repeat the question for the wrong field.

Note: `valore` is declared as String on purpose. Numbers dictated by voice may contain spaces or commas; the webhook normalizes and validates them (400 if not numeric or negative).

## Tool 3: apri_ticket

Defined on Day 3.
