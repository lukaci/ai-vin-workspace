# Blocker formats

`to-tickets` records dependencies in one of two ways. The generated `loop.sh` must
parse whichever one this repo uses to build the topological order.

## 1. Textual `Blocked by:` (default)

`to-tickets`' own `<issue-template>` renders this as a heading, not an inline
line — always with a blank line between the heading and its content:

```
## Blocked by

- #21, #22 (every endpoint must have migrated to the new path first)
```
or `- None (can start immediately)`.

This is what the default block in `loop.sh` handles. It reads from the
`## Blocked by` heading to the *next heading* — not the next blank line, since
the template always has one right after the heading itself; stopping there
would truncate before ever reaching the content — and extracts every `#N`:

```bash
blk_section=$(awk '/^## *[Bb]locked [Bb]y/{f=1;next} f&&/^##/{exit} f' <<<"$body")
blk=$(grep -oE '#[0-9]+' <<<"$blk_section" | tr -d '#' | sort -u | tr '\n' ' ' || true)
```

Verified against a real `to-tickets`-generated issue with 6 blockers (an earlier
colon-requiring, stop-at-blank-line version of this pattern silently returned
empty on that same issue — the template's heading has no colon, so match it
loosely and don't trust blank lines as a section boundary). The trailing
`|| true` matters just as much as the parsing itself: `grep` exits 1 on no
match — the *normal* case for a ticket with no blockers (`- None`) — and under
`set -euo pipefail` that non-zero status, propagated through the pipe into the
`$(...)` assignment, silently kills the whole script the moment it reaches the
first such ticket. Same failure mode as the parent-filter bug below — caught
the same way, by actually running the real loop end-to-end against a real
batch that included an issue hitting the empty case, not by reasoning about it.

## 2. Native GitHub sub-issues / dependencies

If the repo uses GitHub's native "blocked by" issue relationships (rather than
text in the body), replace the marked BLOCKER PARSE block with a `gh api` query
against the same REST endpoint `to-tickets`/`/wayfinder` themselves write to when
creating the dependency edge (see the repo's own `issue-tracker.md`):

```bash
OWNER_REPO="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
# per ogni issue $num già raccolta:
blk=$(gh api "repos/${OWNER_REPO}/issues/${num}/dependencies/blocked_by" \
      --jq '.[].number' 2>/dev/null | sort -u | tr '\n' ' ')
BLOCKERS[$num]="$blk"
```

Verified working end-to-end (built the image, ran it as the real non-root
runtime user, confirmed correct blocker numbers against a live repo). No GraphQL
needed — this plain REST endpoint returns open blockers directly. Keep the rest
of the loop (Kahn ordering, state files, label flip) unchanged — only the source
of the blocker numbers changes.

## 3. Parent/spec issues aren't tickets — filter them regardless of format

`to-tickets` explicitly never labels the parent/spec issue itself
(`ready-for-agent`, per its own instructions, goes only on the generated child
tickets — "Do NOT close or modify any parent issue"), but a parent can still end
up carrying that label by triage mistake. Since a parent usually has no blockers
of its own, it would sort first in the topological order and get "implemented"
directly — wrong regardless of which blocker format is in use above, so this
filter runs unconditionally in `loop.sh`, independent of the BLOCKER PARSE
variant: collect every candidate's `## Parent` reference (same heading-to-next-
heading extraction as above) into a `PARENTS` set, then drop from the queue any
ticket whose own number appears in that set. Verified against a real batch: a
parent issue with 7 real children, incorrectly labeled `ready-for-agent`, was
correctly excluded while all 7 children were kept.

The extraction carries the identical `grep`-exits-1-on-no-match trap as §1's
`blk` line: `parent_num=$(grep -oE '#[0-9]+' <<<"$parent_section" | tr -d '#' |
head -1 || true)` — without the `|| true`, the parent/spec issue itself (which
by definition has no `## Parent` section to match) crashed the whole script via
`set -e` the moment the collection loop reached it. This is exactly what
happened in production: the loop looked like it hung right after the branch
switch, with zero further output — really it had already died, silently, on
the very first parentless issue it saw. Confirmed by re-running the exact
container with `bash -x`, not inferred from reading the code.
