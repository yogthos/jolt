# jolt-dev
# jolt-dev

Jolt development workflow — build, test, special form patterns, Janet gotchas

# Jolt Development

## Build & Test

```bash
cd /Users/yogthos/src/jolt
jpm build           # produces build/jolt
jpm test            # runs all tests
janet test/foo.janet  # run a single test file from project root
```

## Special Form Checklist

To add a new special form to the evaluator:

1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form` (the full list). Use `(in form 1)` for first arg, etc.

**Non-symbol heads** (keywords, etc.): `eval-list` first checks `(and (struct? first-form) (= :symbol (...)))` before extracting `name`. If not a symbol, falls through to default function application.

### Current special forms (29):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`, `var-get`, `var-set`, `var?`, `alter-var-root`, `find-var`, `intern`, `alter-meta!`, `reset-meta!`, `disj`, `set?`

## Compiler Architecture

Two-phase: `analyze-form [form bindings ctx]` → `emit-ast` (string) or `emit-expr` (data structures).

**Why data structures:** Janet's `eval` can't see `use`-imported symbols. Embed function VALUES directly via `core-fn-values` table.

**eval-string dispatch** (compile mode): stateful forms → interpreter; everything else → `compile-and-eval`. Macros expand at analyze time.

## PersistentHashMap Gotchas

- `core-map?`: `(if (and (table? x) (get x :jolt/deftype)) true false)` — `and` returns last truthy, not boolean
- `core-count`: subtract 1 for deftype tables (skip `:jolt/deftype` key)
- Equality: convert via `phm-to-struct` before `deep=`

## defrecord / deftype Patterns

- defrecord emits `(deftype TypeName [fields])` + arrow factory `(fn fields-vec (TypeName. field1 field2...))`
- Records are tables with `:jolt/deftype` = type name string
- `set!` field mutation: `(set! (.-x obj) val)` parses as array with `.-x` symbol head — check symbol name before dispatch

## Binding Macro

Uses `array-map` (plain Janet struct) not `hash-map` (PHM) to avoid PHM get() incompatibility with `var-get`.

## Tagged Literals (#inst, #uuid)

`:#inst` is invalid Janet keyword syntax (contains `#`). Use dynamic table construction:
```janet
(let [dr @{}] (put dr (keyword "#inst") (fn [s] s)) dr)
```

## LazySeq Patterns

- Use `indexed?` not `tuple?` for realized sequences (may be arrays from `cons`/`concat`)
- Avoid `val'` (apostrophe in symbol names) — causes Janet parse errors; use `vf` instead
- `ls-first`/`ls-rest`/`ls-seq` all call `realize-ls` first (caches result, realizes once)

## Janet Gotchas

- `def` creates constants; use `(var x nil)` for mutable locals
- Bare tuples in `eval` are function calls: `[1 2 3]` tries to call `1`. Use `['tuple 1 2 3]`
- `try` format: `(try body ([err] handler))` NOT `(try body (catch sym handler))`
- core-renames MUST match actual fn names: `"-"` → `"core-sub"` (not `"core--"`)
- Janet `parse` vs `parser/new`: use `parser/new` + `parser/consume` + `parser/eof` + `parser/produce` for full source parsing
- `(break val)` breaks from a while loop returning val — useful in bucket search patterns