#!/usr/bin/env bash
# Lanciatore da eseguire SULL'HOST (Fedora), da dentro la cartella di scaffold
# generata da /lk-loop — un SIBLING del repo (fuori dal suo working tree), non
# una sua sottocartella. Gestisce l'unico passo interattivo (generazione token),
# calcola il branch target, e fa girare il loop dentro il container montando
# repo e scaffold come due volumi separati.
set -euo pipefail

# Auto-inhibisce la sospensione dell'host per tutta la durata della run — una
# run non presidiata di più ticket può durare a lungo, e una sospensione a
# metà (osservato: "connection lost" su un ticket) interrompe la sessione
# Claude senza modo di distinguerla da un fallimento vero. Si ri-esegue da
# solo sotto `systemd-inhibit` una volta sola (LK_LOOP_INHIBITED evita il
# loop), rilasciato automaticamente all'uscita, successo o errore. Blocca
# solo sleep/idle, non il dimming dello schermo (DPMS/lid, gestiti a parte).
# Nessun effetto se systemd-inhibit non c'è: la run parte comunque, solo
# senza protezione dalla sospensione.
if [[ -z "${LK_LOOP_INHIBITED:-}" ]] && command -v systemd-inhibit >/dev/null; then
  export LK_LOOP_INHIBITED=1
  exec systemd-inhibit --what=sleep:idle --who="lk-loop" --why="batch implement loop in corso" --mode=block "$0" "$@"
fi

SCAFFOLD_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT: percorso assoluto del repo, riempito dallo scaffolder al momento
# della generazione (lo scaffold vive fuori dal repo, quindi non può risalirci
# con `git rev-parse` da solo).
REPO_ROOT="{{REPO_ROOT}}"
ENV_FILE="$SCAFFOLD_ABS/.env"

# --- -1) Carica token cacheati da una run precedente, se presenti ---
# Scritto in fondo a questo blocco dopo l'acquisizione. Cancellare $ENV_FILE
# forza a rifare l'intero check (nuovo token Claude + verifica GitHub) da capo.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
  set +a
fi

# --- 0) prerequisiti host ---
command -v docker >/dev/null || { echo "docker non trovato sull'host." >&2; exit 1; }
command -v git    >/dev/null || { echo "git non trovato sull'host." >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "Repo non trovato in ${REPO_ROOT} (spostata la cartella del repo?)." >&2; exit 1; }

# --- 1) Token OAuth per Claude (unico passo che richiede intervento umano) ---
# Se è già esportato — dall'ambiente o appena caricato da $ENV_FILE — salta e
# non chiede nulla.
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  command -v claude >/dev/null \
    || { echo "Serve la CLI di Claude Code sull'host per generare il token (installala col native installer)." >&2; exit 1; }
  echo "== Genero il token OAuth: si aprirà il browser =="
  claude setup-token || true   # apre il browser e stampa un token sk-ant-oat...
  echo
  read -rsp "Incolla qui il token generato (sk-ant-oat...): " CLAUDE_CODE_OAUTH_TOKEN
  echo
  export CLAUDE_CODE_OAUTH_TOKEN
fi
[[ "${CLAUDE_CODE_OAUTH_TOKEN}" == sk-ant-oat* ]] \
  || { echo "Token non valido (atteso prefisso sk-ant-oat)." >&2; exit 1; }

# --- 2) Token GitHub: riusa il login gh esistente, altrimenti login interattivo ---
# Sempre riverificato con `gh auth token`, anche se già presente da $ENV_FILE —
# non ci si fida ciecamente di un token cacheato che nel frattempo potrebbe
# essere scaduto o revocato.
if ! GITHUB_TOKEN="$(gh auth token 2>/dev/null)"; then
  echo "== Login GitHub necessario =="
  gh auth login
  GITHUB_TOKEN="$(gh auth token)"
fi
export GITHUB_TOKEN
# Nota: il token deve avere scope per editare le label delle issue (issues: write) e per il push.

# --- 2b) Modello ed effort level per Claude: default cacheati in .env,
# modificabili a mano in qualsiasi momento senza toccare nessuno script —
# basta editare la riga in .env e rilanciare. Letti NATIVAMENTE dalla CLI
# tramite le env var ANTHROPIC_MODEL e CLAUDE_CODE_EFFORT_LEVEL (confermato
# nel binario: fallback interno a "high" se assente), quindi non serve
# passare --model/--effort nella chiamata a `claude` dentro loop.sh — bastano
# le -e nel docker run più sotto.
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-5}"
CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-medium}"
export ANTHROPIC_MODEL
export CLAUDE_CODE_EFFORT_LEVEL
echo "Modello Claude   : ${ANTHROPIC_MODEL}"
echo "Effort level     : ${CLAUDE_CODE_EFFORT_LEVEL}"

# --- 3) Branch target: riusa quello cacheato se il repo è ancora lì sopra —
# altrimenti <branch corrente>-implementation-<timestamp senza ms> ---
# Senza questo, ogni retry da dentro un branch di implementation ne accoda un
# altro sopra invece di continuarci (osservato: tre "-implementation-<ts>"
# impilati dopo tre run). $ENV_FILE carica un eventuale TARGET_BRANCH cacheato
# dal blocco -1 sopra; se il repo è ESATTAMENTE lì sopra ora, resta lì.
CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ -n "${TARGET_BRANCH:-}" ]] && [[ "$CURRENT_BRANCH" == "$TARGET_BRANCH" ]]; then
  echo "Riuso il branch target cacheato (il repo è già lì sopra): ${TARGET_BRANCH}"
else
  TS="$(date +%Y%m%d-%H%M%S)"
  TARGET_BRANCH="${CURRENT_BRANCH}-implementation-${TS}"
fi
export TARGET_BRANCH
export CURRENT_BRANCH
echo "Repo root        : ${REPO_ROOT}"
echo "Cartella scaffold: ${SCAFFOLD_ABS}"
echo "Branch corrente  : ${CURRENT_BRANCH}"
echo "Branch target    : ${TARGET_BRANCH}"

# Consiglio: parti da un working tree pulito, così il nuovo branch è pulito.
if ! git -C "$REPO_ROOT" diff --quiet || ! git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "ATTENZIONE: ci sono modifiche non committate nel working tree." >&2
  read -rp "Continuo comunque? [y/N] " ans; [[ "${ans:-N}" == [yY] ]] || exit 1
fi

# --- 3b) Salva token + branch per le run successive (retry senza rifare
# token/login, e senza accodare un altro -implementation- se si è ancora lì).
# %q quota in modo sicuro per il sourcing; permessi 600 perché i token sono
# segreti. La cartella di scaffold è già fuori dal repo git, quindi fuori da
# ogni rischio di commit accidentale. Per forzare un branch nuovo pur tenendo
# i token cacheati: cancella solo la riga TARGET_BRANCH da questo file (o
# spostati su un altro branch prima di rilanciare).
umask 077
{
  echo "# Token + branch + modello/effort cacheati da run-batch.sh — segreti, non committare/condividere."
  echo "# Cancella questo file per rifare da capo token Claude + verifica GitHub."
  echo "# ANTHROPIC_MODEL / CLAUDE_CODE_EFFORT_LEVEL: modificabili a mano qui in"
  echo "# qualsiasi momento, non serve toccare gli script."
  printf 'CLAUDE_CODE_OAUTH_TOKEN=%q\n' "$CLAUDE_CODE_OAUTH_TOKEN"
  printf 'GITHUB_TOKEN=%q\n' "$GITHUB_TOKEN"
  printf 'TARGET_BRANCH=%q\n' "$TARGET_BRANCH"
  printf 'ANTHROPIC_MODEL=%q\n' "$ANTHROPIC_MODEL"
  printf 'CLAUDE_CODE_EFFORT_LEVEL=%q\n' "$CLAUDE_CODE_EFFORT_LEVEL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# --- 4) Build immagine (idempotente) + run del loop nel container ---
docker build -t claude-loop -f "$SCAFFOLD_ABS/Dockerfile" "$SCAFFOLD_ABS" >/dev/null

docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/scaffold/.claude-home \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e GITHUB_TOKEN \
  -e TARGET_BRANCH \
  -e CURRENT_BRANCH \
  -e ANTHROPIC_MODEL \
  -e CLAUDE_CODE_EFFORT_LEVEL \
  -v "$REPO_ROOT":/workspace \
  -v "$SCAFFOLD_ABS":/scaffold \
  -w /workspace \
  claude-loop bash /scaffold/loop.sh

chmod +x "$SCAFFOLD_ABS/retry.sh" "$SCAFFOLD_ABS/manual-resume.sh" "$SCAFFOLD_ABS/stream.sh" 2>/dev/null || true
echo "Fatto. Sul repo trovi il branch: ${TARGET_BRANCH}"
echo "Indice run          : ${SCAFFOLD_ABS}/.loop-logs/SUMMARY.md"
echo "Stato per-issue     : ${SCAFFOLD_ABS}/.loop-logs/state/"
echo "Ticket fallito, stessa sessione, headless: ./retry.sh <numero-issue> [max-turns]   (da dentro ${SCAFFOLD_ABS}/)"
echo "Apri una sessione in interattivo         : ./manual-resume.sh <numero-issue>       (da dentro ${SCAFFOLD_ABS}/)"
echo "Segui in diretta un ticket in corso       : ./stream.sh <numero-issue> [--all]      (da dentro ${SCAFFOLD_ABS}/)"
