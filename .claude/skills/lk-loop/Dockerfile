FROM node:22-bookworm-slim

# Strumenti: git, jq (parsing issue), uuid (session-id), gh (GitHub CLI),
# unzip (richiesto dall'installer ufficiale di bun, sotto).
RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq ca-certificates uuid-runtime bash curl gnupg unzip \
 && mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Pinna una versione per build riproducibili (es. @2.1.224). @latest per l'ultima.
RUN npm install -g @anthropic-ai/claude-code@latest

# {{RUNTIME_SETUP}} — riempito dallo scaffolder se il repo target usa un
# runtime/package manager diverso da npm (bun, pnpm, yarn...). Vedi step 4 di
# SKILL.md: senza questo, ogni ticket lo riscopre e reinstalla da zero nella
# propria sessione — turni sprecati su setup ambiente invece che sul ticket.

# {{GRAFT_SETUP}} — riempito dallo scaffolder se il repo target usa graft
# (.mcp.json con un server "graft", o .claude/skills/graft/). Senza il binario
# globale, sia gli mcp__graft__* tool sia l'hook di auto-aggiornamento del
# grafo (.claude/helpers/graft-hooks.cjs, che risolve via `npm root -g`)
# falliscono silenziosamente — ogni ticket ripiega su grep/read grezzi,
# proprio il costo in token che il grafo esiste per evitare.

WORKDIR /workspace
# Nessun USER fisso: il container va lanciato con --user "$(id -u):$(id -g)"
# (uid != 0 => --dangerously-skip-permissions è consentito, e i file sul bind
# mount restano di tua proprietà sull'host).
