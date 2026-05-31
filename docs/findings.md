# Findings from building `connect-test` — outstanding items

This document started as a full record of everything wrong, missing, surprising,
or delightful while building the distributed-node chat REPL in `src/chat.blsp`
(an LLM, Claude, writing Brood for the first time against the live image via
`nest mcp`). The confirmed bugs and documentation errors it surfaced have since
been fixed upstream and removed from here — see this file's git history and the
upstream `docs/devlog.md` for the resolved items: the `--main` override (§1.1),
clean-disconnect `nodedown` (§1.2), the cross-node unbound-symbol hint (§1.3),
"functions can't be sent" (§2.1), implicit-`do` bodies (§2.2), 2-arg `substring`
(§3.1), the `std/lineedit` editor (§3.2), `doc-search` ranking (§3.3), and the
`term-poll`/`node-name`/raw-mode doc caveats (§4.1–§4.3).

What remains are two **documentation gaps** (not defects). Original finding IDs
are preserved.

---

## 3. API / stdlib gaps

### 3.4 Local-only `register`/`whereis` vs remote `{:name :node}` addressing

The model is good — `register` binds a local name, peers address it as `{:name N
:node Node}`, `whereis` is explicitly local. But this relationship is spread
across three separate docstrings. A short "named processes & cross-node
addressing" section (register ↔ send-map ↔ whereis, with one worked example)
would save a lot of stitching. This was the single hardest thing to assemble
from docstrings alone.

---

## 4. Behavioural surprises (correct, but document them)

### 4.4 The formatter relocates inline `;` comments inside `cond`

A trailing `;` comment on a `cond` clause gets moved to its own line *between*
clauses on `nest format`. Harmless, but the skill currently only warns about
comments inside vector/map literals — `cond` is another place to annotate
*above* the form, not inline.
