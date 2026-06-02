# Findings from building `chat` — all resolved

This document started as a full record of everything wrong, missing, surprising,
or delightful while building the distributed-node chat REPL in `src/chat.blsp`
(an LLM, Claude, writing Brood for the first time against the live image via
`nest mcp`). **Every finding it surfaced has since been addressed upstream** —
there are no outstanding items.

For the resolved items, see this file's git history and the upstream
`docs/devlog.md`:

| # | Finding | Resolution |
|---|---------|------------|
| §1.1 | `nest run --main` silently ignored | `*project-main-override*` slot preferred over the manifest; `run_main.rs` test |
| §1.2 | clean disconnect not detected | `drop_link`-on-EOF fires `[:nodedown]` before the heartbeat window; repro at [`repro/run.sh`](../repro/run.sh) |
| §1.3 | misleading scheduler-race hint on a cross-node unbound | hint gated to bare names (`!name.contains('/')`) |
| §2.1 | "functions can't be sent" (false) | `brood-for-claude.md` now documents sendable closures + late-bound free globals |
| §2.2 | implicit-`do` bodies undocumented | one line added to *Defining things* |
| §3.1 | `substring` had no 2-arg form | optional `end`, defaults to `(string-length s)` |
| §3.2 | no line editor in the stdlib | `std/lineedit` ships — `(require 'lineedit)` → `lineedit-read` |
| §3.3 | `doc-search` under-delivered | tokenized, ranked name+doc matching |
| §3.4 | cross-node addressing scattered | "Distributed nodes — named processes & cross-node addressing" section added |
| §4.1 | Enter arrives as `:ctrl-m`/`:ctrl-j` under a pty | documented in `primitives.md` |
| §4.2 | `node-name`/`connect` return keywords | documented in `primitives.md` |
| §4.3 | raw mode needs a real TTY | skill's pty tip covers the inline-editor case |
| §4.4 | formatter relocates inline `;` in `cond` | skill warns about `cond` clauses too |

The `repro/` directory keeps the §1.2 two-node demo as a live regression check.
