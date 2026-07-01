# chat — guidance for Claude

A distributed chat app over Brood's nodes (ADR-073), runnable as a **native GUI
window** or a **full-screen terminal TUI** from one codebase — built on the
`std/ui` `ui-run` loop (ADR-046). Start two runtimes, `/connect` to a peer, and
type. Slash-commands ship *closures* over the wire (`/run`, `/say-hi`).

## Layout

- `src/chat.blsp`   — the whole app: model, `chat-update`, pure `chat-view`, the
  peer-traffic frontend wrapper, and `main` (the `:main` entry point).
- `tests/chat_test.blsp` — covers the pure core (model/update/view/commands, presence
  diffing, `/nick` `/me` `/tz` timestamps, history backfill, resilience/never-throws,
  scrollback, node-identity + launch-arg parsing, word-wrap). The networked paths need
  live nodes; the `repro/` scripts drive real `nest run` processes over the actual chat
  module (`repro/mesh_node.blsp` is a faithful mini `ui-run` — reconcile-on-tick + fold
  peer traffic into one threaded model). The repros **stagger** node starts and measure
  `:peers` at convergence (before nodes exit) — a simultaneous double-join races the
  mesh gossip, and a late node would otherwise see earlier nodes leave.
- `repro/mesh.sh`   — three-node transitive-mesh (ADR-088) group-chat regression:
  B and C dial only A, yet all three end up in one room. The "everyone sees everyone"
  guarantee (asserts `peers=2 conv=3` each).
- `repro/tcp.sh`    — the same over TCP (loopback = the cross-machine path); A chats
  before B/C join, so it also asserts late joiners **backfill** the missed history.
- `repro/run.sh`    — a two-node clean-disconnect (`[:nodedown]`) regression.
- `docs/`           — `brood-for-claude.md` (language reference) and
  `findings.md` (the resolved log from first building this app).

## Running

- `make check`  — the full gate: `nest test` + all networked repros (`repro/all.sh`).
  Use this before declaring done. `make test` / `make repro` / `make fmt` / `make run`
  are the pieces.
- `nest test`   — run the test suite (each test runs in its own green process).
- `nest run`    — launch the chat app (`:main chat` in `project.blsp` → `chat/main`).
  It prompts for a frontend (`g`/`t`) and a node name; pass `gui`/`tui` (or a
  `name`/`name@host:port`) as args to skip the prompts. `nest run --name NAME` (the
  daemon model) pre-starts the node and the app adopts it — pick the frontend with a
  `tui`/`gui` word or `-- --with-tui` (a bare `--with-tui` is rejected by nest's parser
  when there's no FILE).
  Each module is a namespace (ADR-065): a file's `defmodule name` makes its
  `def`/`defn` define `name/foo`; a bare reference resolves in the current
  namespace, then through `(:use …)` imports, then root/prelude. The `chat--`
  double-dash helpers are module-private — `(:use chat)` re-exports only the
  public names, so tests reach the helpers qualified (`chat/chat--submit`).
- `nest run --for 2s` — run the TUI for a bounded time, then exit cleanly (`2s`,
  `500ms`, or a bare integer of ms). The way to exercise it end-to-end or in CI.
- `nest format` — format Brood source.

## Writing Brood

`docs/brood-for-claude.md` is the language reference geared for AI assistants
— syntax, idioms, and the patterns that aren't shared with other Lisps. Read
it before generating Brood code. The `.claude/skills/writing-brood` skill
carries the short version and auto-loads when Claude Code edits `.blsp` files.

Brood ships randomness (`rand-int`/`rand-float`/`shuffle`/`sample` — pure and
seedable, thread the seed), bitwise ops (`bit-and`/`bit-or`/`bit-xor`/...),
and discovery (`apropos`, `all-globals`, `doc-search`) — use the last three to
find what exists instead of guessing names.

## MCP integration

`.mcp.json` points Claude Code at this project's `nest mcp` server, so `cd chat && claude`
auto-attaches an agent that can `eval`, `load`, `lookup`, `macroexpand`, `format`,
and discover the image with `apropos` / `all-globals` / `doc-search`, against the
live image (ADR-036, `docs/mcp.md` upstream).
