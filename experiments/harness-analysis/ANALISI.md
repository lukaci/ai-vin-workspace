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

## 7. Decisioni aperte

1. **Istanze**: ai-vin-app gira su una o più istanze, e dove? Decide SQLite su volume (con backup su S3 fatto dallo scheduler) contro Postgres gestito.
2. **Tetto UdV**: oltre le UdV extra massime per licenza/mese, l'API **rifiuta** (429) o continua senza fatturare? Cambia la guardia.
3. **Attributo API**: in quale campo arriva il `cliente_id`? (`metadata` della richiesta, header, API key per licenza?) Il TODO "Licenze" dice "API key e metadati, oggetto composto": va fissato in specifica.
4. **API batch**: per il contratto è l'`/async/part-applicability` o un'API nuova?
5. **SFTP**: obbligatorio o basta l'API?
6. **Retention del ledger UdV**: i 6 mesi dell'Offerta valgono per il registro ricerche; il ledger di fatturazione va tenuto di più (verifiche fino a due volte l'anno).
7. **Clerk**: dipendenze presenti ma inutilizzate (auth custom). Da rimuovere o da adottare per il pannello admin.
