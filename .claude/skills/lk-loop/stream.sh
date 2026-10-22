#!/usr/bin/env bash
# Segue in diretta (tipo `tail -f`) la conversazione Claude di un ticket, dato
# solo il numero della issue: legge il session_id dal suo file di stato e
# fa il tail del .jsonl di quella sessione. Gira interamente sull'HOST — il
# .jsonl vive già lì via il bind-mount di .claude-home, nessun docker
# coinvolto, nessuna attesa di build immagine.
# Uso: ./stream.sh <numero-issue> [--all]
#   --all: mostra anche le righe "attachment" (hook, telemetria interna) —
#          di default sono nascoste, sono spesso più della metà delle righe
#          e non fanno parte della conversazione vera e propria.
set -euo pipefail

SCAFFOLD_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCAFFOLD_ABS/.env"

# Le env var non servono a leggere il .jsonl (è un file locale), ma si carica
# comunque .env per coerenza con gli altri comandi — "usa le env già
# predisposte" invece di richiedere altro setup.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$ENV_FILE"
  set +a
fi

n="${1:?uso: ./stream.sh <numero-issue> [--all]}"
show_all=0; [[ "${2:-}" == "--all" ]] && show_all=1

state="${SCAFFOLD_ABS}/.loop-logs/state/issue-${n}.json"
[[ -f "$state" ]] || { echo "Nessuno stato per la issue #$n in $state." >&2; exit 1; }
sid=$(jq -r '.session_id // empty' "$state")
[[ -n "$sid" ]] || { echo "Nessun session_id in $state." >&2; exit 1; }

jsonl="${SCAFFOLD_ABS}/.claude-home/.claude/projects/-workspace/${sid}.jsonl"

echo "Ticket #$n — sessione $sid"
echo "$jsonl"
[[ -f "$jsonl" ]] || echo "(il file non esiste ancora — resto in attesa che la sessione parta...)"
echo "---"

# `-F` (= --follow=name --retry): segue per nome e aspetta che il file compaia
# se non esiste ancora, a differenza di `-f` che richiede il file già presente.
tail -F -n +1 "$jsonl" 2>/dev/null | while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  jq -r --argjson all "$show_all" '
    def trunc($n): if (.|length) > $n then .[0:$n] + "…" else . end;
    if (.type == "assistant" or .type == "user") then
      (.timestamp[11:19] // "??:??:??") as $t
      | (.message.role // .type) as $role
      | (.message.content // []) as $content
      | (if .isApiErrorMessage == true or .error then "  ⚠ " else "" end) as $warn
      | if ($content|type) == "string" then
          "[\($t)]\($warn) \($role): \($content|trunc(300))"
        elif ($content|type) == "array" then
          ($content[] |
            if .type == "text" then "[\($t)]\($warn) \($role): \(.text|trunc(300))"
            elif .type == "thinking" then "[\($t)] \($role) (thinking): \(.thinking|trunc(200))"
            elif .type == "tool_use" then "[\($t)] \($role) → \(.name): \((.input|tostring)|trunc(200))"
            elif .type == "tool_result" then
              ((if (.content|type) == "array" then ([.content[]?.text // (.content[]|tostring)] | join(" ")) else (.content|tostring) end) | trunc(300)) as $c
              | "[\($t)] \($role) ← tool_result\(if .is_error then " (error)" else "" end): \($c)"
            else "[\($t)] \($role): \(.|tostring|trunc(150))" end
          )
        else empty end
    elif ($all == 1 and .type == "attachment") then
      (.timestamp[11:19] // "??:??:??") as $t
      | "[\($t)] hook(\(.attachment.hookName // "?")): \(((.attachment.stdout // .attachment.content // "")|tostring)|trunc(150))"
    else empty end
  ' <<<"$line" 2>/dev/null || true
done
