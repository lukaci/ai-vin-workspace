#!/usr/bin/env bash
# Riapre in interattivo la sessione Claude di un ticket, senza dover leggere i log.
# Per continuare invece un ticket FALLITO in modo scriptato/headless (stessa
# sessione, come run-batch.sh) usa ./retry.sh — questo script è solo per
# l'ispezione manuale via TUI.
# Va lanciato da dentro la cartella di scaffold generata da /lk-loop (sibling del
# repo, fuori dal suo working tree).
# Uso:  ./manual-resume.sh <numero-issue>     (legge il session id da .loop-logs/state)
#       ./manual-resume.sh <session-id>       (id diretto)
set -euo pipefail

SCAFFOLD_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT: percorso assoluto del repo, riempito dallo scaffolder al momento
# della generazione (stesso valore usato in run-batch.sh).
REPO_ROOT="{{REPO_ROOT}}"
ENV_FILE="$SCAFFOLD_ABS/.env"

# Carica i token cacheati da run-batch.sh, se presenti — stesso blocco, stessa
# logica di run-batch.sh, così i due comandi si comportano allo stesso modo.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
  set +a
fi

arg="${1:?uso: ./manual-resume.sh <numero-issue|session-id>}"
if [[ "$arg" =~ ^[0-9]+$ ]]; then
  state="${SCAFFOLD_ABS}/.loop-logs/state/issue-${arg}.json"
  [[ -f "$state" ]] || { echo "Nessuno stato per la issue #$arg." >&2; exit 1; }
  sid=$(jq -r '.session_id' "$state")
else
  sid="$arg"
fi

# Se il token non è nell'ambiente né nel cache appena caricato, acquisiscilo —
# stesso identico flusso di run-batch.sh, così un resume "a freddo" (shell
# nuova, nessuna run precedente) funziona senza dover lanciare prima il batch.
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

# Modello/effort: stesso default di run-batch.sh se non già cacheati/esportati —
# modificabili a mano in .env in qualsiasi momento, non serve toccare gli script.
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-claude-sonnet-5}"
CLAUDE_CODE_EFFORT_LEVEL="${CLAUDE_CODE_EFFORT_LEVEL:-medium}"
export ANTHROPIC_MODEL
export CLAUDE_CODE_EFFORT_LEVEL

# Cachealo per le prossime volte — preservando GITHUB_TOKEN e TARGET_BRANCH se
# già presenti nel file (run-batch.sh li scrive, manual-resume.sh non li
# usa/calcola e non deve cancellarli riscrivendo l'intero file).
umask 077
{
  echo "# Token cacheati — segreti, non committare/condividere."
  echo "# Cancella questo file per rifare da capo token Claude + verifica GitHub."
  printf 'CLAUDE_CODE_OAUTH_TOKEN=%q\n' "$CLAUDE_CODE_OAUTH_TOKEN"
  [[ -n "${GITHUB_TOKEN:-}" ]] && printf 'GITHUB_TOKEN=%q\n' "$GITHUB_TOKEN"
  [[ -n "${TARGET_BRANCH:-}" ]] && printf 'TARGET_BRANCH=%q\n' "$TARGET_BRANCH"
  printf 'ANTHROPIC_MODEL=%q\n' "$ANTHROPIC_MODEL"
  printf 'CLAUDE_CODE_EFFORT_LEVEL=%q\n' "$CLAUDE_CODE_EFFORT_LEVEL"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Stesso HOME/repo della run: le trascrizioni vivono in <scaffold>/.claude-home,
# montato insieme al repo (due volumi separati), quindi il resume le trova.
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/scaffold/.claude-home \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e ANTHROPIC_MODEL \
  -e CLAUDE_CODE_EFFORT_LEVEL \
  -v "$REPO_ROOT":/workspace \
  -v "$SCAFFOLD_ABS":/scaffold \
  -w /workspace \
  claude-loop claude --resume "$sid"
