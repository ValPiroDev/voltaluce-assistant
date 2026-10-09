# Script della demo: frasi di test per l'agente

Frasi da dire (o scrivere nel widget di test di ElevenLabs) per mostrare ogni percorso, con il
comportamento atteso e cosa verificare nel database. Dati dal seed (`db/seed.sql`).

Prima della demo: `scripts/demo.ps1`, URL del tunnel nei tre tool e nel post-call, agente pubblicato.

## Clienti utili

| Codice | Nome | Forniture | Caso |
|---|---|---|---|
| CL-00001 | Marco Bianchi | luce + gas | bolletta luce da pagare; ultima lettura luce 15900 (dopo i test) |
| CL-00002 | Giulia Rossi | luce | bolletta **scaduta** 71,80 |
| CL-00003 | Antonio Esposito | luce + gas | tutto pagato; usato per i ticket |
| CL-00004 | Francesca Colombo | gas | bolletta gas da pagare |
| CL-00005 | Luca Ferrari | luce (gas **inattivo**) | gas senza bollette e senza fornitura attiva |
| CL-99999 | nessuno | - | cliente inesistente |

Prima di una demo "pulita" si può rilanciare il seed, che azzera letture e ticket di test:
`docker exec -i voltaluce_postgres psql -U postgres -d voltaluce < db/seed.sql`
(le tabelle `calls` e `workflow_errors` vengono svuotate anch'esse).

## 1. Ultima bolletta (get_ultima_bolletta)

**1a. Caso felice, bolletta scaduta**
> Buongiorno, il mio codice cliente è CL zero zero zero zero due. Quanto devo pagare?

Atteso: l'agente ripete il codice per conferma, chiama il tool, dice "fornitura luce, 71 euro e 80,
periodo dal primo giugno al 31 luglio 2026, scadenza 31 agosto 2026, scaduta e non ancora pagata".

**1b. Bolletta da pagare, non scaduta**
> Codice CL-00001, mi dici l'ultima bolletta?

Atteso: bolletta gas da 31 euro e 75 (è l'ultima emessa tra luce e gas, stesso giorno, vince l'id più
alto), scadenza 31 ottobre 2026, ancora da pagare.

**1c. Cliente inesistente (404)**
> Codice CL-99999, quanto devo pagare?

Atteso: "non trovo nessuna bolletta per questo codice", chiede di ricontrollare o propone una
segnalazione. Non inventa importi.

**1d. Codice detto male (400 o richiesta di ripetere)**
> Il mio codice è 12345, quanto devo?

Atteso: l'agente chiede il codice nel formato corretto (CL più cinque cifre). Se chiama comunque il
tool, riceve 400 e chiede di ripetere.

## 2. Autolettura (invia_autolettura)

**2a. Caso felice**
> Codice CL-00001, vorrei comunicare la lettura del contatore della luce: 16000.

Atteso: ripete "16000 per la luce, confermo?"; alla conferma chiama il tool e dice "registrata la
lettura 16000, la precedente era 15900".
Verifica: `select value, request_id from meter_readings order by id desc limit 1;`
(`request_id` = `conv_...:electricity:16000`).

**2b. Idempotenza: stessa richiesta ripetuta nella stessa conversazione**
> Rimanda la stessa lettura, 16000, per sicurezza.

Atteso: il tool risponde 200 con `duplicate: true`; l'agente dice che la lettura risulta già
registrata. In tabella nessuna riga nuova.

**2c. Valore inferiore all'ultima lettura (422)**
> Scusi, ho letto male: il valore giusto è 15000.

Atteso: l'agente chiama comunque il tool (regola del prompt), riceve 422 e dice "15000 è inferiore
all'ultima lettura registrata, 16000 del [data]; la invito a ricontrollare il contatore". Non dice
"non si può modificare".

**2d. Correzione verso l'alto (nuova lettura accettata)**
> Allora è 16050.

Atteso: registrata, precedente 16000. Mostra che una correzione è una lettura nuova, non un duplicato.

**2e. Fornitura non attiva (404)**
> Ho anche il gas, codice CL-00005, lettura 3000.

Atteso: "per il codice CL-00005 non risulta una fornitura gas attiva: non posso registrare letture
per questa fornitura", propone una segnalazione. Non dice "cliente non trovato".

**2f. Prima lettura in assoluto**
> Codice CL-00004, lettura gas 4200.

Atteso: registrata, precedente 4120 (dal seed). Con il seed appena rilanciato CL-00005 luce non ha
letture: `Codice CL-00005, lettura luce 100` → registrata, nessuna precedente.

**2g. Valore non numerico (400)**
> Codice CL-00001, lettura luce: abc.

Atteso: l'agente di solito non chiama il tool e chiede un numero; se lo chiama, 400 "valore must be a
number" e richiede il valore.

## 3. Segnalazione (apri_ticket)

**3a. Caso felice**
> Codice CL-00003. Da due giorni il contatore del gas fa un rumore strano, vorrei che qualcuno lo controllasse.

Atteso: riformula o chiede conferma della descrizione, chiama il tool, dice "ho aperto la segnalazione
numero N per Antonio, un operatore la contatterà".
Verifica: `select id, priority, description, request_id from tickets order by id desc limit 1;`

**3b. Priorità alta**
> Codice CL-00001, sento odore di gas in casa.

Atteso: ticket con `priority = high` (il prompt del parametro dice "alta solo per guasti, odore di gas o
assenza di fornitura"); l'agente dovrebbe anche invitare a chiamare il numero di emergenza.

**3c. Idempotenza: secondo ticket nella stessa conversazione**
> Apri un'altra segnalazione per lo stesso problema.

Atteso: 200 con `duplicate: true`; "risulta già una segnalazione aperta in questa conversazione".

**3d. Richiesta fuori ambito → ticket**
> Vorrei cambiare l'intestatario del contratto.

Atteso: l'agente dice che non può farlo direttamente e propone una segnalazione; alla conferma apre
il ticket con la descrizione.

**3e. Cliente inesistente (404)**
> Codice CL-99999, voglio fare una segnalazione per la bolletta.

Atteso: "non trovo nessun cliente con questo codice", chiede di ricontrollarlo.

## 4. Post-call webhook

Dopo **ogni** conversazione chiusa (End nel widget), entro circa un minuto:

```sql
select id, conversation_id, customer_id, duration_sec, outcome,
       metadata->'tools_used' as tools, metadata->>'summary' as summary
from calls order by id desc limit 1;
```

Atteso: una riga con durata, esito, tool usati e riassunto. `customer_id` è valorizzato solo se nella
tab Analysis dell'agente esiste il data collection item `codice_cliente`.

Simulazione senza chiamata (firma valida, riconsegna, firma errata, timestamp vecchio, body
manomesso, header mancante): `bash scripts/test_post_call.sh`.

## 5. Error workflow

`bash scripts/test_error_workflow.sh`: manda al post-call un payload firmato ma malformato; il Code
lancia un'eccezione, n8n risponde 500 e `error_handler` scrive in `workflow_errors`:

```sql
select workflow_name, node_name, message, details->>'execution_url' from workflow_errors order by id desc limit 1;
```

## 6. Sequenza consigliata per una demo di 5 minuti

1. `demo.ps1` già lanciato, mostrare l'URL e il canvas di `invia_autolettura` in n8n.
2. Chiamata vocale: 1a (bolletta scaduta di Giulia).
3. Stessa chiamata: 2a poi 2c (lettura accettata, poi valore troppo basso rifiutato).
4. Stessa chiamata: 3a (ticket per Antonio), chiudere la chiamata.
5. In psql: ultima riga di `meter_readings`, `tickets` e, dopo un minuto, `calls`.
6. Se chiedono gli errori: `test_error_workflow.sh` e la riga in `workflow_errors`.
