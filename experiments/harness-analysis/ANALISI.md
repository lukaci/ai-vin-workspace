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

<!-- sezioni 3+ completate dopo la ricerca online -->
