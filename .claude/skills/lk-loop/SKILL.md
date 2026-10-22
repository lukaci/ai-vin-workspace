---
name: lk-loop
description: >-
  Generates (does NOT run) an automated batch-implementation loop for a repo that
  uses the mattpocock engineering skills. It writes a container plus shell scripts
  that implement every ready-for-agent ticket in dependency order on a single
  branch, advance each ticket to ready-for-human WITHOUT closing it, and record
  per-issue state files plus a resumable SUMMARY index (Claude session ids +
  resume commands). User-invoked ONLY — do not reach for this on your own. Use
  when the user explicitly asks to scaffold / set up / generate the batch
  /implement loop, the AFK ticket loop, or the "container implement loop".
---

# Scaffold implement-loop

This skill **writes** an automated batch-`/implement` loop as a folder *sibling*
to the current repo (outside its working tree, outside git entirely).
It does not execute anything — the user runs the generated `run-batch.sh`.

**User-invoked.** Reach for it only when the user explicitly asks to create/scaffold
the loop. Never trigger it automatically from words like "loop" or "implement".

## What it generates

A fresh folder **next to** the repo (same parent directory, not inside it):
`<repo-parent>/<repo-name>-lk-loop-<YYYY-MM-DD-HH-MM-SS>` (dash-separated, no
milliseconds, timestamped at scaffold time — never overwrites a previous
scaffold, so re-running the skill just adds another sibling folder). Being
outside the repo, none of it is git-tracked and no `.gitignore` edits are needed:

- `Dockerfile` — image with Claude Code + git + gh + jq (non-root at runtime),
  plus the target repo's JS runtime/package manager if it's not plain npm, and
  `graft` if the repo uses it (see step 4 — `{{RUNTIME_SETUP}}`,
  `{{GRAFT_SETUP}}`).
- `run-batch.sh` — host launcher: auto-inhibits host suspend for the run's
  whole duration (`systemd-inhibit --what=sleep:idle --mode=block`, re-execs
  itself once under it via `exec`, guarded by `LK_LOOP_INHIBITED` so it
  doesn't loop — released automatically on exit, success or failure; no-op if
  `systemd-inhibit` isn't present). Doesn't block screen dimming/DPMS, only
  actual sleep/idle-suspend — a suspend mid-run was observed to sever a
  ticket's Claude session outright (surfaced as "connection lost"), silently
  indistinguishable from a real failure. `retry.sh` does the same. One
  interactive token step, computes the target branch, runs the loop inside
  the container. Has the repo's absolute path baked
  in as `REPO_ROOT` at scaffold time; mounts the repo at `/workspace` and the
  scaffold folder itself at `/scaffold` — two separate volumes, since they're no
  longer nested. Caches both tokens in `.env` next to it (mode `600`, `%q`-quoted,
  outside the repo so no commit risk) after acquiring them — a retry skips the
  interactive Claude-token step entirely, though `GITHUB_TOKEN` is always
  re-verified via `gh auth token` regardless of the cache, never trusted blindly.
  Deleting `.env` forces the whole check to happen again from scratch. Nothing
  else needed to wire this into the container: the existing `-e
  CLAUDE_CODE_OAUTH_TOKEN -e GITHUB_TOKEN` docker flags already just read
  whatever's in the shell environment, cached or freshly acquired alike.
  `TARGET_BRANCH` is cached the same way, but conditionally: reused only if the
  repo is *currently checked out exactly on* the cached branch — otherwise a
  fresh `<current-branch>-implementation-<ts>` is computed as usual. Without
  this, every retry from inside an implementation branch stacked another
  `-implementation-<ts>` on top instead of continuing on it (observed: three
  stacked after three runs). To force a fresh branch while keeping the cached
  tokens, delete just the `TARGET_BRANCH` line from `.env`, or `git switch`
  away first. `ANTHROPIC_MODEL` (default `claude-sonnet-5`) and
  `CLAUDE_CODE_EFFORT_LEVEL` (default `medium`) are cached the same way too —
  edit either line directly in `.env` at any time to change model or
  reasoning effort, no script edits needed. Both are read natively by the
  `claude` CLI itself (confirmed in the binary: it falls back to `high`
  effort if the var is absent), so `run-batch.sh`/`manual-resume.sh`/`retry.sh`
  only need to `-e` them into the container — `loop.sh`'s `claude -p` call
  never needs a `--model`/`--effort` flag.
- `loop.sh` — in-container loop: topological order, clean context per ticket,
  state files, label state-flip. `write_state`'s `ended_at` field is built as
  `if $ended=="" then null else $ended end`, not `$ended|select(.!="")` — the
  `select` form looks equivalent but isn't: when a value-generator inside a jq
  object constructor yields zero outputs (exactly what `select` does on a
  non-match), the *whole object* yields zero outputs, not just that key. Since
  the very first `write_state` call per ticket (status `running`) always has
  an empty `$ended`, that early version silently wrote a 0-byte state file for
  the entire in-progress duration — valid JSON only appeared once the ticket
  finished and `$ended` was real. Never noticed before `stream.sh` needed to
  read a ticket's `session_id` *while it was still running*; reproduced and
  confirmed live against a real in-flight ticket, not just reasoned about.
  Logs/state live at `/scaffold/.loop-logs`. After
  every ticket — success or failure — decodes that session's Claude Code JSONL
  transcript and writes a self-contained `logs/ticket-<n>.html` viewer (data in a
  `<script type="application/json">` tag, rendered via a small vanilla-JS script
  that writes with `textContent`, never `innerHTML`, so transcript content can't
  inject markup). Linked from `SUMMARY.md`'s table. The base64 blob is written to
  a temp file and passed to `jq` via `--rawfile`, not `--arg` — a real transcript's
  base64 routinely exceeds Linux's ~128KB single-argv-string limit.
  Re-launching `run-batch.sh` after any interruption (host suspend despite the
  inhibitor, container killed, `docker` crash) continues on its own, no
  argument needed: for each not-yet-`ok` ticket, `resolve_session()` checks
  whether a prior attempt's session is genuinely resumable — a `session_id`
  recorded AND that session's own JSONL transcript actually present and
  non-empty on disk (`$HOME/.claude/projects/-workspace/<sid>.jsonl`, same
  path `render_transcript` reads) — and if so resumes it via `claude -p
  --resume` with a continuation prompt instead of starting fresh. A `status`
  of `running`/`failed` with a `session_id` but *no* matching transcript (an
  early-enough kill — e.g. manual, or the connection drop this was built to
  survive — can leave exactly that) falls back to a fresh session rather than
  attempting a resume with nothing to resume, treating it as never-attempted.
  `loop.sh --retry <n> [max-turns]` (invoked by `retry.sh`) shares this exact
  same `resolve_session` — same fallback, not a separate code path.
  While a ticket runs, a background `monitor_ticket` job updates one status
  line in-place (`\r`, no scrolling) under the `=== Ticket #n ===` line:
  model-response count, tool-call count, and cumulative input/cache-read/
  output tokens — all exact counts pulled straight from that ticket's own
  growing JSONL (`.message.usage` per assistant message), no separate
  accounting. Deliberately *not* labeled "turns" and not shown against
  `MAX_TURNS`: raw assistant-message count in the JSONL isn't the same unit
  as `--max-turns`/`num_turns` — verified on a real, never-resumed ticket
  (117 raw assistant messages, `num_turns:8` in the final state). Tried
  `isSidechain`, `parentUuid`, `stop_reason`, presence of a `text` block, and
  distinct `requestId` as possible groupings that might reconstruct the real
  count — none of them did; whatever "turn" means internally isn't derivable
  from the transcript, so don't claim it. No live `$` figure either: the
  stream carries no reliable per-turn price, only token counts; the real
  cost still lands in `SUMMARY.md`/the state file once the ticket finishes,
  same as before. If the last-seen assistant turn has
  `isApiErrorMessage`/`error` set, the line grows a `⚠ errore trasporto
  rilevato` marker — this is what a transport drop (e.g. host suspend cutting
  the connection) looks like from inside the transcript, confirmed against
  the real failed-#24 session this was built to surface. The monitor is
  killed the moment `claude -p` returns, success or failure, so it never
  outlives the ticket it's watching.
- `stream.sh <n> [--all]` — tails one ticket's live conversation in the
  terminal, given only the issue number: reads its `session_id` from
  `.loop-logs/state/issue-<n>.json`, then `tail -F` (follow-by-name, waits for
  the file if it doesn't exist yet) on that session's own JSONL. Runs entirely
  on the HOST, no docker involved — the file's already there via the
  `.claude-home` bind mount, same one `render_transcript`/`monitor_ticket`
  read. Formats each `user`/`assistant` line (role, timestamp, truncated
  text/thinking/tool_use/tool_result) instead of dumping raw JSON; `attachment`
  rows (hook output, internal telemetry — routinely *more than half* the
  lines in a real transcript) are hidden by default, `--all` shows them too.
- `retry.sh` — re-attempts ONE already-failed ticket, headless and scripted,
  the same way `run-batch.sh` runs a fresh one: `./retry.sh <n> [max-turns]`.
  Internally calls `loop.sh --retry <n> [max-turns]`, which resumes the
  ticket's *existing* Claude session — `claude -p --resume "$sid" ...` — so
  it continues the exact conversation (full prior context) rather than
  starting over, but stays fully headless: `-p` plus `--resume` never opens
  the TUI, it's the identical machinery as a fresh ticket (state file, HTML
  transcript, label flip on success, same `--dangerously-skip-permissions`).
  `max-turns` is optional and per-invocation, not cumulative with turns the
  original session already used — defaults to `loop.sh`'s own `MAX_TURNS` if
  omitted. Requires `TARGET_BRANCH` already cached in `.env` (errors out
  otherwise) — a retry continues the same shared branch, it never computes a
  new one. Reuses `run-batch.sh`'s exact token-acquire/cache block, so it also
  works standalone in a brand new shell.
- `manual-resume.sh` — reopens a ticket's Claude session *interactively* (TUI),
  for manual inspection/steering rather than a scripted retry; same
  two-volume mount as `run-batch.sh`. Shares the exact same `.env`
  load/acquire/cache block as `run-batch.sh` (deliberately identical, not just
  similar) — a resume in a brand new shell, with no prior `run-batch.sh` run,
  still works: it prompts for the Claude token itself and caches it, preserving
  any `GITHUB_TOKEN` and `TARGET_BRANCH` already in the file rather than
  overwriting them, since `manual-resume.sh` doesn't use or compute those
  itself — it only fills in `ANTHROPIC_MODEL`/`CLAUDE_CODE_EFFORT_LEVEL` with
  the same defaults as `run-batch.sh` if they're still unset.

## Guardrails baked into the output — never drop these

- One target branch per scaffold folder, not per invocation: first run creates
  `<current-branch>-implementation-<YYYYMMDD-HHMMSS>`; every retry while still
  checked out on it reuses the same branch (cached in `.env`) instead of
  stacking another `-implementation-<ts>` on top. All tickets accumulate there
  (dependencies need shared filesystem state) — `loop.sh`'s `git switch`
  creates the branch only if it doesn't already exist, for the same reason.
- Clean context per ticket: one `claude -p` process each (fresh conversation),
  shared working tree.
- Topological order over the tickets' blocking edges; work the frontier; **stop on
  first failure** (shared branch ⇒ failures cascade).
- Filter out parent/spec issues before ordering — see `blocker-formats.md` §3.
  `to-tickets` never labels the parent itself, but triage can mislabel it by
  mistake, and an unblocked parent would otherwise sort first and get
  "implemented" directly. This runs independent of which BLOCKER PARSE variant
  is active.
- Advance state instead of closing: `LABEL_TODO → LABEL_DONE`. Never emit
  `Closes/Fixes #N` in commits — use `Refs #N`. Never close issues.
- `--dangerously-skip-permissions` only inside the container, as a non-root user.
- Per-issue state JSON + `SUMMARY.md` are the source of truth for idempotency and
  for resuming sessions; the label flip is best-effort.

## Procedure

### 1. Check preconditions
- The repo must be configured by `/setup-matt-pocock-skills`: expect
  `docs/agents/issue-tracker.md`. If missing, tell the user to run
  `/setup-matt-pocock-skills` first, then stop.
- The tracker must be GitHub (this scaffolder targets `gh`). If
  `issue-tracker.md` says Linear / local-markdown / other, say so and stop — this
  loop is GitHub-specific.
- A container runtime (docker or podman) must be available on the host.

### 2. Resolve the real label strings
If `docs/agents/triage-labels.md` exists, read it and map the canonical roles to
the repo's actual label strings. Otherwise fall back to the canonical names
directly — no file with "triage" in its name is required:
- `ready-for-agent` → `LABEL_TODO`
- `ready-for-human` → `LABEL_DONE`
Cross-check both against `gh label list`. If either is missing on the repo,
create it silently — `gh label create <name> --description "..." --color "..."` —
no confirmation prompt; just note the resolved/created strings to the user as an
informational line before writing the files.

### 3. Detect the blocker format
Fetch one candidate ticket body: `gh issue view <n> --json body`. If it contains a
textual `Blocked by:` section, keep the default parser in `loop.sh`. If the repo
uses GitHub's **native** sub-issue / dependency relationships instead, read
`blocker-formats.md` and replace the marked BLOCKER PARSE block with the
`gh`-based variant. If it's ambiguous, ask the user.

### 4. Pick parameters (with sensible defaults)
- `MAX_TURNS` (default `120`).
- Model / effort level: default `claude-sonnet-5` / `medium` — cached in
  `.env` by `run-batch.sh` on first run (see "What it generates" above), not
  baked into any script, so the user can retune either one after scaffolding
  by editing `.env` directly.
- Container runtime: `docker` (default) or `podman` — if podman, replace `docker`
  with `podman` in `run-batch.sh`, `retry.sh`, and `manual-resume.sh`
  (CLI-compatible).
- Optionally add `--max-budget-usd <n>` to the `claude` call for a spend cap.
- **Detect the target's JS runtime/package manager** and resolve
  `{{RUNTIME_SETUP}}` in `Dockerfile`. Check `package.json`'s `packageManager`
  field, lockfiles (`bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`), and `scripts`
  values. If it's plain npm, the base `node` image already has it — delete the
  `{{RUNTIME_SETUP}}` line entirely. Otherwise install the right one, e.g. for
  bun: `RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash`
  (`BUN_INSTALL=/usr/local` puts the binary on `/usr/local/bin`, in `PATH` for
  every user regardless of `$HOME` — at runtime `$HOME` is the scaffold's
  `.claude-home`, not the build user's home, so the installer's default
  `$HOME/.bun` location wouldn't be found). Skipping this isn't just slower: a
  missing runtime gets rediscovered and reinstalled from scratch by *every
  ticket's* session (turns burned on environment archaeology, not the ticket),
  and can cascade into worse workarounds — observed once where the official
  bun installer's `unzip` step silently had nothing to unzip with (missing from
  the base image) and the agent burned several tool calls writing a Node script
  with `adm-zip` to manually decompress the release tarball instead.
- **Detect graft** and resolve `{{GRAFT_SETUP}}` in `Dockerfile`. Check for a
  `graft` entry in `.mcp.json`'s `mcpServers`, or a `.claude/skills/graft/`
  directory. If present, pin the exact version already used to build the
  repo's `graft/` cache — `npm ls -g @nanonets/graft --depth=0 --json` on the
  host — and add `RUN npm install -g @nanonets/graft@<that-version>` (pinning,
  not `@latest`, keeps the container's CLI consistent with whatever built the
  existing on-disk graph; the graft skill's own instructions say every graft
  command refreshes the graph before answering, so a version mismatch would
  show up as unnecessary full rebuilds rather than wrong answers, but pinning
  avoids the question). If graft isn't in use, delete the `{{GRAFT_SETUP}}`
  line entirely. Skipping this when graft *is* in use breaks two things at
  once, both silently: `mcp__graft__*` tools plus `graft` CLI calls just fail
  ("command not found"), and — because `.claude/helpers/graft-hooks.cjs`
  resolves the package via `npm root -g` as one of its fallback candidates —
  the PostToolUse/UserPromptSubmit/SessionStart/Stop hooks that keep the graph
  updated as code changes silently no-op instead of erroring. Net effect:
  every ticket burns turns rediscovering that graft is unavailable and falls
  back to raw `grep`/`Read` — exactly the token cost the graph exists to avoid.

### 5. Write the files
Let `REPO_ROOT` = the repo's absolute path (`git rev-parse --show-toplevel`) and
`REPO_NAME` = its directory basename. Compute
`SCAFFOLD_DIR = <parent-of-REPO_ROOT>/<REPO_NAME>-lk-loop-<timestamp>`, timestamp
via `date +%Y-%m-%d-%H-%M-%S` (dash-separated, no milliseconds). Create it as a
**sibling** of the repo, not inside it, and copy the bundled assets into it,
substituting placeholders:
- `loop.sh`: `{{LABEL_TODO}}`, `{{LABEL_DONE}}`, `{{MAX_TURNS}}`.
- `run-batch.sh`, `retry.sh`, and `manual-resume.sh`: `{{REPO_ROOT}}` (the
  absolute path, baked in — these scripts live outside the repo so they can't
  `git rev-parse` their way to it).
- `Dockerfile`: `{{RUNTIME_SETUP}}` and `{{GRAFT_SETUP}}` per step 4 — each
  either a real `RUN` line or deleted entirely if not applicable.
Apply the podman swap in `run-batch.sh`/`retry.sh`/`manual-resume.sh` if
chosen. No `.gitignore` changes — the folder is outside the repo already.

### 6. Do NOT run anything. Print next steps
```
cd <repo-parent>/<repo-name>-lk-loop-<timestamp>
chmod +x run-batch.sh retry.sh manual-resume.sh stream.sh
./run-batch.sh
```
Remind the user:
- The first run has one interactive step (`claude setup-token` → paste token).
  Exporting `CLAUDE_CODE_OAUTH_TOKEN` in the shell makes later runs non-interactive.
- **Verify billing on a single ticket first**: `claude -p` with an OAuth
  subscription token can draw API credits — check `cost_usd` in the first
  `.loop-logs/state/issue-*.json` before running the whole batch.
- While a ticket runs, a single in-place status line shows model-responses/
  tool-calls/tokens live; `./stream.sh <n>` (a second terminal, host-side, no
  docker) tails
  the actual conversation for that ticket if you want to watch it happen.
- After a run, `.loop-logs/SUMMARY.md` (inside the scaffold folder) lists every
  issue with its status, Claude session id, and two ready commands per row: a
  scripted `./retry.sh <n> [max-turns]` (headless, same session, picks up
  where it stopped — the normal path after a failure) and an interactive
  `./manual-resume.sh <n>` (opens the TUI, for when you actually want to
  steer or inspect it by hand) — no log-grepping needed either way.

## Bundled resources
- `Dockerfile`, `run-batch.sh`, `loop.sh`, `retry.sh`, `manual-resume.sh`,
  `stream.sh` — copied verbatim (with placeholder substitution where
  applicable — `stream.sh` needs none, it never touches the repo or docker)
  into the generated sibling scaffold folder.
- `blocker-formats.md` — textual vs native GitHub blocker parsing.
