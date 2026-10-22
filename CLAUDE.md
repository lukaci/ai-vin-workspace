# Workspace

Soluzione automotive: identificare parti di ricambio da richieste in linguaggio naturale, legate a un veicolo (VIN, oppure targa convertita in VIN).
I dati arrivano dai provider, che espongono il catalogo come albero delle parti. Gli alberi cambiano molto tra brand; nello stesso brand il contenuto logico è simile, ma a parità di posizione i nomi dei nodi differiscono sempre un po'.

## Servizi

- **ai-vin-service**: servizio interno, API non esposte. Identificazione di base: gestisce i provider, persistenza/cache, naviga il catalogo con LLM.
- **ai-vin-app**: espone le funzionalità all'esterno: autenticazione, SPA, API di livello pari o superiore a quelle del servizio.
- **ai-vin-website**: sito vetrina statico (pre-renderizzato, nessun runtime server), bilingue IT/EN; lo stile resta allineato a quello di ai-vin-app.
- **ai-vin-logging**: libreria condivisa `@ai-vin/logging` che implementa le regole di [Logging](#logging); vendorizzata come tarball in `vendor/` di service e app (`bun run release ../ai-vin-service ../ai-vin-app`).

## Storage cache

`.s3/` è lo storage delle cache degli ambienti di test (bucket S3), montato in sola lettura (per ora): serve a consultare i dati.

- Attivazione: task VS Code all'apertura della cartella, oppure `.vscode/s3-mount.sh start` (background) / `umount`; se `.s3/` è vuota, non è montato.
- Consultazione: file normali da bash (`ls .s3/`, `cat`, `jq`), con letture mirate: ogni accesso è una richiesta di rete.

# Convenzioni

- TypeScript, runtime Bun, API con Hono.
- Stile funzionale: trasformazioni di alto livello (map, filter, flatMap, groupBy, ...), creando gli operatori mancanti.
- Valori opzionali con `undefined`, non `null`.
- Interfacce dove aggiungono valore, con giudizio.
- Integrazioni REST esterne: client generati dalla specifica OpenAPI con generatori open source.
- Release: tag `vX.Y.Z`, note in `CHANGELOG.md` di ogni repo tramite la skill `release-notes` del repo; commit e tag li fa l'utente.

# Logging

I log sono la tua fonte di diagnostica: devono ricostruire il percorso di una richiesta attraverso i servizi.
Usare sempre `@ai-vin/logging` (`apiLogger`, `logger.enter`/`logger.scope`, `httpClientLogging`, `loggingFetch`), non `console` diretto; dettagli in `ai-vin-logging/README.md`.

- Una riga per log: timestamp UTC `[YYYY-MM-DD HH:mm:ss.SSS]`, livello, request id, API, funzione, messaggio.
- Request id: riusato dall'header `X-Api-Request-Id` se valido, altrimenti un id casuale breve; propagato ai servizi interni e restituito nella risposta.
- Ogni API ha un nome logico e logga ingresso ed esito (status, durata).
- Le funzioni principali (pubbliche, di dominio, integrazioni) loggano come prima istruzione nome e parametri, poi l'esito: trovato/non trovato, conteggi.
- Livelli:
  - error: imprevisto che interrompe l'operazione, loggato una volta, con stack;
  - warn: anomalia gestita;
  - info: flusso normale (ingressi, esiti, cache hit/miss, fallback, retry, chiamate esterne);
  - debug: prompt, payload, stato interno; messaggi costruiti solo se il livello è attivo.
- Parametri troncati; buffer e base64 come dimensione (contenuto solo a debug); segreti sempre mascherati.
- Formato e livello da `LOG_FORMAT` / `LOG_LEVEL`.
