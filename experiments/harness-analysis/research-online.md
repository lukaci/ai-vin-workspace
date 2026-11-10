# Ricerca online: harness agentico, job durevoli, skill, dataset e metering per ai-vin-app

Data della ricerca: **2026-11-10**. Solo fonti primarie: sorgenti della documentazione ufficiale su GitHub, README dei repository, registry npm (`registry.npmjs.org`, per versioni e date), pagine ufficiali.

**Nota sul metodo.** Da questa sessione erano raggiungibili solo GitHub, npm e `code.claude.com`/`platform.claude.com`. I siti di documentazione (ai-sdk.dev, vercel.com, mastra.ai, docs.langchain.com, inngest.com, trigger.dev, duckdb.org, bun.com, stripe.com, useautumn.com, polar.sh, openmeter.io ecc.) non lo erano. Per questo cito il **sorgente della documentazione nel repository ufficiale**, cioè lo stesso contenuto pubblicato sul sito. Versioni e date vengono dal registry npm, interrogato il 2026-11-10.

---

## 1. Sintesi

1. **Vercel AI SDK è alla v7** (`ai@7.0.168`; 7.0.0 uscita il 2026-06-25). La v6 (2025-12-22) ha introdotto `ToolLoopAgent` e le approvazioni dei tool. La v7 aggiunge `WorkflowAgent` (durevole), "harness" sperimentali, `toolApproval`, code mode e skill upload. Richiede Node 22+ ed è solo ESM. Da v5 servono **due migrazioni** (5→6→7), con codemod disponibili.
2. Per ai-vin-app (Bun, Hono, AI SDK UI, self-host) la strada con **meno parti mobili** è aggiornare ad AI SDK v7 e costruire in casa le parti trasversali, su SQLite/S3 già in uso: thread, ledger dei crediti, export. In più `Bun.cron` (nativo da Bun 1.3.11), DuckDB per i dataset e `just-bash`/`bash-tool` per skill e sandbox leggera.
3. **I resumable stream "standard" dell'AI SDK richiedono Redis** (`resumable-stream`). Le alternative senza Redis sono due: Workflow DevKit (stream durevoli nel "World") oppure un replay su SQLite fatto in casa.
4. **Workflow DevKit** (`workflow@5.4.0`, Apache-2.0) gira fuori da Vercel, ma con limiti:
   - il Local World è dichiarato "solo sviluppo";
   - il Postgres World è una "reference implementation" senza autenticazione;
   - Hono richiede Nitro come build;
   - non c'è cron nativo.
5. **Mastra** (`@mastra/core@1.82.0`, Apache-2.0 tranne `ee/`) è il framework più completo per questo caso: server Hono, adapter `@mastra/hono`, storage LibSQL/SQLite, workflow schedulati con cron, skill SKILL.md, workspace con `S3Filesystem`, stream convertibili in AI SDK v7. Ha resumable stream in un singolo processo **senza Redis** (`CachingPubSub`). Durable agent ancora in **beta**.
6. **eve** (Vercel, `eve@1.0.0-rc.9`, Apache-2.0) ha skill, schedule cron, run durevoli e self-host Node. È però in **release candidate** da fine ottobre 2026 e impone una propria struttura di progetto.
7. **LangChain Deep Agents / LangGraph JS** (MIT) offrono un harness ricco: todo, filesystem virtuale, subagent, skill. Ma la UI `useStream` presuppone il protocollo dell'Agent Server, e l'Agent Server self-host richiede Postgres, Redis e una licenza (Enterprise). Si perderebbe lo stack AI SDK UI.
8. **Claude Agent SDK** non è adatto come runtime principale: legato ai modelli Claude e al binario Claude Code, sotto Commercial Terms.
9. **Metering/crediti**: per contratti B2B prepagati con fattura offline, un **ledger interno su SQLite** è il più adatto. Lago (AGPL) e OpenMeter (Apache) sono self-hostabili ma pesanti (Postgres+Redis, oppure Kafka+ClickHouse+…). Polar è merchant of record per pagamenti con carta. Autumn e Stripe dipendono da Stripe.
10. **Classifica per questo caso**:
    1. AI SDK v7 + componenti in casa;
    2. Mastra (se si vuole un framework "batteries included");
    3. Workflow DevKit/WorkflowAgent (solo quando serve vera durabilità e si accetta Postgres);
    4. eve (da rivalutare dopo la 1.0);
    5. LangChain Deep Agents;
    6. gli altri.

---

## 2. Candidati

### A. Vercel AI SDK (v5 → v6 → v7) e AI Elements

**Versioni e stato**
- `ai` latest **7.0.168** (2026-11-10). Linee mantenute su npm: `ai-v5` = 5.0.288 e `ai-v6` = 6.0.328. `@ai-sdk/react` latest 4.0.172 (la v2 corrisponde ad AI SDK 5). Licenza Apache-2.0. [npm ai](https://www.npmjs.com/package/ai), [npm @ai-sdk/react](https://www.npmjs.com/package/@ai-sdk/react)
- Date delle major (dal registry npm): 5.0.0 il 2025-07-31, 6.0.0 il 2025-12-22, 7.0.0 il 2026-06-25. [npm ai (versions)](https://www.npmjs.com/package/ai?activeTab=versions)
- Il changelog Vercel annuncia AI SDK 7 come disponibile (GA), con codemod `npx @ai-sdk/codemod v7`. Lo vedo solo come snippet di ricerca: la pagina non era raggiungibile. [vercel.com/changelog/ai-sdk-7](https://vercel.com/changelog/ai-sdk-7)

**Migrazione da v5**
- Il percorso è 5→6 e poi 6→7. La guida 6.0 copre:
  - `Experimental_Agent` diventa `ToolLoopAgent`;
  - `convertToModelMessages` diventa async;
  - deprecazione di `generateObject`/`streamObject`;
  - nuovi stati di approvazione nelle tool UI part;
  - rinomina degli helper `isToolUIPart`/`getToolName`.
  
  [migration-guide-6-0](https://github.com/vercel/ai/blob/main/content/docs/08-migration-guides/24-migration-guide-6-0.mdx)
- La guida 7.0 è lunga (circa 1900 righe). Punti principali:
  - **Node.js 22+** (testato su 22/24/26) e **solo ESM**;
  - `system` diventa `instructions`, `onFinish` diventa `onEnd`, `fullStream` diventa `stream`, `stepCountIs` diventa `isStepCount`;
  - OpenTelemetry spostato in `@ai-sdk/otel`, `experimental_telemetry` diventa `telemetry`;
  - `experimental_context` diventa `context`/`runtimeContext`;
  - `needsApproval` è deprecato a favore di `toolApproval`;
  - `usage` e i risultati ora includono tutti gli step (`finalStep` per l'ultimo).
  
  C'è una skill di migrazione (`npx skills add vercel/ai --skill migrate-ai-sdk-v6-to-v7`). [migration-guide-7-0](https://github.com/vercel/ai/blob/main/content/docs/08-migration-guides/23-migration-guide-7-0.mdx)
- Bun non è citato tra i runtime testati: la guida parla solo di versioni Node. La compatibilità con Bun va verificata empiricamente (vedi Domande aperte).

**Agent e human in the loop**
- `ToolLoopAgent` (nel pacchetto `ai`) gira in memoria. `WorkflowAgent` (`@ai-sdk/workflow`, richiede `workflow@5`) esegue ogni tool come step durevole, con retry, approvazioni che sopravvivono alla sospensione e uno stream scritto su `getWritable()`. Il `DurableAgent` di `@workflow/ai` è deprecato e funziona solo con AI SDK 6. [07-workflow-agent.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-agents/07-workflow-agent.mdx), [durable-agent.mdx (Workflow)](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/api-reference/workflow-ai/durable-agent.mdx)
- `toolApproval` su `ToolLoopAgent` e `streamText` restituisce gli stati `not-applicable`, `approved`, `user-approval` ecc. Nella UI le tool part hanno `approval-requested`/`approval-responded`. Le approvazioni non valgono per i tool eseguiti lato provider. [06-tool-approvals.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-agents/06-tool-approvals.mdx), [03-chatbot-tool-usage.mdx](https://github.com/vercel/ai/blob/main/content/docs/04-ai-sdk-ui/03-chatbot-tool-usage.mdx)

**Persistenza delle UIMessage**
- Il pattern ufficiale funziona così:
  - si salva `UIMessage[]` nella callback `onEnd` di `toUIMessageStream`;
  - si validano con `validateUIMessages` (tool, metadata, data part);
  - gli ID si generano lato server con `createIdGenerator`;
  - si può inviare solo l'ultimo messaggio;
  - `consumeStream` serve a completare la generazione anche se il client si disconnette.
  
  È documentata anche la persistenza dell'input dei tool in streaming. Non c'è uno storage incluso: lo sceglie l'applicazione. [03-chatbot-message-persistence.mdx](https://github.com/vercel/ai/blob/main/content/docs/04-ai-sdk-ui/03-chatbot-message-persistence.mdx)
- Le memorie a lungo termine sono documentate come tool del provider (Anthropic memory tool), provider esterni (Letta, Mem0) o tool custom. [06-memory.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-agents/06-memory.mdx)

**Resumable stream**
- Richiedono il pacchetto `resumable-stream` e **un'istanza Redis**. Gli stream in Redis scadono. Lo stop dell'utente va gestito a parte dal resume, ed esiste una nota di troubleshooting "abort breaks resumable streams". [03-chatbot-resume-streams.mdx](https://github.com/vercel/ai/blob/main/content/docs/04-ai-sdk-ui/03-chatbot-resume-streams.mdx), [15-abort-breaks-resumable-streams.mdx](https://github.com/vercel/ai/blob/main/content/docs/09-troubleshooting/15-abort-breaks-resumable-streams.mdx)
- `resumable-stream` (v2.2.13, ISC) "relies on a pubsub mechanism and is designed to be used with Redis". [github.com/vercel/resumable-stream](https://github.com/vercel/resumable-stream)
- L'alternativa senza Redis è `WorkflowChatTransport` (ora in `@ai-sdk/workflow`), che riprende stream durevoli da una run del Workflow DevKit. [Workflow resumable-streams.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/ai/resumable-streams.mdx)

**Tool streaming, data part, generative UI**
- Gli stati delle tool part sono `input-streaming` → `input-available` → (`approval-requested`) → `output-available`, e permettono un rendering custom per ciascuno stato. [03-chatbot-tool-usage.mdx](https://github.com/vercel/ai/blob/main/content/docs/04-ai-sdk-ui/03-chatbot-tool-usage.mdx)
- Le data part tipizzate (`data-*`) si dividono in due:
  - persistenti, con riconciliazione per `id`;
  - transienti (`transient: true`), escluse dalla storia.
  
  [20-streaming-data.mdx](https://github.com/vercel/ai/blob/main/content/docs/04-ai-sdk-ui/20-streaming-data.mdx)

**MCP, code mode, skill, harness (v7)**
- Client MCP in `@ai-sdk/mcp` (2.0.95): trasporti HTTP, SSE e stdio, OAuth. [16-mcp-tools.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-core/16-mcp-tools.mdx)
- **Code mode** (`@ai-sdk/code-mode`, *sperimentale*): il modello scrive JS/TS che chiama i tool dentro una sandbox **QuickJS**. Utile per filtrare e aggregare risultati grandi. Richiede Node 22. [18-code-mode.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-core/18-code-mode.mdx)
- **Skill**: le skill native sono solo due varianti, nessuna delle due adatta a un `ToolLoopAgent` multi-provider:
  - `uploadSkill`, che carica uno SKILL.md *presso il provider* (Anthropic/OpenAI) per usarlo nel container di code execution del provider: lock-in sul provider;
  - `skills` su `HarnessAgent`.
  
  Per `ToolLoopAgent` le skill vanno realizzate con tool propri, per esempio `bash-tool`, vedi C. [41-skill-uploads.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-core/41-skill-uploads.mdx), [harness 04-skills.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-harnesses/04-skills.mdx)
- **Harness** (`HarnessAgent`, adapter per esempio `@ai-sdk/harness-claude-code`). Esplicitamente *"Harness packages are experimental"*. Servono a far girare runtime come Claude Code o Codex in una sandbox: non pertinenti per un agente di dominio. [03-ai-sdk-harnesses/01-overview.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-harnesses/01-overview.mdx)

**AI Elements**
- `ai-elements@1.9.1`: componenti shadcn/ui copiati nel progetto (Conversation, Message, Tool, Reasoning, PromptInput…). **Il README annuncia la deprecazione a fine novembre 2026, con migrazione in "AI Elements from shadcn/ui"**. Prerequisiti dichiarati: Next.js e Tailwind. Su Vite+React vanno verificati. [github.com/vercel/ai-elements](https://github.com/vercel/ai-elements)

**Valutazione rispetto alle feature**
1. Forte su UI e streaming, persistenza fatta in casa. Il resume richiede Redis o Workflow.
2. Nessuna schedulazione.
3. Nessuna skill per `ToolLoopAgent` multi-provider: va realizzata in proprio.
4. Code mode o tool SQL custom.
5. Nulla.

Lock-in basso: libreria Apache-2.0, provider astratti.

### B. Vercel Workflow DevKit (`workflow`, "use workflow"/"use step")

**Versioni**
- `workflow@5.4.0` (2026-11-04); la v5.0.0 è del 2026-09-30, la v4 resta disponibile (`4.8.16`). Apache-2.0. [npm workflow](https://www.npmjs.com/package/workflow), [whats-new.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/whats-new.mdx)
- La v5 è molto più veloce della v4. Gli stream sono scritti su WebSocket di default e i payload compressi e cifrati. [whats-new.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/whats-new.mdx)

**World (backend)**
- Ufficiali: Local, Postgres, Vercel. Di comunità: Turso/libSQL, MongoDB, Redis/BullMQ, MySQL, NATS, Cloudflare, Azure, Upstash, Platformatic, Eveland, Browser. [worlds-manifest.json](https://github.com/vercel/workflow/blob/main/worlds-manifest.json)
- **Local World**: file JSON in `.workflow-data/`, una sola istanza, autenticazione minima. *"designed for development, not production"*. [worlds/v5/local.mdx](https://github.com/vercel/workflow/blob/main/docs/content/worlds/v5/local.mdx)
- **Postgres World** (`@workflow/world-postgres@5.1.1`): PostgreSQL più graphile-worker. È una *"reference implementation… not optimized for scale, speed, or security… ships with **no authentication** on the workflow HTTP routes"*: si consiglia di clonarlo e adattarlo. [worlds/v5/postgres.mdx](https://github.com/vercel/workflow/blob/main/docs/content/worlds/v5/postgres.mdx)
- Il World Turso/libSQL di comunità (`@workflow-worlds/turso@0.2.2`) non è aggiornato dal 2026-02-09: dubbia la compatibilità con la v5. [npm @workflow-worlds/turso](https://www.npmjs.com/package/@workflow-worlds/turso)

**Bun e Hono**
- La guida Hono usa **Nitro** (`workflow/nitro`) come sistema di build. [getting-started/hono.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/getting-started/hono.mdx)
- Esiste una guida "Framework Integrations" con esempio **Bun** (`Bun.serve` più le route `/.well-known/workflow/v1/flow` e `/webhook`). È però rivolta agli autori di framework: integrazione da costruire a mano. [how-it-works/framework-integrations.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/how-it-works/framework-integrations.mdx)

**Scheduling e sleep**
- `sleep()` durevole e hook/webhook per l'human in the loop. **Nessun cron nativo**: la comparativa ufficiale dice *"Trigger from Vercel Cron or a system cron calling `start()`"*. [workflow-sdk-vs-inngest.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/comparisons/workflow-sdk-vs-inngest.mdx), [api-reference/workflow/sleep.mdx](https://github.com/vercel/workflow/blob/main/docs/content/docs/v5/api-reference/workflow/sleep.mdx)

**Integrazione con l'AI SDK**: `WorkflowAgent` più `WorkflowChatTransport` danno chat durevole e resumable senza Redis, se il World persiste gli stream. [07-workflow-agent.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-agents/07-workflow-agent.mdx)

**Valutazione**
- Ottimo per le feature 1 (resume) e 2 (job lunghi), ma cron esterno.
- Parti mobili:
  - in produzione Postgres (più il lavoro di hardening);
  - oppure Local World, non supportato ufficialmente per la produzione;
  - più il build con Nitro o un'integrazione custom.
- Lock-in medio: direttive del compilatore e semantica di replay deterministico.

### C. Vercel Sandbox, eve e il tooling skill (`skills`, `bash-tool`, `just-bash`)

- **`@vercel/sandbox@3.9.1`** (Apache-2.0): microVM Firecracker **ospitate da Vercel**. Fuori da Vercel servono un token di accesso, `VERCEL_TEAM_ID` e `VERCEL_PROJECT_ID`: il servizio resta Vercel. [npm @vercel/sandbox README](https://www.npmjs.com/package/@vercel/sandbox)
- **`just-bash@3.6.0`** (Apache-2.0, Vercel Labs, *"beta software"*): bash simulato in TypeScript con filesystem virtuale.
  - Filesystem: `OverlayFs` copy-on-write su directory reale, `ReadWriteFs`, mount multipli.
  - Comandi dati inclusi: `jq`, `sqlite3`, `xan` (CSV), `yq`.
  - Opzionali: `python3` (CPython), `js-exec` (QuickJS). Rete disabilitata di default.
  
  [just-bash README](https://github.com/vercel-labs/just-bash/blob/main/packages/just-bash/README.md)
- **`bash-tool@1.3.19`** (MIT): tool AI SDK (`bash`, `readFile`, `writeFile`) su just-bash o su `@vercel/sandbox`. Include **`experimental_createSkillTool({ skillsDirectory })`** per skill in formato SKILL.md (directory, caricamento progressivo). Esempi già scritti per AI SDK 7 (`isStepCount`). [github.com/vercel-labs/bash-tool](https://github.com/vercel-labs/bash-tool)
- **`skills@1.8.0`** (MIT): CLI per *installare* skill negli agenti di coding (Claude Code, Codex, Cursor…), `npx skills add …`. Requisito Node 22.20+. È tooling per sviluppatori, non un runtime di skill per la nostra app. [github.com/vercel-labs/skills](https://github.com/vercel-labs/skills)
- **eve** (`eve@1.0.0-rc.9`, Apache-2.0; rc.0 il 2026-10-30): framework "filesystem-first" per agenti durevoli, costruito su AI SDK e Workflow SDK. [github.com/vercel/eve](https://github.com/vercel/eve), [AI SDK docs 10-eve.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-agents/10-eve.mdx)
  - Struttura del progetto: `agent/instructions.md`, `tools/`, `skills/` (SKILL.md, standard Agent Skills), `channels/`, `schedules/` (cron in frontmatter).
  - Self-host: server Node (`.output/`) con World Local (default, file in `.eve/.workflow-data`, un solo processo, recupero delle run al riavvio) o Postgres (repliche). Sandbox di default su Docker se disponibile al build. `eve start` esegue gli schedule. Fonte: docs incluse nel pacchetto npm, `docs/guides/deployment/workflow-worlds.md`, `self-hosted-operations.md`, `schedules.mdx`, `skills.mdx`. [npm eve](https://www.npmjs.com/package/eve)
  - Contrasto da notare: la doc di eve usa il Local World per il self-host a processo singolo, mentre la doc di Workflow lo dichiara "solo sviluppo".
- **Valutazione per la feature 3**: `bash-tool` + `just-bash` con OverlayFs read-only sulle skill è la via più leggera per avere skill SKILL.md con progressive disclosure dentro `ToolLoopAgent`, senza VM.

### D. LangChain: Deep Agents JS, `createAgent` + middleware, LangGraph JS

**Versioni**
- `deepagents@1.16.4` (MIT; skill disponibili da 1.7.0, 2026-02-05).
- `langchain@1.6.4`: la serie 1.x effettiva parte da 1.0.1, il 2025-10-18. Il nome "1.0.0" su npm risale al 2023 ed è un pacchetto storico.
- `@langchain/langgraph@1.7.3` (1.0.0 il 2025-10-18). Tutti MIT.

[npm deepagents](https://www.npmjs.com/package/deepagents), [npm langchain](https://www.npmjs.com/package/langchain), [npm @langchain/langgraph](https://www.npmjs.com/package/@langchain/langgraph)

**Deep Agents**: "batteries-included agent harness". `write_todos` per la pianificazione; filesystem con `read_file`/`write_file`/`edit_file`/`ls`/`glob`/`grep`; subagent (`task`); restituisce un grafo LangGraph compilato. [deepagents README](https://github.com/langchain-ai/deepagentsjs/blob/main/libs/deepagents/README.md)

**Backend del filesystem**: `StateBackend` (default, per thread), `FilesystemBackend`, `LocalShellBackend`, `StoreBackend` (store LangGraph, per utente/assistente/thread), `CompositeBackend` (router), sandbox e backend custom. [deepagents/backends.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/deepagents/backends.mdx)

**Skill**: directory con SKILL.md; all'avvio viene caricato solo il sommario e i file si leggono on demand. Supporta skill per subagent, scrivibili e con approvazione. [deepagents/skills.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/deepagents/skills.mdx)

**Middleware `createAgent`** (built-in): retry di tool e modello, fallback, summarization, human in the loop, limiti di chiamate, PII, to-do list, tool selector, shell, filesystem, subagent, context editing… [middleware/built-in.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/langchain/middleware/built-in.mdx)

**Checkpointer JS**: `MemorySaver`, `@langchain/langgraph-checkpoint-sqlite` ("ideal for experimentation", dipende da **better-sqlite3**), `-postgres`, `-mongodb`, `-redis`. [langgraph/checkpointers.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/langgraph/checkpointers.mdx), [npm checkpoint-sqlite](https://www.npmjs.com/package/@langchain/langgraph-checkpoint-sqlite)

**UI**: `useStream` (`@langchain/react@1.2.13`) si collega via `apiUrl` all'API di streaming dell'agente: in pratica Agent Server o `langgraph dev`. Non usa il protocollo UIMessage dell'AI SDK. AI Elements è utilizzabile come componenti visivi, ma alimentati da `useStream`. In alternativa c'è AG-UI. [langchain/frontend/overview.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/langchain/frontend/overview.mdx), [frontend/integrations/ai-elements.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/langchain/frontend/integrations/ai-elements.mdx), [deepagents/ag-ui.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/deepagents/ag-ui.mdx)

**Cron e deploy**: i cron job sono una funzione dell'Agent Server (LangSmith Deployment). [langsmith/cron-jobs.mdx](https://github.com/langchain-ai/docs/blob/main/src/langsmith/cron-jobs.mdx)
- Agent Server standalone self-host: richiede **PostgreSQL e Redis**, `LANGGRAPH_CLOUD_LICENSE_KEY` ed egress verso `beacon.langchain.com` per licenza e usage reporting. [deploy-standalone-server.mdx](https://github.com/langchain-ai/docs/blob/main/src/langsmith/deploy-standalone-server.mdx)
- *"Self-hosted deployments require an Enterprise plan"*. [deploy-to-self-hosted-overview.mdx](https://github.com/langchain-ai/docs/blob/main/src/langsmith/deploy-to-self-hosted-overview.mdx)

**Valutazione**: harness molto ricco per le feature 3 e 4. Però:
- self-host "completo" (cron, thread API) = Enterprise più Postgres e Redis;
- in alternativa si usano solo le librerie MIT dentro Hono e si scrivono in proprio API e streaming;
- si perde AI SDK UI;
- SQLite via better-sqlite3 su Bun da verificare.

### E. Mastra

**Versioni e licenza**: `@mastra/core@1.82.0` (2026-11-04; 1.0.0 il 2026-01-20). Apache-2.0, tranne le directory `ee/`. La licenza EE serve in produzione solo per: RBAC, FGA, Agent Builder e la schermata di login di Studio con provider di terze parti. **L'autenticazione delle API, anche con Clerk, non richiede EE.** [license.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/license.mdx), [LICENSE.md](https://github.com/mastra-ai/mastra/blob/main/LICENSE.md)

**Server e Bun**: `mastra build` genera un server **Hono** (`index.mjs`) eseguibile su *"Node.js, Bun, or Deno"*. In alternativa ci sono gli adapter per server esistenti (`@mastra/hono@1.7.24`, Express, Fastify, Elysia…). [deployment/mastra-server.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/deployment/mastra-server.mdx), [server/server-adapters.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/server/server-adapters.mdx)

**Memoria e storage**: thread e messaggi su `@mastra/libsql` (SQLite/libSQL, quickstart ufficiale), `@mastra/pg`, `@mastra/mongodb`… Per l'observability si usa DuckDB (`@mastra/duckdb`, consigliato in locale). [memory/overview.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/memory/overview.mdx), [observability/overview.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/observability/overview.mdx)

**Compatibilità con AI SDK**: `@mastra/ai-sdk` (`toAISdkStream`, `toAISdkMessages`, `chatRoute`, `handleChatStream`). Il default è il formato v5; si passa `version: 'v7'` per AI SDK 7. [guides/streaming.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/guides/streaming.mdx)

**Workflow**: suspend/resume, human in the loop, snapshot, time travel. **Workflow schedulati** con `schedule: { cron, timezone }` sulla definizione. Garanzia di consegna *best-effort* (occorrenze perse non rigiocate). Esecuzione in-process senza worker extra. [workflows/scheduled-workflows.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/workflows/scheduled-workflows.mdx)

**Harness**: durable agent (**beta**, da 1.45.0), background task, goal, **schedule per agenti** (da 1.50.0, persistiti; storage LibSQL o PG o altri) e signal. [harness/overview.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/harness/overview.mdx), [harness/durable-agents.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/harness/durable-agents.mdx), [harness/schedules.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/harness/schedules.mdx), [reference/schedules/overview.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/reference/schedules/overview.mdx)

**Resumable stream e PubSub**: `EventEmitterPubSub` (singolo processo) avvolto in `CachingPubSub` per il replay. **Redis non serve con un solo processo**; per più host esiste `RedisStreamsPubSub`. [server/pubsub.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/server/pubsub.mdx)

**Skill e workspace**: skill per agente (`createSkill`) e skill di workspace scoperte da `SKILL.md` (spec Agent Skills). Il workspace offre `LocalFilesystem`, **`S3Filesystem`** e GCS, e sandbox Local, E2B, Daytona… [skills.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/skills.mdx), [sandbox/skills.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/sandbox/skills.mdx), [sandbox/filesystem.mdx](https://github.com/mastra-ai/mastra/blob/main/docs/src/content/en/docs/sandbox/filesystem.mdx)

**Valutazione**: copre le feature 1–4 con SQLite e senza Redis su un solo processo. Il ritmo di rilascio è altissimo (core 1.82 in circa 10 mesi), quindi l'API evolve in fretta. Lock-in medio-alto: modello Agent/Workflow/Memory di Mastra, anche se i modelli restano AI SDK.

### F. Altri SDK agentici e piattaforme di job (brevemente)

- **Claude Agent SDK TS** (`@anthropic-ai/claude-agent-sdk@0.3.322`, licenza "SEE LICENSE IN README" → Anthropic Commercial Terms):
  - esegue il **binario Claude Code**, distribuito come dipendenza opzionale per piattaforma;
  - offre tool built-in, hook, subagent, MCP, permessi, sessioni (JSONL su disco, con `sessionStore` per storage condiviso) e skill da `.claude/`;
  - fit: legato a Claude (API Anthropic) e al runtime Claude Code, mentre ai-vin-app usa `@ai-sdk/openai`. Va bene per tool interni, non come runtime della chat multi-provider.
  
  [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview), [sessions](https://code.claude.com/docs/en/agent-sdk/sessions.md), [npm](https://www.npmjs.com/package/@anthropic-ai/claude-agent-sdk)
- **OpenAI Agents SDK JS** (`@openai/agents@0.21.0`, MIT, ancora 0.x): agent, handoff, guardrail, human in the loop, **sessioni**, **tracing**, MCP, agenti realtime. Supporta Node 22+, Deno e **Bun**. Non ha un protocollo UI compatibile con `useChat`. [README](https://github.com/openai/openai-agents-js)
- **VoltAgent** (`@voltagent/core@2.11.1`, `3.0.0-next.1` in arrivo, MIT): agent, workflow, memoria su LibSQL, server Hono, console VoltOps (cloud o self-host). [README](https://github.com/VoltAgent/voltagent)
- **Inngest**: SDK `inngest@4.26.2` (Apache-2.0). Server e CLI sotto **SSPL** (con DOSP verso Apache).
  - Self-host: `inngest start` è un singolo binario **[Beta]**, con SQLite di default e Redis in-memory nel processo; Postgres e Redis esterni sono opzionali;
  - offre cron ed eventi.
  - **AgentKit** (`@inngest/agent-kit@0.13.2`) non è pubblicato dal 2025-11-13.
  
  [inngest README/licenza](https://github.com/inngest/inngest), [self-hosting.mdx](https://github.com/inngest/website/blob/main/pages/docs/self-hosting.mdx), [npm agent-kit](https://www.npmjs.com/package/@inngest/agent-kit)
- **Trigger.dev v4** (`@trigger.dev/sdk@4.8.4`, Apache-2.0): self-host con Docker Compose, webapp (Postgres, Redis…) **3+ vCPU / 6+ GB** e worker **4+ vCPU / 8+ GB**. Troppo pesante per il nostro caso. Supporta runtime `bun` nei deploy. [self-hosting/docker.mdx](https://github.com/triggerdotdev/trigger.dev/blob/main/docs/self-hosting/docker.mdx), [self-hosting/overview.mdx](https://github.com/triggerdotdev/trigger.dev/blob/main/docs/self-hosting/overview.mdx)

### G. Scheduling e job durevoli leggeri in un singolo processo Bun

- **`Bun.cron`** (nativo): presente nei tipi `bun-types` da **1.3.11** (2026-03-18); Bun corrente 1.4.3.
  - Modalità in-process `Bun.cron(expr, handler)`: garanzia di non sovrapposizione, timezone `{ tz }`, *non sopravvive al riavvio*.
  - Modalità OS-level `Bun.cron(path, expr, title)`: registra su crontab.
  - Per job persi, catch-up e storico serve una tabella propria (per esempio SQLite).
  
  [bun docs runtime/cron.mdx](https://github.com/oven-sh/bun/blob/main/docs/runtime/cron.mdx), [npm bun-types](https://www.npmjs.com/package/bun-types)
- **croner** (`11.0.0`, 2026-10-26, MIT): cron in-process puro JS, alternativa portabile. [npm croner](https://www.npmjs.com/package/croner)
- **bunqueue** (`2.9.21`, MIT, creato il 2026-01-28, maintainer singolo): coda per Bun con memoria o **un file SQLite**, Postgres opzionale, cron, retry, DLQ, backup S3, "No Redis". Server e modalità embedded solo su Bun ≥1.4.0. Progetto giovane. [README](https://github.com/egeominotti/bunqueue)
- **pg-boss** (`12.38.1`, MIT): richiede **Postgres**. **BullMQ** (`6.7.3`, MIT): richiede **Redis**. [npm pg-boss](https://www.npmjs.com/package/pg-boss), [npm bullmq](https://www.npmjs.com/package/bullmq)
- Durevoli "veri":
  - Workflow DevKit: Local World "solo dev", Postgres World = Postgres;
  - Inngest self-host: binario Go in beta più SQLite;
  - Mastra: workflow e schedule su LibSQL.

**Riepilogo delle dipendenze**

| Opzione | Infrastruttura richiesta |
|---|---|
| Bun.cron, croner | nessuna |
| bunqueue | nessuna oltre a SQLite |
| Mastra | SQLite (LibSQL) |
| pg-boss, Workflow Postgres World | Postgres |
| BullMQ, `resumable-stream` | Redis |
| Inngest self-host | un processo/binario in più (SQLite + Redis in-memory interno) |
| Trigger.dev | Postgres, Redis e molto altro |

### H. Elaborazione dati: DuckDB, SQL tool, sandbox

- **DuckDB 2.0.0** annunciato il 2026-10-21. [duckdb-web _posts/2026-10-21-announcing-duckdb-200.md](https://github.com/duckdb/duckdb-web/blob/main/_posts/2026-10-21-announcing-duckdb-200.md)
- **`@duckdb/node-api`** (`2.0.0-r.1`, 2026-10-21; tag `lts-v1.4` = 1.4.5-r.1, MIT): API Promise sul C API, binari per Linux x64/arm64 (glibc e musl), macOS, Windows. **Bun non è menzionato** (vedi Domande aperte). [README pacchetto](https://www.npmjs.com/package/@duckdb/node-api), [duckdb-node-neo](https://github.com/duckdb/duckdb-node-neo)
- **Estensione `excel`** di DuckDB:
  - legge `.xlsx` (`FROM 'file.xlsx'` o `read_xlsx`);
  - **scrive** `.xlsx` con `COPY … TO … (FORMAT xlsx, HEADER)`, limite di 1.048.576 righe per foglio.
  
  Utile per l'export periodico dei log in Excel. [docs/2.0/core_extensions/excel.md](https://github.com/duckdb/duckdb-web/blob/main/docs/2.0/core_extensions/excel.md)
- Lettura da S3: estensione `httpfs` (API S3) di DuckDB, documentata in `docs/*/core_extensions/httpfs/s3api.md` del repo duckdb-web. Bun ha inoltre un client S3 nativo (`Bun.s3`) con streaming, multipart e presign. Il presign si presta all'"area export". [duckdb-web](https://github.com/duckdb/duckdb-web/tree/main/docs), [bun docs runtime/s3.mdx](https://github.com/oven-sh/bun/blob/main/docs/runtime/s3.mdx)
- Pattern "SQL tool": la doc LangGraph ha un tutorial `sql-agent`. In AI SDK il pattern si costruisce con un tool che esegue SELECT read-only, oppure con code mode (QuickJS) per filtrare risultati grandi. [langgraph/sql-agent.mdx](https://github.com/langchain-ai/docs/blob/main/src/oss/langgraph/sql-agent.mdx), [AI SDK 18-code-mode.mdx](https://github.com/vercel/ai/blob/main/content/docs/03-ai-sdk-core/18-code-mode.mdx)
- Sandbox:
  - **just-bash** (in-process, con `sqlite3` e `xan` per CSV, Python opzionale, beta);
  - **Vercel Sandbox** (VM ospitate, account Vercel);
  - **E2B** (`e2b@2.63.0`, cloud; self-host del runtime su AWS, GCP o Azure via "embed", una macchina).
  
  [just-bash README](https://github.com/vercel-labs/just-bash/blob/main/packages/just-bash/README.md), [E2B README](https://github.com/e2b-dev/E2B), [e2b-dev/infra](https://github.com/e2b-dev/infra)

### I. Metering, crediti, licenze per cliente

- **Ledger interno** (SQLite): una tabella movimenti (ricariche contrattuali, consumi per richiesta/API, rettifiche), il saldo derivato e l'abilitazione per API su tabella di piano. Non aggiunge parti mobili e si adatta a crediti prepagati B2B fatturati offline. *Raccomandazione derivata dai requisiti, non da una fonte.*
- **Lago** (AGPL-3.0): metering, crediti prepagati con top-up automatici, entitlement, fatture; indipendente dal processore di pagamento (Stripe, Adyen, GoCardless). Il docker-compose comprende Postgres (partman), Redis, API, worker, clock, front e servizio PDF. Pesante, e l'AGPL va valutata. [lago README](https://github.com/getlago/lago), [docker-compose.yml](https://github.com/getlago/lago/blob/main/docker-compose.yml)
- **OpenMeter** (Apache-2.0): metering, entitlement con grant, saldi di credito, fatturazione. Il quickstart richiede **Kafka, ClickHouse, Redis, Postgres, Svix** più 6 servizi OpenMeter. Sproporzionato per noi. SDK npm `@openmeter/sdk` ancora in `1.0.0-beta.236`. [openmeter README](https://github.com/openmeterio/openmeter), [quickstart compose](https://github.com/openmeterio/openmeter/blob/main/quickstart/docker-compose.yaml)
- **Polar** (Apache-2.0): **merchant of record** (gestisce tasse, ricevute, dunning): orientato a checkout e carte. Non adatto a contratti B2B fatturati offline. Il README non parla di self-host. [polar README](https://github.com/polarsource/polar)
- **Autumn** (`autumn-js@1.5.73`): layer di billing sopra Stripe. Il repo `github.com/useautumn/autumn` indicato su npm **non era accessibile pubblicamente da questa sessione**; licenza e self-host non verificati. [npm autumn-js](https://www.npmjs.com/package/autumn-js)
- **Flowglad**: `@flowglad/server@0.18.0`, ultimo rilascio il 2026-01-29. Repo `github.com/flowglad/flowglad` **non accessibile** da questa sessione; stato non verificato. [npm @flowglad/server](https://www.npmjs.com/package/@flowglad/server)
- **Stripe Billing (meters, credit grants)**: pensato per clienti Stripe con fatturazione Stripe. Documentazione **non verificata** in questa sessione (stripe.com non raggiungibile). [docs.stripe.com/billing](https://docs.stripe.com/billing)

---

## 3. Tabella comparativa

Legenda: ✅ supportato nativamente · 🟡 parziale o fai-da-te · ❌ assente. F1 = chat persistente/resume/generative UI · F2 = schedulazione e job lunghi · F3 = skill · F4 = dataset/SQL/sandbox · F5 = crediti/licenze.

| Candidato | F1 | F2 | F3 | F4 | F5 | Parti mobili aggiunte | Self-host su Bun | Maturità (2026-11) | Licenza |
|---|---|---|---|---|---|---|---|---|---|
| AI SDK v7 (`ToolLoopAgent`) | ✅ UI/tool streaming/data part; persistenza 🟡; resume = Redis | ❌ | 🟡 (solo via `bash-tool`) | 🟡 code mode (sperim.) | ❌ | nessuna (Redis se resume standard) | libreria; Bun non nei runtime testati | GA, v7.0.168 | Apache-2.0 |
| AI SDK `WorkflowAgent` + Workflow DevKit | ✅ incluso resume senza Redis | ✅ durevole, sleep; cron ❌ (esterno) | 🟡 | 🟡 | ❌ | Postgres (prod) o Local World (dev); build Nitro/custom | 🟡 integrazione Bun "per autori di framework" | v5 GA; Postgres World = reference | Apache-2.0 |
| eve | ✅ (canali web) | ✅ schedule cron, run durevoli | ✅ SKILL.md | 🟡 sandbox Docker/just-bash | ❌ | server eve dedicato; Local World o Postgres; Docker per sandbox | 🟡 doc parla di Node | **RC** (1.0.0-rc.9) | Apache-2.0 |
| Mastra | ✅ memoria su LibSQL; resume via `CachingPubSub`; stream → AI SDK v7 | ✅ workflow con cron (best-effort), suspend/resume; durable agent beta | ✅ SKILL.md, workspace S3 | 🟡 workspace/sandbox; DuckDB solo observability | ❌ | SQLite (LibSQL); nient'altro su un solo processo | ✅ dichiarato (Node/Bun/Deno); adapter Hono | GA 1.x, API in rapida evoluzione | Apache-2.0 (+EE per RBAC/FGA) |
| LangChain Deep Agents + LangGraph JS | 🟡 checkpointer; UI `useStream` legata ad Agent Server | 🟡 cron solo su Agent Server | ✅ SKILL.md | ✅ backend FS/sandbox, middleware | ❌ | Agent Server: Postgres+Redis+licenza; oppure codice proprio | 🟡 (SQLite via better-sqlite3 da verificare) | GA 1.x | MIT (Agent Server proprietario) |
| Claude Agent SDK | 🟡 sessioni JSONL/`sessionStore` | ❌ | ✅ (`.claude/skills`) | ✅ tool built-in | ❌ | binario Claude Code per piattaforma | 🟡 (supporto `bun build --compile` documentato) | 0.3.x | Commercial Terms |
| OpenAI Agents JS | 🟡 sessioni, tracing | ❌ | ❌ | 🟡 sandbox agent | ❌ | nessuna | ✅ (Bun dichiarato) | 0.21 | MIT |
| VoltAgent | 🟡 memoria LibSQL | 🟡 workflow | ? | ? | ❌ | LibSQL | probabile (server Hono) | 2.x (3.0 next) | MIT |
| Inngest (+AgentKit) | 🟡 | ✅ cron, step durevoli | ❌ | ❌ | ❌ | binario Go (beta) + SQLite + Redis in-proc | SDK sì; server separato | server beta (self-host); AgentKit fermo | SSPL (server), Apache (SDK) |
| Trigger.dev v4 | ❌ | ✅ | ❌ | ❌ | ❌ | stack Docker (Postgres, Redis…; 7+ vCPU) | runtime bun supportato nei task | GA v4 | Apache-2.0 |
| Bun.cron / croner | – | 🟡 in-process, niente catch-up | – | – | – | nessuna | ✅ nativo | stabile | MIT (Bun) / MIT |
| bunqueue | – | ✅ coda + cron su SQLite | – | – | – | nessuna (SQLite) | ✅ (Bun ≥1.4) | giovane, maintainer singolo | MIT |
| pg-boss / BullMQ | – | ✅ | – | – | – | Postgres / Redis | ✅ | maturi | MIT |
| DuckDB (`@duckdb/node-api`) | – | 🟡 export xlsx | – | ✅ CSV/XLSX/Parquet/S3/SQLite | – | nessuna (embedded) | ❓ non dichiarato | DuckDB 2.0 GA; binding 2.0.0-r.1 | MIT |
| just-bash + bash-tool | – | – | ✅ SKILL.md (sperim.) | ✅ jq/sqlite3/xan, in-process | – | nessuna | ✅ probabile (TS puro) | beta | Apache-2.0 / MIT |
| Ledger crediti interno (SQLite) | – | – | – | – | ✅ su misura | nessuna | ✅ | da costruire | – |
| Lago | – | – | – | – | ✅ crediti prepagati, fatture | Postgres, Redis, API, worker, clock, front, PDF | servizio separato | GA | AGPL-3.0 |
| OpenMeter | – | – | – | – | ✅ grant/entitlement | Kafka, ClickHouse, Redis, Postgres, Svix | servizio separato | GA (SDK npm beta) | Apache-2.0 |
| Polar / Autumn / Stripe | – | – | – | – | 🟡 orientati a carta/Stripe | SaaS (Stripe) | – | GA | Apache (Polar) / ? / proprietario |

---

## 4. Domande aperte e punti incerti

- **Siti di documentazione non raggiungibili**: ai-sdk.dev, vercel.com, mastra.ai, docs.langchain.com, inngest.com, trigger.dev, duckdb.org, bun.com, stripe.com, useautumn.com, polar.sh, openmeter.io. Ho usato i sorgenti delle stesse doc su GitHub. Possibili piccole differenze di pubblicazione.
- **AI SDK v7 su Bun**: la guida richiede Node ≥22 ed è solo ESM, ma non menziona Bun. Lo stesso vale per `@ai-sdk/code-mode` (QuickJS, "not available in browser or edge runtimes"). Da verificare con uno spike (`bun test`).
- **AI SDK 7 GA o beta**: il changelog Vercel (letto solo come snippet) e il dist-tag `latest` = 7.0.x indicano GA; una fonte terza parlava di beta. Considero GA (dist-tag `latest` dal 2026-06-25).
- **Workflow DevKit**:
  - è supportato l'uso del Local World in produzione a processo singolo? La doc Workflow dice di no; la doc eve lo usa come default self-host;
  - compatibilità del World Turso/libSQL con la v5 non verificata;
  - integrazione con Bun (non Nitro) documentata solo come guida per autori di framework.
- **Mastra su Bun**: la doc dichiara Bun per il server generato. Non ho verificato `@mastra/libsql` (`@libsql/client`, nativo) sotto Bun né i test CI di Mastra su Bun.
- **LangGraph SQLite checkpointer**: dipende da `better-sqlite3`; il supporto di Bun a questo addon nativo non è verificato. Non ho verificato neppure se `useStream` possa collegarsi a un backend custom diverso da Agent Server o `langgraph dev`.
- **LangGraph Agent Server standalone**: la licenza è richiesta (`LANGGRAPH_CLOUD_LICENSE_KEY`). Non ho verificato se esista un tier gratuito o "lite" per il self-host standalone nel 2026: la doc sul self-host generale dice Enterprise.
- **`@duckdb/node-api` su Bun**: non dichiarato. È un addon N-API, in teoria compatibile, ma da testare. Da capire anche se conviene la major 2.0.0-r.1 o la `lts-v1.4`.
- **eve**: maturità (RC), possibilità di integrarlo in un'app Hono esistente invece che come servizio separato, supporto Bun: non verificati.
- **Autumn e Flowglad**: repository GitHub non accessibili pubblicamente da questa sessione (`git ls-remote` chiede credenziali), quindi licenza, self-host e stato non verificati. Flowglad non pubblica su npm da gennaio 2026.
- **Stripe Billing** (meters, credit grants): non verificato in questa sessione.
- **AI Elements**: deprecazione annunciata per fine novembre 2026 a favore della versione shadcn/ui. Da verificare la disponibilità della nuova versione e il supporto Vite (il README attuale cita Next.js).
- **bunqueue**: progetto di un singolo maintainer, nato a gennaio 2026. Le statistiche di download non sono verificabili (api.npmjs.org bloccato).
