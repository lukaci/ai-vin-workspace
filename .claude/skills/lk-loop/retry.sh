#!/usr/bin/env bash
# Riprova UN ticket già fallito, in modo scriptato/headless — stessa identica
# sessione Claude di prima (claude -p --resume), nessuna TUI si apre, stesso
# branch condiviso, stesso pattern a due volumi di run-batch.sh. Per ispezionare
# invece la sessione a mano (TUI interattiva) usa ./manual-resume.sh.
# Uso: ./retry.sh <numero-issue> [max-turns]
#   max-turns: opzionale, sovrascrive MAX_TURNS di loop.sh solo per questo retry
#              (budget per-invocazione, non cumulativo con i turni già usati
#              dalla sessione originale).
set -euo pipefail

# Auto-inhibisce la sospensione dell'host per la durata del retry — stesso
# meccanismo e stessa motivazione di run-batch.sh (vedi lì per i dettagli).
if [[ -z "${LK_LOOP_INHIBITED:-}" ]] && command -v systemd-inhibit >/dev/null; then
  export LK_LOOP_INHIBITED=1
  exec systemd-inhibit --what=sleep:idle --who="lk-loop" --why="retry ticket in corso" --mode=block "$0" "$@"
fi

SCAFFOLD_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT: percorso assoluto del repo, riempito dallo scaffolder al momento
# della generazione (stesso valore usato in run-batch.sh).
REPO_ROOT="{{REPO_ROOT}}"
ENV_FILE="$SCAFFOLD_ABS/.env"

n="${1:?uso: ./retry.sh <numero-issue> [max-turns]}"
turns="${2:-}"

# --- Carica token/branch/modello cacheati, se presenti ---
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
  set +a
fi

# --- Token OAuth per Claude — stesso flusso di run-batch.sh/manual-resume.sh ---
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

# --- Token GitHub: sempre riverificato — serve per il flip label su successo ---
if ! GITHUB_TOKEN="$(gh auth token 2>/dev/null)"; then
  echo "== Login GitHub necessario =="
  gh auth login
  GITHUB_TOKEN="$(gh auth token)"
fi
export GITHUB_TOKEN

# --- Modello/effort: stessi default di run-batch.sh ---
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-5}"
CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-medium}"
export ANTHROPIC_MODEL
export CLAUDE_CODE_EFFORT_LEVEL

# --- Branch: DEVE essere quello già cacheato da run-batch.sh — un retry
# continua la STESSA sessione sullo STESSO branch condiviso, non ne calcola
# uno nuovo (a differenza di run-batch.sh, che ne crea uno se serve).
: "${TARGET_BRANCH:?Nessun TARGET_BRANCH in $ENV_FILE — lancia prima ./run-batch.sh almeno una volta.}"
export TARGET_BRANCH

# --- Salva token/branch/modello per le prossime volte ---
umask 077
{
  echo "# Token + branch + modello/effort cacheati — segreti, non committare/condividere."
  printf 'CLAUDE_CODE_OAUTH_TOKEN=%q\n' "$CLAUDE_CODE_OAUTH_TOKEN"
  printf 'GITHUB_TOKEN=%q\n' "$GITHUB_TOKEN"
  printf 'TARGET_BRANCH=%q\n' "$TARGET_BRANCH"
  printf 'ANTHROPIC_MODEL=%q\n' "$ANTHROPIC_MODEL"
  printf 'CLAUDE_CODE_EFFORT_LEVEL=%q\n' "$CLAUDE_CODE_EFFORT_LEVEL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Ticket           : #${n}"
echo "Max turns        : ${turns:-<default di loop.sh>}"
echo "Branch target    : ${TARGET_BRANCH}"

docker build -t claude-loop -f "$SCAFFOLD_ABS/Dockerfile" "$SCAFFOLD_ABS" >/dev/null

docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/scaffold/.claude-home \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e GITHUB_TOKEN \
  -e TARGET_BRANCH \
  -e ANTHROPIC_MODEL \
  -e CLAUDE_CODE_EFFORT_LEVEL \
  -v "$REPO_ROOT":/workspace \
  -v "$SCAFFOLD_ABS":/scaffold \
  -w /workspace \
  claude-loop bash /scaffold/loop.sh --retry "$n" ${turns:+"$turns"}

echo "Indice run          : ${SCAFFOLD_ABS}/.loop-logs/SUMMARY.md"
echo "Stato per-issue     : ${SCAFFOLD_ABS}/.loop-logs/state/issue-${n}.json"
