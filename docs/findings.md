# Findings from building `connect-test` — notes to improve Brood

This document records everything that was wrong, missing, surprising, or
delightful while building the distributed-node chat REPL in `src/chat.blsp`
(an LLM, Claude, writing Brood for the first time against the live image via
`nest mcp`). It is organised by actionability:

1. **Confirmed bugs** — behaviour that contradicts the docs or Erlang precedent.
2. **Documentation errors** — the reference says something false.
3. **API / stdlib gaps** — missing or awkward primitives that cost time.
4. **Behavioural surprises** — correct but undocumented, worth a doc line.
5. **What worked well** — keep these; they made the project pleasant.

Every claim below was reproduced against the running image. Minimal repros are
collected in the appendix.

---

## 1. Confirmed bugs

### 1.1 `nest run --main MODULE[/FN]` is silently ignored

With `:main chat` in `project.blsp`, **every** form of the override ran the
manifest entry (`chat`), not the requested module:

```
nest run --main scratch          # ran chat
nest run --main=scratch          # ran chat
nest run --main scratch/main     # ran chat
```

`nest run --help` promises: *"Override the entry point for this run — `module`
or `module/fn` — without editing the manifest's `:main`. Ignored when a FILE is
given."* No FILE was given, so it should have overridden. The flag appears to be
parsed and dropped.

**Impact:** high friction when iterating on a non-default module — you can't run
it without editing the manifest. The documented workaround (run as a FILE) only
executes top-level forms, so a `module` whose entry is `(defn main …)` does
nothing unless you append a top-level `(main)` call.

**Suggested fix:** honour `--main` (resolve `module` → `module/main`,
`module/fn` → that fn) and add a regression test, since the help text already
specifies the contract.

### 1.2 Clean disconnects are not detected (`monitor-node` / `nodes`)

`monitor-node` is documented as firing `[:nodedown name]` on *"heartbeat timeout
**or close**"*. The **close** half does not happen. Repro: two nodes linked,
peer process exits cleanly (`/quit` → process returns → socket closes). The
survivor:

- does **not** receive `[:nodedown peer]` promptly (only after a heartbeat
  timeout, seconds later — and in a bounded test run, never), and
- `(nodes)` still lists the dead peer.

Erlang fires `nodedown` immediately on a clean TCP/socket close; Brood seems to
rely solely on heartbeat liveness. We had to add an application-level `[:bye]`
message broadcast on `/quit` to get prompt pruning — but a process that is
`kill -9`'d or panics can't send that, so the runtime-level close detection
still matters.

**Suggested fix:** on a peer socket EOF/close, deliver `[:nodedown name]` to
monitors and drop the peer from `(nodes)` without waiting for the heartbeat
window. Update the docstring if "close" is intentionally not covered.

### 1.3 Misleading error hint on a cross-node unbound global

A closure sent across a node link whose free variable is a global that exists
only on the sender raises, on the receiver:

```
{:code E0010, :message unbound symbol: scratch/sender-only,
 :hint this fired inside a spawned process — if it happens only under fan-out
 load, the scheduler may be racing prelude lookups; try -j 1 …,
 :kind :unbound}
```

The hint is a red herring here: the symbol is **genuinely absent** on the
receiving image, not a scheduler race. The hint appears to be attached to any
`:unbound` raised inside a spawned process, which over-fires for the
node-link case and would send someone debugging in the wrong direction
(`-j 1` will never help).

**Suggested fix:** gate the "scheduler may be racing" hint to actual prelude/root
symbols, or suppress it for symbols that resolve fine on the local node — and for
the node-link case, add a hint like *"this closure was received from node X;
`scratch/sender-only` is not defined on this node (free globals late-bind on the
receiver)."*

---

## 2. Documentation errors

### 2.1 "Functions can't be sent" is false (the big one)

`docs/brood-for-claude.md:325-326` states:

> `(self)` is the current process's pid. **Functions can't be sent (per-heap
> closures)** — send data and call `def`'d names on the receiving side.

The matching note in `.claude/skills/writing-brood/SKILL.md` (the
reach-for/Brood-has table, `set!`/atoms row and the concurrency section) carries
the same claim.

**This is wrong.** Closures serialize and run, both same-node cross-process and
**across a node link**:

| Sent over a real node link | Ran on peer, returned |
| --- | --- |
| `(fn () (* 6 7))` | `42` |
| `(let (k 100) (fn () (+ k 1)))` — captures a local | `101` |
| `(fn () (str "hi " from))` where `from` captured from sender | greeting with the **sender's** name |

So a sent closure carries **its code + its captured lexical environment**
(closed-over locals are deep-copied with it). The only thing that does *not*
travel is the receiver's **global namespace**: a closure's free reference to a
`def`/`defn` global is **late-bound on the receiver** at call time. Therefore:

- ✅ Captured locals work — copied with the closure.
- ✅ Free globals the receiver also has work — builtins/prelude (`*`, `str`, …)
  always resolve there.
- ❌ Free globals defined **only on the sender** fail with `E0010 unbound
  symbol` on the receiver (see §1.3).

This is the Erlang fun-passing model and it's a genuine strength — the docs are
underselling a headline feature.

**Suggested replacement text:**

> Closures **can** be sent. A `send`-ed function carries its code and its
> captured locals (deep-copied across heaps and across node links). Its **free
> global references are late-bound on the receiver** — builtins and prelude
> names always resolve; your own `def`/`defn` globals must also exist on the
> receiving image (ship a `defn` first, or only reference names defined on both
> sides), otherwise the call raises `unbound symbol` there.

### 2.2 `defn` / `fn` bodies are implicit-`do`, but the docs never say so

Every example in `docs/brood-for-claude.md` shows a single-expression body (or
docstring + single expression). Nothing states that a multi-form body is an
implicit `do`. It is — `((fn () 1 2 3))` returns `3`. Because this was unstated,
the first draft of `chat.blsp` wrapped every multi-statement body in an explicit
`(do …)`, which is pure noise.

**Suggested fix:** one line in *Defining things*: "A `fn`/`defn` body of several
forms is an implicit `do`; the last form's value is returned."

---

## 3. API / stdlib gaps

### 3.1 `substring` has no 2-argument form

`(substring s start)` errors: `substring: expected 3 arguments, got 2`. Clojure
(`subs`) and CL both allow "from `start` to end". Every "rest of the string"
use had to spell `(substring line start (string-length line))`. A 2-arg
overload (end defaults to length) would remove a very common papercut.

### 3.2 No line-editor / readline in the stdlib

`read-line` is line-buffered (good for a script), but there is **no** built-in
interactive editor — no history, no completion, no cursor editing. Building a
REPL prompt with Tab completion meant hand-rolling a raw-mode loop on
`term-raw-enter` / `term-poll` / `term-emit` (~40 lines). The primitives are
excellent (see §5), but a `std/readline`-style helper — `(read-line-edit
{:prompt … :complete (fn (buf) [candidates…]) :history …})` returning the
finished line — would be a high-value addition. It's the single most-requested
shape for any REPL/CLI tool.

### 3.3 `doc-search` under-delivers vs `apropos`

`apropos` (name substring) was reliable and fast. `doc-search` (docstring text)
returned `nil` for several reasonable queries that *should* have hit:

- `"remote node distributed"` → nil (yet `node-start`/`connect` docstrings exist)
- `"raw mode single keypress"` → nil (yet `term-raw-enter`/`term-poll` exist)
- `"node up down notification"` → nil (yet `monitor-node` exists)

Either the index is name/exact-token based rather than fuzzy, or many docstrings
lack the words a caller would search for. Worth checking the indexer; docstring
search is exactly how an LLM (or human) finds "the thing that does X".

### 3.4 Local-only `register`/`whereis` vs remote `{:name :node}` addressing

The model is good — `register` binds a local name, peers address it as `{:name N
:node Node}`, `whereis` is explicitly local. But this relationship is spread
across three separate docstrings. A short "named processes & cross-node
addressing" section (register ↔ send-map ↔ whereis, with one worked example)
would save a lot of stitching. This was the single hardest thing to assemble
from docstrings alone.

---

## 4. Behavioural surprises (correct, but document them)

### 4.1 `term-poll` reports Enter as `:ctrl-j` / `:ctrl-m`, not `:enter`, under a pty

`term-poll`'s docstring lists `:enter` among the specials. In practice, when the
terminal delivers a newline as a raw byte (CR `0x0d` or LF `0x0a` — e.g. through
a pty, CRLF translation, or piped input), `term-poll` returns **`:ctrl-m`**
(CR) or **`:ctrl-j`** (LF), *not* `:enter`. A line editor must treat all three
as "submit":

```lisp
(or (= k :enter) (= k :ctrl-j) (= k :ctrl-m))
```

We lost real time here: Tab completion worked first try, but Enter silently did
nothing because only `:enter` was matched. Either normalise CR/LF to `:enter` in
raw mode, or document that `:enter` is the *named-key* event and CR/LF arrive as
the ctrl- forms.

### 4.2 `node-name` and `connect` return a **keyword** (`:alice@whkbus`)

Not a string. It interpolates fine via `str`, and works as a `:node` value, but
it's worth stating the type — code that does string ops on a node name (e.g.
`(starts-with? (node-name) …)`) would need `(str (node-name))` first.

### 4.3 Raw mode needs a real TTY (same as `term-enter`)

`term-raw-enter` dies on piped stdin; tests must wrap the program in a pty
(`script -qec "nest run --for …" /dev/null`). This matches the existing
`term-enter` note in the skill, but the skill's pty tip only mentions
full-screen TUIs — it should also cover the raw-mode *inline* editor case, since
that's what a REPL uses.

### 4.4 The formatter relocates inline `;` comments inside `cond`

A trailing `;` comment on a `cond` clause gets moved to its own line *between*
clauses on `nest format`. Harmless, but the skill currently only warns about
comments inside vector/map literals — `cond` is another place to annotate
*above* the form, not inline.

---

## 5. What worked well (keep / lean into)

- **The distributed-node layer is excellent and "just worked."** `node-start` →
  `connect` → `register` → `send` to `{:name :node}` over a local Unix socket
  needed zero fiddling, with cookie auth handled transparently. The `name@host`
  identity model (ADR-073) is clean.
- **Closures over the link** (§2.1) are a real superpower once you know they
  exist — shipping `(fn () …)` to a peer and getting the value back, with
  captured locals intact, made the "send a function to the other terminal"
  feature a three-line change.
- **The `term-raw-enter` / `term-emit` / `term-poll` seam is exactly right** for
  an inline editor: raw mode without an alt-screen, relative-motion render ops
  (`[:cr] [:clear-eol] [:print …] [:nl]`), and a single polling call that
  returns rich key events. Building a flicker-free prompt that survives async
  output was straightforward.
- **One process can both `term-poll` and drain its mailbox** (via `receive …
  (after 0 …)`). Making the editor process *be* the registered `:inbox` meant
  incoming messages redraw above the prompt without clobbering the half-typed
  line — no cross-process screen-arbitration needed. This pattern deserves a
  mention in the concurrency docs; it's the clean answer to "interactive input +
  async events."
- **The `nest mcp` eval/load/lookup/apropos loop** was the difference between
  guessing and knowing. Probing `node-start`/`connect`/`monitor-node` signatures
  and reproducing the closure-serialization behaviour live (rather than trusting
  the docs, which were wrong) is what surfaced most of this document.
- **`spawn`'s double-wrap gotcha** is well documented and did not bite — the
  warning earned its place.

---

## Appendix — minimal repros

```lisp
;; §2.1 closure with a captured local, sent across a node link, runs on the peer.
;; (node "cli" connected to node "srv"; srv's :inbox does (f) and replies)
(let (k 100) (to "srv@host" [:run (node-name) (fn () (+ k 1))]))   ; => peer returns 101

;; §2.2 fn body is implicit-do
((fn () 1 2 3))                         ; => 3

;; §3.1 substring is 3-arg only
(substring "hello" 2)                   ; error: substring: expected 3 arguments, got 2
(substring "hello" 2 (string-length "hello"))   ; => "llo"

;; §4.1 Enter under a pty arrives as :ctrl-j (LF) or :ctrl-m (CR), not :enter
;; (probe: raw-enter, poll, print key) feeding bytes 'a' CR LF TAB:
;;   => ("a" :ctrl-j :ctrl-j :tab …)

;; §4.2 node-name is a keyword
(node-name)                             ; => :alice@whkbus  (keyword, not string)
```
