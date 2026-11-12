# ai-vin-app: harness agentico sì/no, e come consolidare

Analisi del 2026-11-10 su `ai-vin-app` ramo `feat/dev/prasco` (release 0.8.0, `ef4cb51`), più `feat/dev/licensing` (`1bd233b`).
Fonti esterne con citazioni in [`research-online.md`](./research-online.md); requisiti contrattuali dal Contratto Prasco (06/08/2026) e dall'Offerta integrativa AIV-2026-PRA001 (15/10/2026), riportati qui solo nelle regole che toccano l'architettura.

## 1. Cosa fa oggi ai-vin-app

| Area | Implementazione | Dove | Note |
|---|---|---|---|
| Chat | AI SDK v5: `streamText` dentro `createUIMessageStream`, `gpt-4o` fisso, 6 tool (vehicle, part, unit, get-unit, applicability, part-list), `stopWhen` custom | `server/routes/aivin.ts`, `server/lib/aivin/tools.ts` | nessuna persistenza: il client rimanda tutta la history a ogni turno; refresh = chat persa; niente resume dello stream |
| Tool streaming | parti dati transienti `data-tool-incremental` scritte dal tool via `experimental_context.writer`; hook client `useChatWithIncremental` | `server/lib/aivin/incremental.ts`, `client/src/hooks/use-chat-with-incremental.ts` | funziona, ma è un meccanismo fatto in casa; transient = non finisce nel messaggio, quindi non sarebbe persistito |
| Rendering tool result | componenti React per tipo di tool (`getToolName(part)`) | `client/src/components/primitives/aivin.tsx`, `aivin-part-result.tsx` (813 righe) | è la parte di maggior valore lato UI: nessun framework la sostituisce, va solo preservata |
| API v1 | 14 endpoint Hono (vehicle, part-search, assembly, part-list, part-applicability, `/cross`, upload cross, async + `/jobs/:id`) | `server/routes/v1-api.ts` | OpenAPI `1.0.0-draft-14` |
| Job async | promise fire-and-forget + LRU in memoria (10k job, TTL 30 min), webhook non implementato | `server/lib/api/v1/jobs.ts` | job persi a ogni restart/deploy; non condivisi tra istanze |
| Auth | JWT HS256 in cookie, utenti da `AUTH_USERS`, API key da `AUTH_API_KEYS` (env) | `server/lib/auth.ts` | dipendenze Clerk presenti ma di fatto inutilizzate (solo `SignUp.tsx`) |
| Gateway | rate limit, ban, allow-list per client, usage counter; store in memoria con interfacce async | `server/gateway/` | **montaggio commentato** in `server/index.ts` |
| Licensing | engine reserve/commit per licenza, limiti globali/feature/route a finestre (mese solare, TZ), plugin di risoluzione (client-id, header) | `server/licensing/` solo su `feat/dev/licensing` | non mergiato; in memoria; conta **richieste**, non UdV |
| Dati di riferimento | cross SKU→OE e assembly groups: xlsx (S3 o locale) → sqlite locale via `Bun.SQL`, singleton caricato all'avvio | `server/lib/cross/`, `server/lib/assemblygroups/` | upload cross aggiorna solo l'istanza che lo riceve (TODO "sincronizzazione tra istanze") |
| Datasets | upload wizard, analisi colonne con LLM (`generateObject`), un sqlite per schema, query solo `SELECT` | `server/lib/datasets/`, `client/src/pages/Datasets*.tsx` | **route commentate**: feature parcheggiata ma già quasi un "datasource per l'agente" |
| Storage | `Bun.s3` + file sqlite locali | — | nessun DB applicativo centrale |
| Logging | `@ai-vin/logging` | ovunque | ok, da riusare in qualsiasi scelta |
| Scheduler | nessuno | — | — |

Osservazione chiave: la parte "agentica" (chat + tool) è piccola e già sul framework giusto. Il grosso di ciò che manca è **piattaforma applicativa deterministica** (stato persistito, job, schedulazioni, licenze, metering, export), che un harness agentico non risolve.

## 2. Requisiti che arrivano dal contratto (vincolanti)

Dal Contratto, art. 1–3, 6, 10, e dall'Offerta integrativa, art. 1 e 5:

1. **Unità di misura = UdV**, non la chiamata: una ricerca VIN *con esito positivo* e da 1 a 10 righe verificate.
   - API singola: `ceil(righe / 10)` UdV per chiamata (12 righe = 2 UdV);
   - API batch: per ogni VIN distinto `ceil(righe del VIN / 10)` (10 VIN / 102 righe = 11 UdV).
   - Quindi il conteggio si fa **dopo** l'esecuzione, sul risultato: un middleware che conta richieste HTTP (come `server/licensing/` oggi, `countOn: success`) non basta.
2. **Per licenza**, identificata da un "Attributo API" = `cliente_id` del Cliente Ricambista (una licenza per Cliente Ricambista; accessi Prasco filiali/QA senza limite).
3. **Finestra mensile**: soglia inclusa per licenza al mese, eccedenza fatturata fino a un tetto di UdV extra per licenza al mese. Da chiarire se oltre il tetto si **blocca** (429) o si continua senza fatturare: cambia l'engine (hard limit vs solo conteggio).
4. **Fatturazione mensile offline** (bonifico, fattura): serve un **report mensile per licenza** (UdV incluse/eccedenti), non un payment provider.
5. **Dashboard di reportistica con dati aggregati** di utilizzo per Prasco.
6. **Registro delle ricerche** (Offerta art. 5): data/ora, `cliente_id`, VIN, codice cercato, codice Prasco corrispondente, esito; **cancellazione dopo 6 mesi** (retention automatica = un job schedulato).
7. **Canale API e/o SFTP** (Offerta art. 1.d): Prasco carica periodicamente il tracciato e scarica le esportazioni delle ricerche, "con i relativi processi automatici di aggiornamento" → import/export schedulati + area download.
8. **Riconciliazione** (art. 3): UdV per Attributo API devono essere ricostruibili e confrontabili con i registri ordini di Prasco → il ledger delle UdV va persistito per riga, non solo come contatore.

Questi punti definiscono il cuore del lavoro: sono deterministici, auditabili, legati a soldi. Vanno in codice nostro, testato, non in un agente.

## 3. La distinzione che decide tutto: agente vs piattaforma

| Bisogno | Natura | Chi lo risolve bene |
|---|---|---|
| chat, tool, streaming, rendering tool result | agente + UI | AI SDK (già in uso) |
| persistenza chat | stato applicativo | una tabella; i framework la danno pronta |
| skill (SKILL.md) | agente | due tool o `bash-tool`; i framework la danno pronta |
| dataset per l'agente (cross, assembly groups, datasets) | dati + tool | codice nostro (sqlite già in uso, DuckDB opzionale) |
| job async API, import/export schedulati, retention, report mensili | piattaforma deterministica | scheduler + tabella job; nessun harness agentico lo risolve per intero |
| area export | piattaforma | S3 + presigned URL + tabella |
| licenze, UdV, ledger, riconciliazione | piattaforma, contrattuale | **solo codice nostro**: nessuna libreria conosce la UdV |

Tre quarti del lavoro sono nella colonna "piattaforma". Un harness agentico (Deep Agents, Mastra, eve) aggiunge valore solo sulla prima metà della tabella, che è quella già funzionante. Migrare l'agente su un harness non avvicina i requisiti contrattuali.

## 4. Opzioni valutate

Dettagli, versioni e fonti in [`research-online.md`](./research-online.md). Sintesi:

| Opzione | Copre | Contro per noi | Verdetto |
|---|---|---|---|
| **AI SDK v7 + moduli nostri** | chat, UI, tool streaming (anche risultati parziali nativi), approvazioni, MCP | persistenza, scheduler, skill da scrivere (poco codice); resume dello stream standard = Redis | **scelta consigliata** |
| Mastra 1.x | agente, memoria su LibSQL, workflow con cron, skill SKILL.md, workspace S3, resume senza Redis su processo singolo; stream compatibili AI SDK v7; gira su Bun (verificato) | lock-in medio-alto sul modello Agent/Workflow/Memory; API in evoluzione rapidissima (core 1.0 → 1.82 in 10 mesi); cron *best-effort* (occorrenze perse non rigiocate), inadatto da solo a export contrattuali; non tocca licenze/UdV | alternativa valida se l'agente cresce (più agenti, run lunghe) |
| Workflow DevKit + `WorkflowAgent` | durabilità vera, resume senza Redis | in produzione serve Postgres (World "reference", senza auth) o Local World "solo dev"; build Nitro con Hono; niente cron | no ora; riconsiderare per run lunghe |
| eve (Vercel) | skill, schedule, run durevoli in un pacchetto | release candidate; struttura di progetto propria, servizio separato | no ora; rivalutare dopo la 1.0 |
| LangChain Deep Agents / LangGraph | harness più ricco (todo, FS virtuale, subagent, skill) | UI `useStream` legata all'Agent Server (self-host = Postgres + Redis + licenza Enterprise); perderemmo la UI AI SDK e 800+ righe di rendering | no |
| Claude Agent SDK | skill, sessioni, subagent | legato a modelli Claude e al binario Claude Code; licenza commerciale | no come runtime della chat |
| Inngest / Trigger.dev | job durevoli, cron | servizio in più (Inngest self-host in beta, SSPL; Trigger.dev 7+ vCPU, Postgres, Redis) | no |
| Lago / OpenMeter / Polar / Stripe | billing e crediti | stack pesanti o orientati a carta; la UdV va calcolata comunque da noi | no: ledger interno |

### Verifiche fatte qui (Bun 1.4.4)

- `ai@7.0.168` (`streamText` + tool + `toUIMessageStream`): funziona su Bun, nonostante la guida citi solo Node 22+.
- **Risultati parziali dei tool nativi**: un `execute` come `async function*` che fa `yield` produce `tool-output-available` con `preliminary: true`, poi l'output finale. È quello che oggi fa a mano `incremental.ts` + `useChatWithIncremental`, ma l'output finale resta nel messaggio (persistibile).
- `@duckdb/node-api@2.0.0-r.1`: funziona su Bun. L'estensione `excel` (scrittura xlsx) si scarica a runtime da internet: in produzione va preinstallata nell'immagine.
- `Bun.cron`: presente.
- Mastra (`@mastra/core` + `@mastra/memory` + `@mastra/libsql`): agente con memoria su file SQLite funziona su Bun, messaggi persistiti.

## 5. Raccomandazione

**Non migrare a un harness.** Restare su AI SDK (aggiornando a v7) e consolidare il resto in pochi moduli nostri sopra **un solo database applicativo**, con S3 per i file. Nessun servizio nuovo.

### 5.1 Architettura target

```
                 ai-vin-app (un processo Bun, Hono)
 ┌───────────────────────────────────────────────────────────────────┐
 │  API v1 ──► identity ─► license guard ─► handler ─► UdV metering    │
 │  Chat   ──► AI SDK v7 agent ─► tool ─► (stessi handler)              │
 │                                                                     │
 │  jobs + scheduler ─► import cross · export ricerche · report mensile │
 │                     · retention 6 mesi · job async API               │
 │  datasets (snapshot sqlite per istanza, versionati da ETag S3)       │
 │  skills (SKILL.md) · area export (presigned S3)                      │
 └───────────────┬───────────────────────────────┬─────────────────────┘
                 │ Bun.SQL                        │ Bun.s3
          DB applicativo                     S3 (file, export, snapshot)
   (SQLite su volume se 1 istanza,
    Postgres gestito se N istanze)
```

Parti mobili: oggi app + S3 (+ ai-vin-service). Domani: app + S3 + DB. Con istanza singola il DB è un file: zero servizi in più.

`Bun.SQL` (già usato per cross e datasets) parla sia SQLite sia Postgres: scrivendo SQL portabile, il passaggio da file a Postgres resta un cambio di URL più qualche differenza di dialetto, non una riscrittura.

### 5.2 Moduli

1. **Agente (chat)**
   - AI SDK v7: `ToolLoopAgent` con gli stessi tool; codemod 5→6→7.
   - Tool streaming: `execute` a generatore (risultati preliminari) al posto di `data-tool-incremental`; il rendering per stato della tool part resta nei componenti attuali.
   - Persistenza: tabelle `chat_thread` / `chat_message` (UIMessage JSON), salvataggio in `onEnd`, id generati dal server, `consumeStream` per finire la generazione se il client si disconnette, client che invia solo l'ultimo messaggio.
   - Resume dello stream in corso: rinviare. Se servirà: replay dei chunk da tabella (in casa) prima di introdurre Redis.
   - Componenti UI: tenere prompt-kit e i componenti attuali; AI Elements è in deprecazione (fine novembre 2026) e orientato a Next.js.
2. **Skill**
   - Cartella `skills/<nome>/SKILL.md` (spec Agent Skills), su S3 o nell'immagine.
   - Nel system prompt solo nome + descrizione; tool `load_skill(nome)` e `read_skill_file(nome, path)` per la progressive disclosure: circa 100 righe nostre, nessuna dipendenza.
   - `bash-tool` / `just-bash` (beta) solo se le skill dovranno eseguire script; allora conviene anche come sandbox dati.
3. **Datasets**
   - Un modulo unico per cross, assembly groups e datasets utente: sorgente su S3 (xlsx/csv) → snapshot sqlite locale, versione = ETag; un job periodico confronta l'ETag e ricarica. Risolve anche "Cross: sincronizzazione tra istanze" senza storage condiviso.
   - Tool agente `query_dataset` (solo `SELECT`, limite righe) riusando `server/lib/datasets/` (route oggi commentate).
   - DuckDB solo se servono analisi su file grandi o scrittura xlsx efficiente; altrimenti la libreria `xlsx` già presente basta.
4. **Job e scheduler**
   - Tabella `job` (tipo, payload, stato, tentativi, risultato, chiave di idempotenza) al posto dell'LRU in memoria: i job async dell'API sopravvivono ai deploy e il webhook ha dove salvare i tentativi.
   - Schedulazioni dichiarate in codice (`Bun.cron` o `croner`), che **creano** un job con chiave `(schedulazione, periodo)`: all'avvio si recuperano i periodi mancati (catch-up), il job non parte due volte.
   - Con più istanze: lock del leader (advisory lock Postgres o riga con scadenza).
   - Job previsti: import cross da S3, export ricerche per Prasco, report mensile UdV per licenza, retention a 6 mesi, refresh snapshot datasets.
5. **Area export**
   - Tabella `export` (tipo, licenza/cliente, periodo, chiave S3, righe, stato) + download con URL S3 presigned (`Bun.s3` lo supporta).
   - API per Prasco (`GET /v1/exports`, `GET /v1/exports/:id`) e pagina nella SPA (pannello admin).
   - SFTP: l'Offerta dice "API e/o SFTP". Un server SFTP è un servizio in più (o AWS Transfer Family): proporre l'API come canale, SFTP solo se Prasco lo pretende.
6. **Licenze e UdV** (il pezzo con più valore e più rischio)
   - Riusare dal ramo `feat/dev/licensing` i concetti buoni (risoluzione licenza a plugin, finestre di calendario con timezone, reserve/commit) ma spostando licenze e contatori **nel DB**, gestiti dal pannello admin, non da YAML: le licenze si attivano nel tempo.
   - Pipeline per richiesta: identità (API key → account) → licenza (attributo API = `cliente_id`) → guardia (licenza valida, API abilitata, tetto mensile) → handler → **metering sul risultato**.
   - Calcolo UdV dal risultato: VIN con esito positivo, `ceil(righe/10)`; batch: per VIN distinto. Il massimo è noto prima di eseguire (dalle righe in input): si **riserva il massimo e si conferma il reale**, così due richieste concorrenti non sforano il tetto.
   - Ledger `usage_event` per richiesta (request id, licenza, API, VIN, righe, UdV, esito) e registro ricerche per riga (campi dell'Offerta art. 5): servono a fatturazione, dashboard aggregata, export per Prasco e riconciliazione. La retention a 6 mesi vale per il registro ricerche; per il ledger UdV va decisa (serve per la fatturazione e per le verifiche art. 3).
   - Licenze Prasco filiali/QA: licenza senza limite, ma comunque misurata.
   - Gateway (rate limit, ban): resta in memoria, va solo rimontato.

### 5.3 Quando scegliere Mastra

Se nei prossimi mesi l'agente diventa il centro del prodotto (più agenti, run lunghe con sospensione e approvazioni, agenti schedulati che lavorano da soli), Mastra dà già memoria, workflow, skill e workspace su SQLite, e convive con AI SDK v7 lato UI. Anche in quel caso licenze, UdV, export e retention restano codice nostro. La scelta di oggi non la preclude: i tool, gli handler e il DB restano gli stessi.

## 6. Piano a fasi

Ordine guidato dal contratto: prima ciò che si fattura e che l'Offerta impegna.

| Fase | Contenuto | Esito |
|---|---|---|
| 0 | DB applicativo (`Bun.SQL`, migrazioni), tabella `job` al posto dell'LRU, scheduler con catch-up | base comune |
| 1 | identità e licenze su DB, guardia per API, metering UdV, ledger, registro ricerche, retention | obblighi Contratto art. 2–3 e Offerta art. 5 |
| 2 | export ricerche e report mensile UdV schedulati, area export (API + pagina), import cross da S3 schedulato | Offerta art. 1.c–d; sync cross tra istanze |
| 3 | pannello admin: licenze, export, caricamenti | TODO "Pannello di amministrazione" |
| 4 | AI SDK 5→7, tool a generatore, persistenza chat | consolidamento chat |
| 5 | skill e `query_dataset` | nuove capacità agente |

La fase 4 è indipendente: si può anticipare, ma non sblocca nulla di contrattuale.

## 7. Decisioni aperte (prima tornata)

Risposte del 2026-11-12 nella sezione 8.1; restano aperte le 4, 6, 7 e quelle nuove della sezione 8.9.

1. ~~**Istanze**~~ → una istanza per cliente oggi, da superare.
2. ~~**Tetto UdV**~~ → oltre il tetto l'API rifiuta.
3. ~~**Attributo API**~~ → `cliente_id` nei `metadata`, ma il meccanismo deve essere configurabile.
4. **API batch**: oggi entrambe le applicability (`/part-applicability`, `/part-applicability/cross`, sync e async) sono **a VIN singolo** (`vehicle_id` + `parts[]`): un'API batch multi-VIN non esiste. Il metering la prevede comunque (sezione 8.5).
5. ~~**SFTP**~~ → no, solo API (anche per scaricare gli export).
6. **Retention del ledger UdV**: i 6 mesi dell'Offerta valgono per il registro ricerche; il ledger di fatturazione va tenuto di più (verifiche fino a due volte l'anno).
7. **Clerk**: dipendenze presenti ma inutilizzate (auth custom). Proposta nella sezione 8.6: sostituire con Better Auth.

## 8. Aggiornamento 2026-11-12: licenze configurabili, multi-tenant, admin

### 8.1 Decisioni prese

| Tema | Decisione | Conseguenza |
|---|---|---|
| Tetto UdV | oltre il tetto mensile (incluse + extra) l'API **rifiuta** | limite rigido: serve prenotazione atomica (reserve/commit), non solo conteggio |
| Identificazione licenza | oggi `cliente_id` nei `metadata`, ma **non fisso**: il cliente sceglie il plugin (API key, campo dei metadata, ...), genera le API key, gestisce le licenze assegnando i seat | risoluzione della licenza = configurazione per tenant su DB, non YAML |
| Canale | niente SFTP: import ed export solo via API | area export = API di elenco e download |
| Deploy | una istanza per cliente, vissuta come limite | progettare **multi-tenant** da subito; più istanze condivise in prospettiva |
| UdV | concetto **solo dell'applicability** | il metering è per API: ogni API ha la sua unità; le API senza unità a contratto sono disabilitate per quel cliente |
| Rate limit e API abilitate | **configurabili da un admin**, non fissi | gateway con configurazione su DB e pannello admin |

### 8.2 Ruoli: chi configura cosa

Due livelli di amministrazione, perché il cliente non deve poter superare il contratto:

| Ruolo | Chi | Può |
|---|---|---|
| **Admin piattaforma** | AIVIN | crea i tenant; definisce il **piano** del tenant (API abilitate, unità e limiti per API, numero di seat acquistati, tetto mensile per seat, rate limit massimi, plugin di risoluzione ammessi, validità, timezone); vede tutto, sospende |
| **Admin tenant** | Prasco | sceglie e configura il plugin di risoluzione (tra quelli ammessi); genera e revoca API key; **assegna i seat** (es. `cliente_id` → seat) entro il numero acquistato; restringe (mai allarga) API e rate limit per singola key; programma export e import; scarica export e report |
| Operatore tenant | utenti Prasco | consultazione: dashboard aggregata, export |

Regola: la configurazione effettiva è sempre **l'intersezione** piano ∩ configurazione del tenant ∩ permessi della key.

### 8.3 Modello dati (essenziale)

```
tenant ─┬─ plan (1, versionato: api abilitate, meter, limiti, seat acquistati, rate limit max)
        ├─ member (utente + ruolo nel tenant)
        ├─ api_key (hash, prefisso, permessi = sottoinsieme delle API del piano, rate limit ≤ piano, metadata)
        ├─ resolver_config (ordine, tipo plugin, parametri: es. { type: "metadata", path: "cliente_id" })
        ├─ seat (tipo: metered | unlimited, stato: active | deactivated, go_live, deactivated_at)   ← acceso da AIVIN (8.13)
        ├─ seat_binding (seat, plugin, external_id = cliente_id o key, bound_at, bound_by)        ← associato dal cliente, una volta sola
        ├─ quota_counter (seat, meter, periodo, used, reserved)
        ├─ usage_event (request_id, seat, api, meter, unità, esito, ts)          ← fatturazione, riconciliazione
        ├─ search_log (request_id, seat, VIN, codice, codice Prasco, esito, ts)    ← Offerta art. 5, retention 6 mesi
        ├─ schedule (tipo job, cron, timezone, parametri, next_run_at)
        ├─ job (tipo, payload, stato, tentativi, chiave idempotenza)
        ├─ dataset (nome, tipo: generic | cross | ..., versione attiva)                    ← 8.18
        ├─ dataset_version (file originale S3, snapshot normalizzata S3, mappatura colonne, statistiche, report di validazione, stato)
        ├─ export (tipo, periodo, chiave S3, righe, stato)
        └─ audit_log (chi, cosa, su cosa, prima/dopo, quando: solo append)             ← operazioni utente e admin (8.17)
```

Tutte le tabelle applicative hanno `tenant_id`: è ciò che permette di passare da "una istanza per cliente" a "più clienti per istanza" senza riscrivere.

### 8.4 Risoluzione della licenza a plugin

Il ramo `feat/dev/licensing` ha già l'idea giusta (plugin ordinati, il primo che risolve vince, l'engine resta unico). Cambia la fonte della configurazione: da YAML a `resolver_config` del tenant.

Plugin previsti:

| Tipo | Parametri | Seat = |
|---|---|---|
| `api-key` | — | la key (una key per Cliente Ricambista) |
| `metadata` | path nel body (es. `cliente_id`, `customer.code`) | il valore trovato |
| `header` | nome header | il valore dell'header |

- Il plugin estrae solo l'identificativo: validità, limiti e conteggio restano all'engine, uguali per tutti i plugin.
- Identificativo assente o sconosciuto: **rifiuto** (403) di default. L'attivazione automatica di un seat al primo uso, se mai servisse, va abilitata dall'admin piattaforma (consuma un seat acquistato).
- Confine di fiducia: con `metadata`/`header` la key autentica il server Prasco e il seat lo dichiara Prasco; il contratto già prevede la verifica a posteriori (riconciliazione con i registri ordini), che il nostro `usage_event` rende possibile.

### 8.5 Metering per API

Un piccolo catalogo in codice di **meter** (funzioni pure richiesta + risposta → unità); il piano assegna a ogni API abilitata il suo meter e i limiti.

| Meter | Unità | Massimo prima dell'esecuzione | Valore reale (dalla risposta) |
|---|---|---|---|
| `udv` | UdV | Σ per VIN `ceil(righe/10)` | 0 se `vehicle_found` è falso, altrimenti come il massimo |
| `request` | chiamate | 1 | 1 se esito < 400 |
| `vin` | VIN distinti cercati | n. VIN | VIN trovati |
| — | nessuna | — | API non misurata (es. `GET /jobs/:id`, export, upload cross) |

- Oggi le applicability sono a VIN singolo: UdV massime = `ceil(parts.length/10)`, reali = stesse se il veicolo è trovato, 0 altrimenti. La formula per VIN distinto copre già un'eventuale API batch.
- Piano Prasco: `part-applicability` e `part-applicability/cross` (sync e async) con meter `udv`; datasets, export e job abilitati senza meter; **tutte le altre API disabilitate** perché il contratto non ne definisce l'unità.
- Flusso: **prenota il massimo** sul `quota_counter` del periodo (update atomico condizionato: `used + reserved + n ≤ tetto`), esegue, **conferma il reale** e libera la differenza; su errore libera tutto. Prenotazioni orfane scadono (TTL, come nel ramo licensing). Le API async prenotano alla creazione del job e confermano alla fine.
- Risposta: header con le unità consumate e residue (es. `X-Usage-Remaining`), 429 con `Retry-After` all'inizio del mese successivo quando il tetto è raggiunto.
- Seat `unlimited` (accessi Prasco filiali/QA): nessun tetto, ma `usage_event` registrato comunque.

### 8.6 Utenti, tenant, ruoli, API key: Better Auth

Il pannello admin a due livelli richiede utenti, sessioni, inviti, ruoli per tenant e API key gestite dal cliente. Scriverlo in casa è molto codice di sicurezza. **Better Auth** (`better-auth@1.7.21`, MIT, libreria, tabelle nello stesso DB) lo copre con plugin:

- `organization`: tenant, membri, inviti, ruoli e permessi, anche ruoli creati a runtime (dynamic access control), team;
- `admin`: admin piattaforma, ban, impersonificazione;
- `@better-auth/api-key`: key intestate all'organizzazione (`references: "organization"`), salvate come hash, con `metadata` e `permissions` per API, scadenza.

Verificato qui (Bun 1.4.4, `bun:sqlite`): migrazione delle tabelle, utente, organizzazione, key dell'organizzazione con permesso `part-applicability` e metadata; `verifyApiKey` accetta la key per l'API permessa e la rifiuta per un'altra.

Attenzioni emerse:
- i `permissions` di una key si impostano solo lato server (`SERVER_ONLY_PROPERTY` se arrivano da una richiesta utente): l'API admin tenant li deve validare contro il piano e poi creare la key lato server, che è comunque il comportamento voluto;
- il **rate limit di default delle key è 10 richieste al giorno**: va disattivato e sostituito dal nostro;
- `remaining`/`refill` non sono mesi solari né UdV: **non** usarli per le quote contrattuali;
- con permesso mancante `verifyApiKey` risponde `KEY_NOT_FOUND`: per distinguere 401 da 403 conviene verificare la key senza permessi e controllare l'abilitazione nella nostra guardia;
- una verifica per richiesta legge il DB: con cache breve in memoria.

Sostituisce: auth custom con JWT (`server/lib/auth.ts`), utenti e key da env (`AUTH_USERS`, `AUTH_API_KEYS`), dipendenze Clerk inutilizzate.

Alternativa più minimale: tabella `api_key` nostra (hash SHA-256, prefisso) e auth attuale. Regge per le key, non per inviti e ruoli del pannello. Esclusi: Unkey (servizio esterno o self-host pesante), Clerk (servizio esterno, Organizations a pagamento).

### 8.7 Gateway: pochi middleware Hono, non un modulo a parte

Rivisto il 2026-11-12. `server/gateway/` (circa 1700 righe senza test, montaggio commentato) e `server/licensing/` (circa 1870, solo su `feat/dev/licensing`) sono già in-process, ma nati come "gateway" separato dall'app: per questo duplicano cose che l'app ha già o che la nuova struttura rende superflue.

| Pezzo del gateway/licensing | Nella nuova struttura |
|---|---|
| `request-context` (request id, start, IP) | già fatto da `apiLogger` di `@ai-vin/logging` |
| `body-limit` | `bodyLimit` di Hono (`hono/body-limit`) |
| `auth` (API key da YAML/env) | Better Auth API key (8.6) |
| `routing/canonical` + `matcher` + `route-resolve` (tabella `METHOD /path`) | **superflui**: la rotta la risolve Hono; ogni rotta dichiara il suo id API |
| `allow-list` per client | piano ∩ permessi della key |
| `rate-limit` + store in memoria | **da tenere** (logica finestre), con politiche da DB |
| `ban-engine` (ban automatici per IP/client) | sostituito da sospensione di key/tenant da admin; ban automatici solo se ci saranno endpoint pubblici |
| `finalize` (riga JSON + usage) | log già da `apiLogger`; l'uso diventa `usage_event` (solo API misurate) |
| licensing: plugin, finestre di calendario, reserve/commit, errori Problem Details | **da tenere** come logica, con config e contatori su DB |
| licensing: config YAML, validazione incrociata con la tabella rotte del gateway | superflua |

Proposta: **un middleware globale e uno per rotta**, con la descrizione dell'API attaccata alla rotta stessa.

```ts
// globale su /api/v1/*: apiLogger (già c'è) → bodyLimit → authenticate (key → tenant, key)
app.use('/api/v1/*', authenticate())

// per rotta: l'id API è lo stesso del log (apiName), del piano e dei permessi della key
app.post('/part-applicability', api({ id: 'part-applicability', meter: udv }), handler)
app.post('/async/part-applicability', api({ id: 'part-applicability', meter: udv, async: true }), handler)
app.get('/exports/:id/download', api({ id: 'exports' }), handler)
```

`api()` fa, in ordine: abilitazione (piano ∩ key) → rate limit → risoluzione seat (solo se c'è un meter) → prenotazione quota → `await next()` → conferma unità reali o rilascio. Il "dopo" sta nello stesso middleware, perché Hono permette codice dopo `next()`. Per le API async la prenotazione passa al job, che conferma alla fine.

Vantaggi:
- un posto solo dove si legge cosa fa un'API (id, meter, async), accanto all'handler: niente tabella rotte da tenere allineata;
- una rotta senza `api()` è un errore visibile in review (si può anche far fallire l'avvio: ogni rotta sotto `/api/v1` deve avere un descrittore);
- stima: 400–600 righe al posto di circa 3600, riusando i test di finestre, limiti e reserve/commit del ramo licensing.

Multi-istanza:
- **rate limit**: contatori in memoria per istanza, politiche da DB con cache versionata. Protegge il servizio e non è contrattuale: con N istanze si accetta l'approssimazione (o limite/N);
- **quote**: sempre su Postgres, update atomico condizionato: esatte anche con N istanze.

Scartati: gateway esterni (Kong, Envoy, AWS API Gateway con usage plan). Aggiungono un servizio, contano richieste e non UdV, e non sanno leggere il `cliente_id` dai metadata del body.

### 8.8 Storage: Postgres

Con multi-tenant e più istanze come obiettivo, servono stato condiviso e operazioni atomiche: prenotazione quote, claim delle schedulazioni, job. **Un Postgres gestito** copre tutto e rende inutile Redis anche in futuro. È una parte mobile in più rispetto al file SQLite, ma l'unica.

- `Bun.SQL` lo supporta nativamente (già usato con SQLite); Better Auth supporta Postgres.
- Schedulazioni senza leader: un tick al minuto per istanza fa `UPDATE schedule SET next_run_at = … WHERE next_run_at <= now() … RETURNING`: una sola istanza vince ogni occorrenza; `croner` calcola il prossimo `next_run_at` dall'espressione cron salvata dall'admin. Le occorrenze saltate (deploy, fermo) si recuperano al primo tick.
- Le snapshot sqlite locali dei dataset (cross per tenant, assembly groups) restano: sono dati di riferimento in sola lettura. La versione attiva la dice il DB (`dataset.active_version_id`), non l'ETag S3 (8.18).
- Se si vuole rinviare Postgres finché si resta a un'istanza per cliente: SQLite funziona, purché `tenant_id` sia ovunque da subito e l'SQL resti portabile. Lo sconsiglio: si testerebbero due dialetti.

### 8.9 Export e import via API

- Tipi in codice: `search-log` (Offerta art. 1.c), `usage-monthly` (report UdV per seat, base della fattura). L'import del tracciato cross non è più un export/import a sé: è il caricamento di una nuova versione del dataset `cross` (8.18).
- Programmazione per tenant in `schedule` (cron + timezone + parametri), modificabile dall'admin tenant entro i tipi del piano.
- API (tenant dalla key, abilitate senza meter):
  - `GET /v1/exports?type=&from=&to=` elenco;
  - `GET /v1/exports/:id` stato e metadati;
  - `GET /v1/exports/:id/download` → redirect a URL S3 presigned di breve durata (o stream);
  - `POST /v1/exports` export on demand (job async);
  - l'upload cross passa sotto `/v1/datasets` (8.18).
- Retention: job giornaliero che cancella `search_log` oltre 6 mesi e gli export scaduti.

### 8.10 Fatturazione: oltre alle UdV

Il report mensile deve contenere anche i **seat**: canone dal go-live del singolo seat (art. 2, 4), attivazioni del mese (fee una tantum), UdV incluse ed eccedenti, chiamate rifiutate per tetto. Quindi `seat` tiene `go_live` e `revoked_at`, e ogni cambio di stato è registrato.

### 8.11 Piano a fasi aggiornato

| Fase | Contenuto |
|---|---|
| 0 | Postgres + migrazioni; `tenant_id` ovunque; tabella `job` al posto dell'LRU; tick schedulazioni |
| 1 | Better Auth (utenti, organizzazioni, admin, API key) al posto di JWT/env/Clerk; `audit_log` (8.17) |
| 2 | piano per tenant, guardia API abilitate, rate limit da DB (gateway rimontato con provider DB) |
| 3 | seat e resolver configurabili, catalogo meter, quote con reserve/commit, `usage_event`, `search_log`, retention |
| 4 | export e import via API, schedulazioni per tenant, report mensile |
| 5 | pannello admin piattaforma e tenant |
| 6 | chat: AI SDK 5→7, tool a generatore, persistenza (con `tenant_id`) |
| 7 | skill e `query_dataset` |

### 8.12 Decisioni del 2026-11-12 (seconda tornata)

| # | Domanda | Decisione |
|---|---|---|
| 1 | cambiare il `cliente_id` di un seat | equivale a disattivazione + nuova attivazione (con fee); lo storico resta |
| 2 | attivazione | **AIVIN accende il seat** e da lì parte il canone; il seat **non si sospende** se non è associato; **l'associazione la fa il cliente** in autonomia |
| 3 | `/part-applicability/cross` | conta UdV come l'applicability |
| 4 | targa | la conversione targa → VIN è inclusa nella UdV, ma va **tracciata** a parte (8.14) |
| 5 | plugin di risoluzione licenza | lista ordinata per tenant, con fallback |

### 8.13 Ciclo di vita del seat

```
AIVIN accende            cliente associa                AIVIN disattiva
     │                        │                               │
     ▼                        ▼                               ▼
 active, libero ──────► active, associato ─────────────► deactivated
 (si paga dal go_live)  (external_id fisso per sempre)   (si paga fino a deactivated_at)
```

- **Accensione** (admin piattaforma): crea il seat con `go_live`; da quel giorno entra nel report di fatturazione, associato o no.
- **Associazione** (admin tenant, self-service): lega un seat attivo e libero a un identificativo del plugin scelto: un `cliente_id` (plugin `metadata`/`header`) oppure una API key generata per il seat (plugin `api-key`). Vincolo unico `(tenant, plugin, external_id)`.
- **L'associazione non si cambia** (decisione 1). Per servire un altro Cliente Ricambista serve un nuovo seat. Unica eccezione proposta: correggere un errore di battitura finché il seat non ha nessun `usage_event` (associazione mai usata).
- **Chiamata con identificativo non associato**: 403 `seat_not_assigned`, con l'identificativo nel messaggio e nel log. Opzione del tenant, spenta di default: **associazione automatica** del nuovo identificativo al primo seat libero (comoda per Prasco, che così non deve passare dal pannello per ogni nuovo cliente).
- **Seat esauriti** (nessun seat libero): stesso 403, con codice `no_free_seat`; l'admin tenant vede nel pannello quanti seat sono liberi e chiede ad AIVIN di accenderne altri.
- **Disattivazione** (admin piattaforma, su richiesta): il seat smette di risolvere chiamate; resta nello storico e nei report del mese.

### 8.14 Tracciamento della conversione targa

Oggi la risoluzione del veicolo (`server/routes/v1-api.ts`, ~righe 130–150; tool `FindVehicleTool` in chat) prova prima `vehicle_id` come VIN e, se non trovato e se `AIVIN_USE_PLATE` è attivo, chiama `plate-to-vin` su ai-vin-service. La UdV non cambia (decisione 4), ma la conversione ha un costo e va contata.

Proposta: **le unità di una richiesta diventano un elenco**, non un numero solo.

1. **Registro d'uso per richiesta.** Il middleware `api()` (e la route della chat) apre un registro legato alla richiesta, raggiungibile da qualunque funzione con `AsyncLocalStorage`, come già fa il request id dei log. Le funzioni profonde registrano senza cambiare firma:
   ```ts
   usage.record('plate-lookup', 1, { found: !!optVin?.vin, cache: 'miss' })
   ```
2. **Meter secondari.** Oltre al meter principale dell'API (`udv`), il catalogo ha meter di componente come `plate-lookup`. Nel piano ogni meter ha un ruolo:
   - `billable`: entra in fattura e ha un tetto (oggi solo `udv`);
   - `tracked`: solo registrato, eventualmente con un tetto di protezione (es. N conversioni al mese per seat, per limitare il costo del provider).
3. **`usage_event` per (richiesta, meter)**: una richiesta con targa produce due righe, `udv = 1` e `plate-lookup = 1`. Report e dashboard le aggregano separatamente.
4. **`search_log`**: salva `vehicle_id` com'è arrivato, il VIN risolto e `vehicle_id_kind` (`vin` | `plate`), così l'export per Prasco mostra quando è stata usata la targa.
5. **Costo reale.** La chiamata al provider avviene solo se ai-vin-service non ha la targa in cache. Proposta: ai-vin-service restituisce l'esito della cache (header, es. `X-Aivin-Cache: hit|miss`), registrato come attributo `cache`; i report distinguono conversioni servite dalla cache e chiamate al provider.
6. **Meno conversioni inutili.** Oggi un VIN valido ma non in catalogo scatena comunque `plate-to-vin`. Controllo di formato prima del fallback: se `vehicle_id` ha la forma di un VIN (17 caratteri, alfabeto senza I/O/Q) non si prova la targa. In alternativa, campo opzionale `vehicle_id_type` nella richiesta.
7. **Tetto sulla conversione** (se configurato): si prenota 1 `plate-lookup` solo quando `vehicle_id` non ha forma di VIN, e si conferma 0 se la conversione non è servita.

La stessa infrastruttura serve per qualunque costo interno futuro (chiamate LLM, provider di catalogo a consumo), senza toccare il contratto con il cliente.

### 8.15 Domande aperte

1. **Associazione automatica** al primo seat libero (8.13): la vuoi come opzione del tenant?
2. **Correzione di un'associazione mai usata** (8.13): ammessa?
3. **Tetto di protezione sulle conversioni targa** (8.14): serve, e su che base (per seat, per tenant)?
4. **Cache della targa in ai-vin-service**: va bene esporre l'esito cache verso ai-vin-app (modifica anche su ai-vin-service)?

### 8.16 Decisioni del 2026-11-12 (terza tornata)

| # | Tema | Decisione |
|---|---|---|
| 1 | associazione automatica al primo seat libero | **no**: impedirebbe al cliente di sospendere una licenza (le chiamate continuerebbero a occupare seat). Al suo posto: **import delle associazioni da un elenco**, eventualmente con l'AI per riconoscere le colonne |
| 2 | riassegnazione | **il cliente può riassegnare** un seat. Supera la decisione 1 della sezione 8.12 (riassegnazione = nuova attivazione) |
| 3 | tetto sulle conversioni targa | sì, **per seat**, semplice |
| 4 | esito cache della targa | non serve ora (vedi sotto) |

**Seat e associazione, rivisti** (sostituisce in parte 8.13):

| Livello | Chi | Stati | Effetto sulle chiamate | Effetto sul canone |
|---|---|---|---|---|
| seat | AIVIN | `active` → `deactivated` | solo un seat attivo risolve | si paga da `go_live` a `deactivated_at`, associato o no |
| associazione | cliente | `assigned` ⇄ `suspended`, `closed` (riassegnazione) | `suspended` → 403 `seat_suspended`; identificativo senza associazione → 403 `seat_not_assigned` | nessuno |

- Ogni associazione ha un intervallo (`from`, `to`): riassegnare chiude quella corrente e ne apre una nuova sullo stesso seat. Lo storico dice sempre quale `cliente_id` usava quale seat in ogni momento: serve per la riconciliazione dell'art. 3.
- Attenzione contrattuale: l'art. 2 vieta di usare un Attributo API per più Clienti Ricambisti e chiede una licenza per ogni Cliente in più. Riassegnare un seat da A (che esce) a B è una sostituzione; ruotarlo spesso tra clienti attivi aggirerebbe il contratto. Per ora nessun vincolo rigido: il report mensile **evidenzia i seat che hanno servito più di un `cliente_id` nel mese**, e AIVIN decide.

**Import delle associazioni da elenco**
- Upload CSV/XLSX dal pannello tenant, oppure via API.
- Riconoscimento delle colonne (`cliente_id`, etichetta/ragione sociale, eventuale stato) con l'analisi colonne già presente in `server/lib/datasets/analyze.ts` (LLM `generateObject`), con conferma dell'utente.
- **Anteprima prima di applicare**: nuove associazioni, già associati, da sospendere/riattivare, righe non valide, seat liberi insufficienti. Applicazione tutta o niente.

**Viste e report del tenant**
Serve un registro di **tutte** le chiamate, non solo di quelle misurate: `request_log`, una riga per chiamata API.

| Campo | Note |
|---|---|
| ts, request_id, api, key | — |
| identificativo grezzo | il `cliente_id` letto dal plugin, **anche se non risolve** |
| seat | se risolto |
| esito | `ok`, `failed` (errore nostro o del provider), `invalid` (400), `rejected:*` |
| motivo del rifiuto | `api_disabled`, `rate_limited`, `seat_not_assigned`, `seat_suspended`, `quota_exceeded`, `plate_limit` |
| unità | UdV e conversioni targa consumate (dalle righe di uso) |

Nella dashboard del tenant: chiamate entrate, riuscite, fallite e rifiutate per giorno e per cliente. **Warning visivo** quando ci sono rifiuti per `seat_not_assigned` nel periodo, con l'elenco degli identificativi sconosciuti e il numero di chiamate di ciascuno, e un'azione "associa a un seat libero" (o "importa elenco"). Così il caso che l'associazione automatica voleva coprire si risolve con un clic, ma sotto il controllo del cliente.

Il `request_log` contiene `cliente_id` e conteggi (consentito dall'art. 10 del Contratto); VIN e codici restano solo nel `search_log` dell'Offerta, con la sua retention a 6 mesi.

**Tetto conversioni targa per seat**
- Nel piano: `plate-lookup` con tetto mensile per seat.
- Al tetto la richiesta con targa riceve 429 `plate_limit` (le richieste con VIN continuano). Si prenota 1 solo quando `vehicle_id` non ha la forma di un VIN.

**Cache della targa (punto 4)**
ai-vin-service tiene in cache le conversioni targa → VIN (`src/functions/plate-to-vin.ts`, `store.cached` attorno alla chiamata RapidAPI/VRM): la stessa targa chiesta una seconda volta non costa nulla. La proposta era far sapere ad ai-vin-app se la conversione è venuta dalla cache o dal provider, per misurare il **costo reale** di AIVIN. Il tetto per seat invece conta ogni conversione chiesta dal cliente, cache o no: è più semplice e prevedibile per lui. Quindi oggi non serve: si potrà aggiungere quando servirà un'analisi dei costi dei provider.

### 8.17 Audit log delle operazioni utente

Deciso il 2026-11-12: nessun vincolo sulla riassegnazione dei seat, ma ogni operazione è verificabile a posteriori. Non ne avevamo ancora parlato: finora c'erano solo i log applicativi (anche delle login, TODO "Log delle login") e i registri delle chiamate.

Tre registri diversi, per tre domande diverse:

| Registro | Risponde a | Scritto da |
|---|---|---|
| log applicativi (`@ai-vin/logging`) | cosa è successo dentro una richiesta (diagnostica) | codice, a ogni livello |
| `request_log` / `usage_event` / `search_log` | quali chiamate API, con che esito e quante unità | middleware `api()` |
| **`audit_log`** | **chi ha cambiato cosa**, quando, da cosa a cosa | ogni operazione che modifica configurazione o stato |

**Cosa si registra**

| Area | Azioni |
|---|---|
| seat (AIVIN) | accensione, disattivazione, cambio tipo (`metered`/`unlimited`) |
| associazioni (cliente) | assegnazione, sospensione, riattivazione, riassegnazione, chiusura; import da elenco (file, anteprima, righe applicate) |
| API key | creazione, revoca, cambio permessi, rate limit, scadenza |
| licensing | modifica dei plugin di risoluzione e del loro ordine |
| piano (AIVIN) | API abilitate, meter, tetti, seat acquistati, rate limit massimi |
| schedulazioni ed export | creazione, modifica, cancellazione; export on demand; **download** di export (contengono dati delle ricerche) |
| dati | dataset: creazione, nuova versione, attivazione, rollback, cancellazione, download |
| utenti e accesso | login riuscite e fallite, logout, inviti, cambio ruolo, rimozione membro, impersonificazione (inizio e fine, con l'admin che la fa) |

**Forma di una riga**
- `ts`, `tenant_id`, `request_id` (per ritrovare i log applicativi della stessa operazione);
- attore: utente e ruolo, oppure API key, oppure `system` (job schedulato, import automatico); se in impersonificazione, anche l'admin reale;
- azione (es. `seat_binding.reassign`), oggetto (tipo e id), **prima/dopo** in JSON (solo i campi cambiati, segreti esclusi: delle key solo prefisso e id);
- esito (riuscita o rifiutata, col motivo: un tentativo negato è informazione utile);
- IP e user agent.

**Regole**
- **Stessa transazione della modifica**: niente modifica senza riga di audit, niente riga di audit per una modifica annullata. In pratica un helper `audited(tx, action, target, before, after)` usato dal livello di servizio, non dalle route.
- Eventi di autenticazione (login, inviti, ruoli, impersonificazione) dagli hook di Better Auth.
- **Solo append**: nessuna API di modifica o cancellazione; su Postgres si può rinforzare togliendo `UPDATE`/`DELETE` all'utente applicativo su quella tabella.
- Visibilità: l'admin tenant vede l'audit del proprio tenant; l'admin piattaforma vede tutto. Esportabile come gli altri report (stesso modulo export).
- Retention: più lunga del `search_log`, almeno la durata del contratto più il periodo delle verifiche; durata esatta da fissare (anche ai fini GDPR, perché contiene IP ed email degli utenti).

**Uso per la verifica delle licenze**
Incrociando `audit_log` (riassegnazioni) e `request_log` (chiamate per seat e `cliente_id`) il report mensile mostra, per ogni seat, la sequenza dei `cliente_id` serviti e chi ha fatto ogni riassegnazione: è la base per la riconciliazione dell'art. 3 senza vincoli preventivi.

Nel piano a fasi (8.11) l'audit entra nella fase 1 insieme a Better Auth: tutte le fasi successive che introducono operazioni lo usano da subito.

### 8.18 Datasets: le cross come tipo vincolato

Deciso il 2026-11-12: generalizzare. Il cliente carica dati (fogli di calcolo, CSV) come **dataset**; le cross sono un dataset di **tipo vincolato**. Gli usi futuri dei dataset generici non si approfondiscono ora, ma gestione via API e sezione "Datasets" nell'app ci sono da subito.

Base esistente da riprendere (route oggi commentate in `server/index.ts`): `server/lib/datasets/` e `client/src/pages/Datasets*.tsx`, con upload wizard, analisi strutturale dei fogli, analisi colonne con LLM (`analyze.ts`), un sqlite per "schema", anteprima tabellare, query `SELECT`. Oggi è per utente (`userId`) e a cartelle ("schema"): diventa per tenant e a dataset versionati.

**Modello**

| Concetto | Contenuto |
|---|---|
| `dataset` | tenant, nome, descrizione, **tipo**, versione attiva |
| `dataset_version` | file originale (S3), snapshot normalizzata (sqlite su S3), mappatura colonne, righe, statistiche, report di validazione, stato: `uploaded` → `validating` → `valid` / `invalid` → `active` / `archived` |
| tipo | definito **in codice**: colonne richieste ("ruoli"), alias degli header, normalizzazione, regole di validazione, se è **singleton** (una sola versione attiva per tenant, consumata da una funzione) |

Tipi iniziali:

| Tipo | Ruoli colonna | Singleton | Consumato da |
|---|---|---|---|
| `generic` | nessuno: colonne dedotte (analisi strutturale + LLM) | no | per ora solo vista e anteprima |
| `cross` | `sku`, `oe` obbligatori; `description` opzionale | sì | `/part-applicability/cross` e tool chat |
| `assembly-groups` | come oggi | sì, a livello **piattaforma** (gestito da AIVIN, condiviso) | part-list, chat |

Lo stesso meccanismo di tipo + ruoli + anteprima serve anche all'**import delle associazioni seat** (8.16): elenco caricato, colonne riconosciute, anteprima, applicazione. Non è un dataset da conservare, ma riusa parsing, mappatura e report.

**Versioni e attivazione**
- Ogni upload crea una **nuova versione**; la versione attiva cambia solo con un'attivazione (manuale o automatica se la validazione passa). **Rollback** = riattivare una versione precedente.
- Per i tipi vincolati la validazione include le regole già elencate nel TODO "Cross: validazione e limiti dell'upload": righe scartate oltre soglia, calo rispetto alla versione attiva, formato dei codici, OE duplicati dopo normalizzazione. Con `dry_run` si ottiene solo il report.
- Ingestione grande = job async (tabella `job`), con avanzamento visibile.
- **Multi-istanza**: la verità è `dataset.active_version_id` nel DB; ogni istanza, quando cambia, scarica la snapshot sqlite della versione da S3 e la sostituisce a caldo. Chiude il TODO "Cross: sincronizzazione tra istanze" senza ETag né notifiche.

**API** (stesse per SPA con sessione e per integrazioni con API key; id API `datasets`, senza meter)

| Metodo e path | Uso |
|---|---|
| `GET /v1/datasets?type=` | elenco |
| `POST /v1/datasets` | crea (`name`, `type`) |
| `GET` / `PATCH` / `DELETE /v1/datasets/:id` | dettaglio, rinomina, cancellazione (409 se è il singleton attivo usato da una funzione) |
| `POST /v1/datasets/:id/versions` | upload multipart, opzioni `mapping`, `activate: auto \| manual`, `dry_run` → 202 con job |
| `GET /v1/datasets/:id/versions[/:v]` | storico, stato, statistiche, report di validazione |
| `POST /v1/datasets/:id/versions/:v/activate` | attivazione o rollback |
| `GET /v1/datasets/:id/versions/:v/download?form=original\|normalized` | URL presigned |
| `GET /v1/datasets/:id/versions/:v/preview` | prime righe (anteprima nell'app) |

- Le route interne `/api/datasets/*` di oggi spariscono: la SPA usa le stesse `/api/v1` (`requireApiKeyOrAuth` lo permette già). Meno endpoint da mantenere.
- **Compatibilità**: `POST /v1/cross/upload` resta come alias deprecato (nuova versione del dataset `cross` del tenant, attivazione automatica) per almeno una release. Il contratto (art. 6) chiede **30 giorni di preavviso** per modifiche alle API che richiedono adattamenti a Prasco.

**Vista "Datasets" nell'app**
- Elenco: nome, tipo (badge), versione attiva, righe, ultimo aggiornamento, stato dell'ultima versione (warning se `invalid`).
- Dettaglio: storico versioni con stato e report di validazione, attiva/rollback, download, anteprima tabellare (`table-preview.tsx` esiste).
- Upload: il wizard esistente (`upload-wizard.tsx`) con scelta del tipo e, per i tipi vincolati, mappatura colonne → ruoli (suggerita da alias e LLM, confermata dall'utente).

### 8.19 Export nel prodotto

Gli export periodici li avevamo previsti (8.9: tipi, schedulazioni per tenant, API di elenco/download, retention), ma solo come API e "pagina nel pannello". Li rendo una sezione del prodotto.

**Vista "Export"**
- **Elenco**: tipo, periodo, stato, righe, dimensione, data; filtri per tipo e periodo; **download** (URL presigned, registrato nell'audit).
- **Programmazioni** (admin tenant): tipo, frequenza (cron + timezone, con forma guidata: giornaliera, settimanale, mensile), prossima esecuzione, esito dell'ultima, attiva/disattiva, "esegui ora".
- **Export su richiesta**: tipo + periodo → job async, compare nell'elenco quando pronto.
- Warning se l'ultima esecuzione programmata è fallita.

**Navigazione proposta**

| Sezione | Contenuto | Ruoli |
|---|---|---|
| Ricerca | chat e ricerca VIN attuali | tutti |
| Dashboard | chiamate entrate/riuscite/fallite/rifiutate, UdV per seat e cliente, warning (seat non associati, tetti vicini) | tenant |
| Datasets | 8.18 | tenant |
| Export | 8.19 | tenant |
| Licenze | seat, associazioni, import elenco, plugin di risoluzione, API key | admin tenant |
| Amministrazione | membri e ruoli, audit log | admin tenant |
| Piattaforma | tenant, piani, accensione seat, rate limit, audit globale | admin AIVIN |

Nel piano a fasi: i datasets entrano nella **fase 4** con export e import (base comune: upload, job, S3, presigned); la vista "Datasets" e la vista "Export" nella **fase 5** con il pannello.
