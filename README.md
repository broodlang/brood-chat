# chat

A small **distributed chat app** written in [Brood](https://github.com/broodlang/brood),
runnable as a **native GUI window** or a **full-screen terminal TUI** from one
codebase — you pick the frontend at startup.

It's a demo of three Brood capabilities at once:

- **Distributed nodes** (ADR-073) — each runtime is a named node; `/connect` links
  two of them over a Unix socket (or TCP for `name@host:port`), and every line you
  type is broadcast to each connected peer's `:inbox` process.
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
nest run            # prompts: [g]ui window or [t]erminal? then a node name
nest run gui        # skip the frontend prompt — open a window
nest run tui        # skip the prompt — stay in the terminal
```

To see two nodes talk, open **two** terminals (or windows) and run `nest run` in
each, giving them different node names — say `alice` and `bob`. Then from `alice`:

```
/connect bob        # link to the peer named "bob"
hello!              # any plain line is broadcast to every connected peer
/say-hi             # ship a closure that greets you, computed on the peer
/run (+ 1 2)        # ship (fn () (+ 1 2)); the peer evaluates it and replies
/nodes              # list connected peers
/quit               # leave (Ctrl-C / Esc also quit)
```

Tab completes commands; Enter sends. The input line is the stdlib line editor
(`editor/lineedit`), so the full emacs/readline keymap works: C-a/C-e, M-b/M-f,
C-k/C-u/C-w kill, C-y yank, C-t, ↑/↓ recall earlier sends, and C-r
reverse-searches them. C-d on an empty line quits (mid-line it deletes forward).

## Tests

```sh
nest test
```

`tests/chat_test.blsp` covers the pure core — the model, the `chat-update` folds,
command dispatch, Tab completion, and the view helpers. The networked paths (peer
broadcast, `connect`, closures over the wire) need two live nodes, so they're
exercised by `repro/run.sh`, which sequences two real `nest run` processes and
asserts a clean peer exit fires `[:nodedown]` on the survivor promptly.

## Layout

| Path | What |
|------|------|
| `src/chat.blsp` | The whole app — model, update, pure view, peer-traffic wrapper, `main`. |
| `tests/chat_test.blsp` | Pure-core tests. |
| `repro/` | Two-node clean-disconnect (`[:nodedown]`) regression check. |
| `docs/brood-for-claude.md` | Brood language reference (for AI assistants). |
| `docs/findings.md` | The resolved findings log from first building this app. |
