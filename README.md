# chat

A small **distributed chat app** written in [Brood](https://github.com/broodlang/brood),
runnable as a **native GUI window** or a **full-screen terminal TUI** from one
codebase — you pick the frontend at startup.

It's a demo of three Brood capabilities at once:

- **Distributed nodes** (ADR-073) — each runtime is a named node; `/connect` links
  them over a Unix socket (or TCP for `name@host:port`), and every line you type is
  broadcast to each connected peer's `:inbox` process. Nodes form a **transitive
  mesh** (ADR-088): connecting to *one* peer joins its whole cluster, so the room is
  everyone reachable through it — connect a third node to either of the first two and
  all three see each other's messages. Presence (`/nodes` and the header count) is
  read straight off the live mesh, so peers appear and drop as the cluster changes.
  Links you dial with a `host:port` are held open with `ensure-link` (auto-reconnect
  on drop), and a late joiner is **caught up on history** — on join it asks a peer to
  replay the conversation so far. Cross-machine works too (see *Across machines*).
- **Closures over the wire** — slash-commands ship *real closures*, not strings.
  `/run <expr>` builds `(fn () <expr>)` and sends it for the peer to call; `/say-hi`
  captures the sender's name *here* yet computes the peer's identity *there* — proof
  that the captured environment crosses the link while free globals late-bind on the
  far side. Results come back and land in your log.
- **One UI, two frontends** (`std/ui`, ADR-046) — a pure `chat-view` (model + size →
  a render frame) and a `chat-update` (model + input → model) in the TEA style. The
  only difference between the window and the terminal is the frontend handed to
  `ui-run`: `(gui-display)` vs `*term-display*`. The same frame paints to both, and
  a crash in `view`/`update` is survived (the loop rolls back to the last good frame)
  rather than killing the session.

## Running

```sh
nest run                       # prompts: [g]ui or [t]erminal? then a node name
nest run gui                   # skip the frontend prompt — open a window
nest run tui alice             # skip both prompts — terminal, local node "alice"
nest run tui alice@0.0.0.0:9001 # a TCP node remote peers can dial (see below)
nest run --name alice tui      # let nest start the node (daemon model), pick tui
```

A bare node name (`alice`) is a **local** node (Unix socket, same machine). A
`name@host:port` name (`alice@0.0.0.0:9001`) is a **TCP** node that peers on other
machines can dial — its dial address shows in the header. If `nest run --name NAME`
already started a node, the app adopts it (no name prompt). Pick the frontend with a
`tui`/`gui` word or a `--with-tui`/`--with-gui` arg (the latter after `--` when there's
no file, e.g. `nest run --name alice -- --with-tui`).

To see two nodes talk, open **two** terminals (or windows) and run `nest run` in
each, giving them different node names — say `alice` and `bob`. Then from `alice`:

```
/connect bob        # link to the peer named "bob" (or alice@host:port for remote)
hello!              # any plain line is broadcast to every connected peer
/nick ada           # change the name shown on your messages
/me waves           # send an action ("✦ ada waves")
/say-hi             # ship a closure that greets you, computed on the peer
/run (+ 1 2)        # ship (fn () (+ 1 2)); the peer evaluates it and replies
/nodes              # list connected peers
/tz +2              # show timestamps in UTC+2 (retroactive, per-viewer)
/help  /clear       # command reference · wipe the log
/quit               # leave (Ctrl-C / Esc also quit)
```

Add a third runtime (`carol`) and `/connect alice` from it — the transitive mesh
links `carol` to `bob` too, so all three land in one room and every message reaches
everyone. `carol` also backfills the messages sent before it joined. Each line carries
a wall-clock timestamp in the left gutter, long lines word-wrap, and **PgUp/PgDn** (or
the mouse wheel) scroll the backlog — sending a line snaps back to live. Nothing you can
type or receive crashes the session: `chat-update` catches every error and turns it into
a log note, so a malformed `/run` or a garbled peer message is survived, not fatal.

### Across machines

The mesh works across hosts over TCP — start each node with a TCP address and dial
by `name@host:port`:

```sh
# on host 10.0.0.4
nest run tui alice@0.0.0.0:9001

# on another host — dial alice's routable address
nest run tui bob@0.0.0.0:9002
# then, in bob:  /connect alice@10.0.0.4:9001
```

The link is authenticated and **encrypted** (ADR-089), so TCP is safe on an
untrusted network. Both machines must share the same cookie — copy
`~/.config/brood/cookie` (or set `$BROOD_COOKIE` to the same value on each).

Tab completes commands; Enter sends. The input line is the stdlib line editor
(`editor/lineedit`), so the full emacs/readline keymap works: C-a/C-e, M-b/M-f,
C-k/C-u/C-w kill, C-y yank, C-t, ↑/↓ recall earlier sends, and C-r
reverse-searches them. C-d on an empty line quits (mid-line it deletes forward).

## Tests

```sh
make check     # the full gate: unit tests + all networked repros
nest test      # just the fast unit tests
```

`tests/chat_test.blsp` (52 tests) covers the pure core — the model, the `chat-update`
folds, command dispatch, presence (mesh → `:peers`) diffing, `/nick` / `/me` / `/tz` /
timestamps, history backfill, resilience (malformed `/run`, garbled history, connect
guards, never-throws), scrollback, node-identity + launch-arg parsing, word-wrap, Tab
completion, and the view helpers. The networked paths need live nodes, so three shell
regressions (run together by `repro/all.sh`, or `make repro`) drive real `nest run`
processes:

- `repro/mesh.sh` — three local nodes where B and C each `/connect` only A; asserts
  the transitive mesh still puts all three in one room (each sees two peers and holds
  all three lines). The group-chat guarantee.
- `repro/tcp.sh` — the same over **TCP** (loopback = the cross-machine path), where A
  chats *before* B and C join; asserts they mesh over TCP and **backfill** A's
  earlier lines they never received live.
- `repro/run.sh` — a clean peer exit fires `[:nodedown]` on the survivor promptly
  (socket-EOF close-detection, not the heartbeat timeout).

## Layout

| Path | What |
|------|------|
| `src/chat.blsp` | The whole app — model, update, pure view, peer-traffic wrapper, `main`. |
| `tests/chat_test.blsp` | Pure-core tests (52). |
| `Makefile` | `make check` / `test` / `repro` / `fmt` / `run`. |
| `repro/all.sh` | Runs every networked regression in sequence. |
| `repro/mesh.sh` | Three-node transitive-mesh group-chat regression (ADR-088). |
| `repro/tcp.sh` | TCP (cross-machine) mesh + history-backfill regression. |
| `repro/mesh_node.blsp` | One node of the mesh/tcp regressions (a faithful mini `ui-run`). |
| `repro/run.sh` | Two-node clean-disconnect (`[:nodedown]`) regression check. |
| `docs/brood-for-claude.md` | Brood language reference (for AI assistants). |
| `docs/findings.md` | The resolved findings log from first building this app. |

## License

Licensed under the GNU Affero General Public License v3.0 (`AGPL-3.0-only`); see
[`LICENSE`](LICENSE). Copyright © 2026 Wilhelm Kirschbaum.
