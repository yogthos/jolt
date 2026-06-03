# jolt-dev

Jolt development workflow — build, test, special form patterns, Janet gotchas

## Build & Test

```bash
cd /Users/yogthos/src/jolt
jpm build           # produces build/jolt
jpm test            # runs all tests
janet test/foo.janet  # run a single test file from project root
```

## Janet Eval Pipeline (critical)

Janet's `(parse s)` does NOT return a parsed form — it returns `[symbol, error-position]`.
For evaluating Janet source strings, use the parser pipeline:

```janet
(def p (parser/new))
(parser/consume p source)
(parser/eof p)              # REQUIRED — otherwise produce returns nil
(def form (parser/produce p))
(eval form)
```

**Never** try `(eval [if true 1 2])` — Janet's `eval` doesn't recognize special forms in tuple data structures.

## `var` vs `def`

When you need to mutate a local with `set`, use `(var x nil)` not `(def x nil)`. `def` creates constants.

## Compiler (see also `jolt-compiler` skill)

`src/jolt/compiler.janet` — Clojure→Janet source compiler with macro expansion.

Key design decision: **compile-and-eval emits Janet DATA STRUCTURES, not source strings**, because Janet's `eval` doesn't see `use`-imported symbols. `core-fn-values` table resolves Janet names to actual function values at compile time.

### Adding a compiled op
1. Add match arm in `analyze-form` — maps Clojure form → AST node
2. Add `emit-*-str` for source-to-source path → arm in `emit-ast` dispatch
3. Add `emit-*-expr` for data-structure path → arm in `emit-expr` dispatch
4. Add tests in `test/compiler-test.janet`

### Emit-expr critical rules
- **Vectors**: wrap with `['tuple ...]` — bare tuples eval as fn calls
- **try/catch**: `[(tuple ;[err-sym]) handler]` NOT `(catch [err] body)`
- **quote**: use `raw-form->janet` converter, don't re-analyze
- **Core fns**: resolve via `core-fn-values` table, embed fn VALUES not names

### Macro expansion
`analyze-form` checks `resolve-macro` first — if head is a macro var, applies fn, re-analyzes expanded form (only when ctx passed).

### Loop/recur compilation
`(loop* [x 0] body)` → `(do (var name nil) (set name (fn [x] body)) (name 0))`
Recur rewrites to `(loop-name arg...)` via `:jolt/current-loop` binding.

## Special Form Checklist

To add a new special form to the evaluator AND compiler:
1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form`. Use `(in form 1)` for first arg.

### Current special forms (29):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`, `var-get`, `var-set`, `var?`, `alter-var-root`, `find-var`, `alter-meta!`, `reset-meta!`, `intern`

## PersistentHashMap (phm.janet)

`src/jolt/phm.janet` — separate module imported via `(use ./phm)` into `core.janet`.
PHM is a table with `:jolt/deftype` tag. Has `:cnt`, `:buckets` (array of 8 flat `[k v k v ...]` arrays), `:_meta`.
16 core functions updated with `(phm? x)` branches. `phm-to-struct` converts to Janet struct for compatibility.

### Janet `break` limitation
Janet `break` cannot be used inside `let` blocks — use `(var found nil)` + `(while ... (if condition (do (set found val) (break))))` pattern.

### core-binding: use array-map, not hash-map
`core-binding` macro must emit `(array-map ...)` for the binding frame — PHM's get is incompatible with `push-thread-bindings` var-get lookup.

### core-intern gotcha
Janet does not support Clojure-style multi-arity destructuring `([a b] ...)` in `defn`. Use flat args or wrapper functions.

## Symbol representation

Jolt symbols are `{:jolt/type :symbol :ns <string-or-nil> :name <string>}` as produced by the reader.

## Janet LSP

Janet LSP produces many false positives on `.janet` files — safe to ignore.
