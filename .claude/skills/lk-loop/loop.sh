#!/usr/bin/env bash
# Eseguito DENTRO il container. Ordina i ticket in ordine di dipendenza, li
# implementa su un unico branch, avanza lo stato senza chiudere le issue, e
# compila file di stato + un indice riprendibile (SUMMARY.md).
#
# Generato da /scaffold-implement-loop. I placeholder {{...}} sono riempiti dallo
# scaffolder in base a docs/agents/triage-labels.md e alle scelte dell'utente.
set -euo pipefail

# === Configurazione (riempita dallo scaffolder) ===
LABEL_TODO="{{LABEL_TODO}}"        # ruolo canonico: ready-for-agent
LABEL_DONE="{{LABEL_DONE}}"        # ruolo canonico: ready-for-human
MAX_TURNS={{MAX_TURNS}}

# La cartella di scaffold è montata separatamente su /scaffold (run-batch.sh
# monta repo e scaffold come due volumi distinti, essendo sibling sull'host).
LOG_DIR="/scaffold/.loop-logs"
STATE_DIR="${LOG_DIR}/state"       # un JSON per issue: stato + metadati sessione
RUN_DIR="${LOG_DIR}/logs"          # output grezzo per ticket
SUMMARY="${LOG_DIR}/SUMMARY.md"    # indice umano con i comandi di resume

now(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

# === Setup ambiente container ===
mkdir -p "$HOME" "$STATE_DIR" "$RUN_DIR"
# Il trust dialog è per-progetto (projects["/workspace"].hasTrustDialogAccepted),
# non un flag globale — senza questo, .claude/settings.json e settings.local.json
# del repo vengono ignorati ad ogni ticket. Merge idempotente: sana anche uno
# stato scritto da un run precedente che non lo settava ancora.
if [[ -f "$HOME/.claude.json" ]]; then
  tmp="$(mktemp)"
  jq '.hasCompletedOnboarding = true | .projects["/workspace"].hasTrustDialogAccepted = true' \
    "$HOME/.claude.json" > "$tmp" && mv "$tmp" "$HOME/.claude.json"
else
  jq -n '{hasCompletedOnboarding:true, projects:{"/workspace":{hasTrustDialogAccepted:true}}}' \
    > "$HOME/.claude.json"
fi
git config --global user.name  "${GIT_AUTHOR_NAME:-claude-batch}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-claude-batch@localhost}"
git config --global --add safe.directory /workspace
gh auth setup-git

# -c crea il branch: fallirebbe se run-batch.sh sta riusando un TARGET_BRANCH
# già esistente da una run precedente (stesso branch, retry). Crea solo se
# manca, altrimenti si limita a spostarcisi sopra.
if git rev-parse --verify --quiet "$TARGET_BRANCH" >/dev/null; then
  git switch "$TARGET_BRANCH"
else
  git switch -c "$TARGET_BRANCH"
fi

# === Helper: scrive lo stato di una issue come JSON ===
# args: n sid status started ended turns cost log html
write_state(){
  jq -n \
    --argjson issue "$1" --arg title "${TITLE[$1]:-}" --arg branch "$TARGET_BRANCH" \
    --arg sid "$2" --arg status "$3" --arg started "$4" --arg ended "$5" \
    --argjson turns "${6:-null}" --argjson cost "${7:-null}" \
    --arg log "$8" --arg html "${9:-}" \
    --arg resume "./manual-resume.sh $1" --arg retry "./retry.sh $1" \
    '{issue:$issue,title:$title,branch:$branch,session_id:$sid,status:$status,
      started_at:$started,ended_at:(if $ended=="" then null else $ended end),num_turns:$turns,
      cost_usd:$cost,log:$log,transcript_html:$html,resume_cmd:$resume,retry_cmd:$retry}' \
    > "$STATE_DIR/issue-$1.json"
}

# === Helper: rigenera l'indice umano SUMMARY.md dai file di stato ===
render_summary(){
  { echo "# Batch implement — ${TARGET_BRANCH}"
    echo; echo "_Aggiornato: $(now)_"; echo
    echo "Ticket fallito, stessa sessione, headless: \`./retry.sh <numero-issue> [max-turns]\`."
    echo "Per aprirlo invece in interattivo: \`./manual-resume.sh <numero-issue>\` (o passa direttamente il session id)."; echo
    echo "| Issue | Titolo | Stato | Turni | Costo USD | Session ID | Retry | Manuale | Trascrizione |"
    echo "|---|---|---|---|---|---|---|---|---|"
    for f in $(ls "$STATE_DIR"/issue-*.json 2>/dev/null | sort -t- -k2 -n); do
      jq -r '"| #\(.issue) | \(.title|gsub("\\|";"\\|")) | \(.status) | \(.num_turns // "–") | \(.cost_usd // "–") | `\(.session_id)` | `\(.retry_cmd)` | `\(.resume_cmd)` | [apri](logs/ticket-\(.issue).html) |"' "$f" 2>/dev/null || true
    done
  } > "$SUMMARY"
}

# === Helper: esporta la trascrizione di una sessione come HTML autonomo ===
# Legge il transcript JSONL di Claude Code (per-progetto, cwd sempre /workspace
# in questo container ⇒ percorso stabile), lo incapsula base64 in uno
# <script type="application/json"> (inerte, non eseguito) e lo rende con un
# piccolo viewer JS che scrive via textContent — mai innerHTML — così nessun
# contenuto della conversazione può iniettare markup nella pagina.
# args: n sid status started ended outfile
render_transcript(){
  local n="$1" sid="$2" status="$3" started="$4" ended="$5" outfile="$6"
  local jsonl="$HOME/.claude/projects/-workspace/${sid}.jsonl"
  # Il blob base64 può superare facilmente i ~128KB per singolo argomento argv
  # (MAX_ARG_STRLEN su Linux, indipendente dall'ARG_MAX totale) — passarlo con
  # `jq --arg` fallisce con "Argument list too long" su transcript non banali.
  # `--rawfile` legge da file, bypassando il limite di argv.
  local b64file; b64file="$(mktemp)"
  [[ -f "$jsonl" ]] && base64 -w0 "$jsonl" > "$b64file"
  local data_json
  data_json=$(jq -n \
    --arg ticket "$n" --arg title "${TITLE[$n]:-}" --arg sid "$sid" \
    --arg status "$status" --arg started "$started" --arg ended "$ended" \
    --arg branch "$TARGET_BRANCH" --rawfile jsonlB64 "$b64file" \
    '{ticket:$ticket,title:$title,sid:$sid,status:$status,started:$started,ended:$ended,branch:$branch,jsonlB64:$jsonlB64}')
  rm -f "$b64file"
  # Un '</script' letterale nei dati (es. dentro un titolo issue) chiuderebbe
  # il tag anche dentro una stringa JSON valida — il parser HTML non guarda il
  # JSON. < resta valido JSON e neutralizza il rischio ovunque compaia '<'.
  data_json="${data_json//</\\u003c}"

  { cat <<'HTMLHEAD'
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ticket transcript</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: ui-sans-serif, system-ui, sans-serif; max-width: 880px; margin: 0 auto; padding: 24px 16px 80px;
         background: Canvas; color: CanvasText; line-height: 1.5; }
  header { border-bottom: 1px solid color-mix(in srgb, CanvasText 20%, transparent); padding-bottom: 12px; margin-bottom: 20px; }
  header h1 { font-size: 1.2rem; margin: 0 0 4px; }
  header .meta { font-size: 0.85rem; opacity: 0.7; display: flex; gap: 14px; flex-wrap: wrap; }
  .status-ok { color: #16a34a; } .status-failed { color: #dc2626; } .status-running { color: #d97706; }
  #filter { width: 100%; box-sizing: border-box; padding: 8px 10px; margin-bottom: 16px; font-size: 0.9rem;
            border-radius: 6px; border: 1px solid color-mix(in srgb, CanvasText 25%, transparent); background: Canvas; color: CanvasText; }
  .turn { border-radius: 10px; padding: 12px 14px; margin-bottom: 10px; border: 1px solid color-mix(in srgb, CanvasText 12%, transparent); }
  .turn.user { background: color-mix(in srgb, #3b82f6 8%, Canvas); }
  .turn.assistant { background: color-mix(in srgb, #8b5cf6 6%, Canvas); }
  .turn.system, .turn.unknown { background: color-mix(in srgb, CanvasText 4%, Canvas); font-size: 0.85rem; opacity: 0.85; }
  .role { font-weight: 600; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; opacity: 0.6; margin-bottom: 6px; }
  .block { margin: 6px 0; }
  .block pre { white-space: pre-wrap; word-break: break-word; margin: 4px 0; font-size: 0.85rem;
               background: color-mix(in srgb, CanvasText 6%, transparent); padding: 8px 10px; border-radius: 6px; overflow-x: auto; }
  .tag { display: inline-block; font-size: 0.7rem; font-weight: 600; padding: 1px 6px; border-radius: 4px; margin-right: 6px;
         background: color-mix(in srgb, CanvasText 10%, transparent); }
  details > summary { cursor: pointer; font-size: 0.8rem; opacity: 0.75; }
  details[open] > summary { margin-bottom: 4px; }
  .empty { opacity: 0.6; font-style: italic; }
</style>
</head><body>
<header>
  <h1 id="hdr-title"></h1>
  <div class="meta">
    <span id="hdr-status"></span>
    <span id="hdr-sid"></span>
    <span id="hdr-branch"></span>
    <span id="hdr-time"></span>
  </div>
</header>
<input id="filter" type="search" placeholder="Filter turns (text search)…">
<div id="turns"></div>
HTMLHEAD
    printf '<script id="ticket-data" type="application/json">%s</script>\n' "$data_json"
    cat <<'HTMLTAIL'
<script>
(function(){
  const data = JSON.parse(document.getElementById('ticket-data').textContent);
  document.getElementById('hdr-title').textContent = 'Ticket #' + data.ticket + (data.title ? ' — ' + data.title : '');
  const statusEl = document.getElementById('hdr-status');
  statusEl.textContent = 'status: ' + data.status;
  statusEl.className = 'status-' + data.status;
  document.getElementById('hdr-sid').textContent = 'session: ' + data.sid;
  document.getElementById('hdr-branch').textContent = 'branch: ' + data.branch;
  document.getElementById('hdr-time').textContent = data.started + (data.ended ? ' → ' + data.ended : ' (in progress)');

  const turnsEl = document.getElementById('turns');

  function el(tag, opts, children){
    const n = document.createElement(tag);
    opts = opts || {};
    if (opts.class) n.className = opts.class;
    if (opts.text !== undefined) n.textContent = opts.text;
    (children || []).forEach(c => c && n.appendChild(c));
    return n;
  }
  function pre(text){ return el('pre', {text: typeof text === 'string' ? text : JSON.stringify(text, null, 2)}); }
  function collapsible(summary, bodyNode){
    const d = document.createElement('details');
    d.appendChild(el('summary', {text: summary}));
    d.appendChild(bodyNode);
    return d;
  }

  function renderContentItem(item){
    if (item == null) return null;
    if (typeof item === 'string') return el('div', {class:'block'}, [pre(item)]);
    if (item.type === 'text') return el('div', {class:'block'}, [pre(item.text || '')]);
    if (item.type === 'thinking') return collapsible('thinking', pre(item.thinking || ''));
    if (item.type === 'tool_use') {
      const label = 'tool_use: ' + (item.name || '?');
      return el('div', {class:'block'}, [
        el('span', {class:'tag', text: label}),
        collapsible('input', pre(item.input))
      ]);
    }
    if (item.type === 'tool_result') {
      let body = item.content;
      if (Array.isArray(body)) body = body.map(c => (c && c.text) ? c.text : c).join('\n');
      const str = typeof body === 'string' ? body : JSON.stringify(body, null, 2);
      const wrap = el('div', {class:'block'});
      wrap.appendChild(el('span', {class:'tag', text: 'tool_result' + (item.is_error ? ' (error)' : '')}));
      if (str.length > 600) {
        wrap.appendChild(collapsible('show ' + str.length + ' chars', pre(str)));
      } else {
        wrap.appendChild(pre(str));
      }
      return wrap;
    }
    return el('div', {class:'block'}, [pre(item)]);
  }

  function renderLine(line){
    const role = (line.message && line.message.role) || line.type || 'unknown';
    const wrap = el('div', {class: 'turn ' + role});
    wrap.appendChild(el('div', {class:'role', text: role}));
    const content = line.message && line.message.content;
    if (typeof content === 'string') {
      wrap.appendChild(pre(content));
    } else if (Array.isArray(content)) {
      content.forEach(item => { const n = renderContentItem(item); if (n) wrap.appendChild(n); });
    } else if (line.type === 'result' || line.type === 'system') {
      wrap.appendChild(collapsible('meta', pre(line)));
    } else {
      wrap.appendChild(pre(line));
    }
    return wrap;
  }

  let lines = [];
  if (data.jsonlB64) {
    try {
      const raw = atob(data.jsonlB64);
      lines = raw.split('\n').filter(Boolean).map(l => { try { return JSON.parse(l); } catch(e){ return {type:'unparsed', raw:l}; } });
    } catch (e) {
      turnsEl.appendChild(el('p', {class:'empty', text: 'Could not decode transcript: ' + e}));
    }
  }
  if (!lines.length) {
    turnsEl.appendChild(el('p', {class:'empty', text: 'No transcript available for this ticket.'}));
  }
  const nodes = lines.map(renderLine);
  nodes.forEach(n => turnsEl.appendChild(n));

  document.getElementById('filter').addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase();
    nodes.forEach(n => { n.style.display = (!q || n.textContent.toLowerCase().includes(q)) ? '' : 'none'; });
  });
})();
</script>
</body></html>
HTMLTAIL
  } > "$outfile"
}

# === Helper: esegue un ticket — sessione nuova o resume della stessa esistente
# — e ne registra lo stato. Usata sia dal loop principale (sessione nuova) sia
# dalla modalità --retry (stesso session_id, via `claude -p --resume`: headless
# esattamente come una sessione nuova, nessuna TUI si apre).
# args: n sid prompt is_resume(0|1) turns_budget
run_ticket(){
  local n="$1" sid="$2" prompt="$3" is_resume="$4" turns_budget="$5"
  local started jf
  started=$(now); jf="$RUN_DIR/ticket-$n.json"
  write_state "$n" "$sid" running "$started" "" null null "$jf"; render_summary

  local -a id_flags
  if ((is_resume)); then id_flags=(--resume "$sid"); else id_flags=(--session-id "$sid"); fi

  monitor_ticket "$n" "$sid" "$turns_budget" &
  local monitor_pid=$!

  if claude -p "$prompt" \
        "${id_flags[@]}" --max-turns "$turns_budget" --dangerously-skip-permissions \
        --output-format json > "$jf" 2> "$RUN_DIR/ticket-$n.err.log"
  then
    { kill "$monitor_pid"; wait "$monitor_pid"; } 2>/dev/null || true
    echo >&2
    local ended turns cost rsid html
    ended=$(now)
    turns=$(jq -r '.num_turns // empty' "$jf" 2>/dev/null); turns=${turns:-null}
    cost=$(jq -r '(.total_cost_usd // .cost_usd) // empty' "$jf" 2>/dev/null); cost=${cost:-null}
    rsid=$(jq -r '.session_id // empty' "$jf" 2>/dev/null); sid=${rsid:-$sid}
    html="$RUN_DIR/ticket-$n.html"; render_transcript "$n" "$sid" ok "$started" "$ended" "$html"
    write_state "$n" "$sid" ok "$started" "$ended" "$turns" "$cost" "$jf" "$html"; render_summary
    gh issue edit "$n" --remove-label "$LABEL_TODO" --add-label "$LABEL_DONE" \
      || echo "WARN: label non aggiornata per #$n — lo stato 'ok' evita comunque il re-run." >&2
    return 0
  else
    { kill "$monitor_pid"; wait "$monitor_pid"; } 2>/dev/null || true
    echo >&2
    local ended html
    ended=$(now)
    html="$RUN_DIR/ticket-$n.html"; render_transcript "$n" "$sid" failed "$started" "$ended" "$html"
    write_state "$n" "$sid" failed "$started" "$ended" null null "$jf" "$html"; render_summary
    echo "STOP: #$n fallito." >&2
    echo "  session id: $sid" >&2
    echo "  riprova (stessa sessione, headless): ./retry.sh $n [max-turns]" >&2
    echo "  oppure apri in interattivo:          ./manual-resume.sh $n" >&2
    echo "  log: $RUN_DIR/ticket-$n.err.log" >&2
    echo "  transcript: $html" >&2
    return 1
  fi
}

# === Helper: contatori live su UNA riga, aggiornata in-place (\r), mentre un
# ticket è in corso — nessun costo in $ mostrato: nello stream della sessione
# non c'è un prezzo per-turno affidabile (solo il costo finale aggregato, che
# arriva già a fine ticket in SUMMARY.md), i token invece sono conteggi esatti
# via .message.usage di ogni turno assistant nel .jsonl — lo stesso file che
# render_transcript legge a fine ticket, qui letto man mano che cresce.
# Gira in background, viene uccisa da run_ticket appena claude -p finisce.
# "risposte modello" (non "turni"): il conteggio grezzo dei messaggi assistant
# nel .jsonl NON è la stessa unità di --max-turns/num_turns — verificato su un
# ticket reale mai risumato: 117 messaggi assistant grezzi contro un num_turns
# finale di 8. Testate anche isSidechain, parentUuid, stop_reason, presenza di
# blocchi text, requestId: nessuna di queste chiavi nel .jsonl ricostruisce il
# vero conteggio — è un contatore interno della CLI, non derivabile dal
# transcript. Quindi nessun confronto con MAX_TURNS qui: solo un indicatore
# di attività, onestamente etichettato per quello che è davvero.
# args: n sid turns_budget (non usato nel display, vedi sopra — tenuto per
# eventuale uso futuro, coerente con la firma di run_ticket)
monitor_ticket(){
  local n="$1" sid="$2" turns_budget="$3"
  local jsonl="$HOME/.claude/projects/-workspace/${sid}.jsonl"
  local t0; t0=$(date +%s)
  while :; do
    if [[ -s "$jsonl" ]]; then
      local stats resp tools tin tcache tout err
      stats=$(jq -s -r '
        [.[] | select(.type=="assistant")] as $a
        | { resp: ($a|length),
            tools: ([$a[].message.content[]? | select(.type=="tool_use")] | length),
            tin:   ([$a[].message.usage.input_tokens // 0] | add // 0),
            tcache:([$a[].message.usage.cache_read_input_tokens // 0] | add // 0),
            tout:  ([$a[].message.usage.output_tokens // 0] | add // 0),
            err:   ($a | any(.isApiErrorMessage==true))
          }
        | "\(.resp)\t\(.tools)\t\(.tin)\t\(.tcache)\t\(.tout)\t\(.err)"
      ' "$jsonl" 2>/dev/null || true)
      if [[ -n "$stats" ]]; then
        IFS=$'\t' read -r resp tools tin tcache tout err <<<"$stats"
        local el=$(( $(date +%s) - t0 ))
        local warn=""; [[ "$err" == "true" ]] && warn=" | ⚠ errore trasporto rilevato"
        printf '\r  #%s — %02d:%02d:%02d | risposte modello %s | tool %s | tok in %s cache %s out %s%s\033[K' \
          "$n" $((el/3600)) $((el%3600/60)) $((el%60)) \
          "$resp" "$tools" "$tin" "$tcache" "$tout" "$warn" >&2
      fi
    fi
    sleep 2
  done
}

declare -A BLOCKERS PENDING TITLE PARENTS

# === Helper: decide se un ticket è riprendibile o va (ri)partito da zero ===
# Riprende SOLO se lo stato ha un session_id E la sua trascrizione esiste
# davvero su disco e non è vuota. Uno stato "running"/"failed" con un
# session_id ma senza trascrizione capita con un kill abbastanza precoce
# (es. manuale, o connessione persa prima che claude scrivesse qualunque
# cosa): in quel caso non c'è nulla da riprendere, va trattato come se il
# ticket non fosse mai stato tentato — non un errore, un fallback silenzioso.
# Imposta RESOLVED_SID e RESOLVED_IS_RESUME (0|1) invece di fare `echo` +
# command substitution, per evitare di dover fare parsing di output composito.
resolve_session(){
  local n="$1" prev_sid=""
  [[ -f "$STATE_DIR/issue-$n.json" ]] && prev_sid=$(jq -r '.session_id // empty' "$STATE_DIR/issue-$n.json")
  if [[ -n "$prev_sid" ]] && [[ -s "$HOME/.claude/projects/-workspace/${prev_sid}.jsonl" ]]; then
    RESOLVED_SID="$prev_sid"; RESOLVED_IS_RESUME=1
  else
    RESOLVED_SID="$(uuidgen)"; RESOLVED_IS_RESUME=0
  fi
}

continue_prompt(){
  echo "La sessione precedente per la issue #$1 si è interrotta prima di completare il lavoro. Continua da dove eri rimasto e completa l'implementazione. Committa sul branch corrente usando 'Refs #$1' (NON 'Closes'/'Fixes'). Non chiudere nessuna issue."
}
fresh_prompt(){
  echo "/implement issue #$1. Committa sul branch corrente usando 'Refs #$1' (NON 'Closes'/'Fixes'). Non chiudere nessuna issue."
}

# === Modalità retry: continua UN ticket già fallito, senza ricalcolare
# coda/ordine — invocata da retry.sh come `loop.sh --retry <n> [max-turns]`.
# Il ticket è per definizione già stato scelto in una run precedente, quindi
# non serve rifare collect+topo-sort.
if [[ "${1:-}" == "--retry" ]]; then
  n="${2:?uso: loop.sh --retry <numero-issue> [max-turns]}"
  turns_budget="${3:-$MAX_TURNS}"
  state_file="$STATE_DIR/issue-$n.json"
  [[ -f "$state_file" ]] || { echo "ERRORE: nessuno stato per #$n in $state_file — non è mai stato tentato da questo loop." >&2; exit 1; }
  TITLE[$n]=$(jq -r '.title // ""' "$state_file")
  resolve_session "$n"
  if ((RESOLVED_IS_RESUME)); then
    echo "=== Retry #$n — riprendo la sessione $RESOLVED_SID, max-turns=$turns_budget ==="
    run_ticket "$n" "$RESOLVED_SID" "$(continue_prompt "$n")" 1 "$turns_budget"
  else
    echo "=== Retry #$n — nessuna trascrizione recuperabile per la sessione precedente, riparto da zero (sessione $RESOLVED_SID), max-turns=$turns_budget ===" >&2
    run_ticket "$n" "$RESOLVED_SID" "$(fresh_prompt "$n")" 0 "$turns_budget"
  fi
  exit $?
fi

# === Raccogli i ticket (numero, titolo, blocker) ===
todo=()
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  TITLE[$num]=$(jq -r '.title // ""' <<<"$row")
  body=$(jq -r '.body // ""' <<<"$row")

  # PARENT FILTER — convenzione to-tickets: ogni ticket figlio dichiara
  # "## Parent" col numero dello spec/contenitore da cui viene; to-tickets
  # stesso non applica MAI la label $LABEL_TODO al parent ("Do NOT close or
  # modify any parent issue"). Se il parent la porta comunque (errore di
  # triage), senza blocker propri finirebbe comunque in cima all'ordine
  # topologico e verrebbe "implementato" per sbaglio — quindi lo si esclude
  # qui in base al riferimento strutturale, non fidandosi solo della label.
  parent_section=$(awk '/^## Parent/{f=1;next} f&&/^##/{exit} f' <<<"$body")
  # `|| true`: grep esce 1 quando non trova nessun "#N" (il caso NORMALE per
  # il parent/spec stesso, o per qualunque ticket senza sezione "## Parent")
  # — sotto `set -euo pipefail` quello stato non-zero, propagato dalla pipe
  # fino all'assegnazione con $(...), terminava l'intero script silenziosamente
  # non appena si incontrava il primo ticket senza Parent (osservato: il loop
  # si fermava sempre subito dopo il branch switch, appena raggiungeva #17).
  parent_num=$(grep -oE '#[0-9]+' <<<"$parent_section" | tr -d '#' | head -1 || true)
  [[ -n "$parent_num" ]] && PARENTS[$parent_num]=1

  # BLOCKER PARSE — formato testuale "Blocked by:" (default di to-tickets).
  # Per sub-issue/dependency native di GitHub vedi references/blocker-formats.md.
  # Ferma alla prossima heading "##", non alla prossima riga vuota — il
  # template to-tickets mette sempre una riga vuota tra la heading e il
  # contenuto ("## Blocked by\n\n- #21..."), quindi fermarsi alla prima riga
  # vuota tronca prima ancora di leggere il contenuto. La heading reale del
  # template non ha i due punti ("## Blocked by", non "## Blocked by:") — il
  # colon nel pattern sotto è tollerato ma non richiesto. Verificato contro
  # un ticket to-tickets reale: il pattern precedente restituiva sempre vuoto.
  blk_section=$(awk '/^## *[Bb]locked [Bb]y/{f=1;next} f&&/^##/{exit} f' <<<"$body")
  blk=$(grep -oE '#[0-9]+' <<<"$blk_section" | tr -d '#' | sort -u | tr '\n' ' ')
  BLOCKERS[$num]="$blk"; PENDING[$num]=1; todo+=("$num")
done < <(gh issue list --state open --label "$LABEL_TODO" --json number,title,body | jq -c '.[]')

# Applica il filtro: rimuovi dalla coda ogni ticket che è il Parent di almeno
# un altro ticket in questo batch.
filtered_todo=()
for n in "${todo[@]}"; do
  if [[ -n "${PARENTS[$n]:-}" ]]; then
    echo "Escludo #$n dalla coda: è la issue Parent di altri ticket in questo batch (label '$LABEL_TODO' probabilmente applicata per errore di triage)." >&2
    unset "PENDING[$n]"
  else
    filtered_todo+=("$n")
  fi
done
todo=("${filtered_todo[@]}")

((${#todo[@]})) || { echo "Nessun ticket con label '$LABEL_TODO'."; exit 0; }

# === Ordinamento topologico (Kahn) — lavora la frontiera ===
order=(); progress=1
while ((${#PENDING[@]})) && ((progress)); do
  progress=0
  for n in "${todo[@]}"; do
    [[ -n "${PENDING[$n]:-}" ]] || continue
    ready=1
    for b in ${BLOCKERS[$n]:-}; do [[ -n "${PENDING[$b]:-}" ]] && { ready=0; break; }; done
    ((ready)) && { order+=("$n"); unset "PENDING[$n]"; progress=1; }
  done
done
((${#PENDING[@]})) && { echo "ERRORE: dipendenze irrisolvibili tra: ${!PENDING[*]}" >&2; exit 1; }
echo "Ordine di implementazione: ${order[*]}"

# === Implementa in ordine; stato live + flip label solo su successo ===
# Rilanciare run-batch.sh dopo un'interruzione (kill, connessione persa, crash
# del container) continua in autonomia: per ogni ticket non ancora "ok" si
# controlla se esiste una sessione precedente davvero riprendibile
# (resolve_session) e si usa quella invece di ripartire da zero — nessun
# argomento da passare, nessuno script diverso da lanciare.
for n in "${order[@]}"; do
  # Idempotenza: se già completata in un run precedente, salta.
  if [[ -f "$STATE_DIR/issue-$n.json" ]] && [[ "$(jq -r .status "$STATE_DIR/issue-$n.json")" == ok ]]; then
    echo "skip #$n (già ok)"; continue
  fi

  echo "=== Ticket #$n ==="
  resolve_session "$n"
  if ((RESOLVED_IS_RESUME)); then
    echo "  riprendo la sessione precedente: $RESOLVED_SID"
    run_ticket "$n" "$RESOLVED_SID" "$(continue_prompt "$n")" 1 "$MAX_TURNS" || exit 1
  else
    run_ticket "$n" "$RESOLVED_SID" "$(fresh_prompt "$n")" 0 "$MAX_TURNS" || exit 1
  fi
done

render_summary
echo "Completato. Branch: ${TARGET_BRANCH}."
echo "Indice: ${SUMMARY}  |  Stato per-issue: ${STATE_DIR}/"
