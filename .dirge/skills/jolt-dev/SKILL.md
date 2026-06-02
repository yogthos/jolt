---
name: jolt-dev
description: Jolt development workflow — build, test, special form patterns, Janet gotchas
---

# Jolt Development

## Build & Test

```bash
cd /Users/yogthos/src/jolt
jpm build           # produces build/jolt
jpm test            # runs all tests
janet test/foo.janet  # run a single test file from project root
```

## Compiler Development

See `jolt-compiler` skill for the Clojure→Janet source-to-source compiler workflow.

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
`test/compiler-test.janet` — 11 test groups covering all ops.

Key design decision: **compile-and-eval emits Janet DATA STRUCTURES, not source strings**, because Janet's `eval` doesn't see `use`-imported symbols. `core-fn-values` table resolves Janet names to actual function values at compile time.

## Compiler Development

### Adding a new op to the compiler

1. Add match arm in `analyze-form` — maps Clojure form → AST node
2. Add `emit-*-str` for source-to-source path, then arm in `emit-ast` dispatch
3. Add `emit-*-expr` for data-structure path, then arm in `emit-expr` dispatch
4. Add tests

### Emitter patterns

**String emitter**: `(buffer/push buf "...")` → source text  
**Data-structure emitter**: `['keyword val1 val2]` → eval-able tuples

### Janet eval gotchas

- Bare tuples are function calls — always use `['tuple ...]` or `(tuple ...)`
- `eval` scope: symbols from `(use ...)` not available — embed function VALUES
- Janet `try`: `(try body ([err] handler))` — not `(catch sym handler)`
- Core `-` maps to `core-sub` (NOT `core--`)

### Loop compilation

`(loop* [x 0] body-with-recur)` → `(do (var name nil) (set name (fn [x] body)) (name 0))`  
Recur rewrites to `(loop-name arg...)` via `:jolt/current-loop` binding.

### Quote: use `raw-form->janet` converter, never re-analyze

### Macro expansion: pass ctx to `analyze-form`, check `resolve-macro`, expand + re-analyze

## Special Form Checklist

To add a new special form to the evaluator AND compiler:

1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form` (the full list). Use `(in form 1)` for first arg, etc.

**Non-symbol heads** (keywords, etc.): `eval-list` first checks `(and (struct? first-form) (= :symbol (...)))` before extracting `name`. If not a symbol, falls through to default function application.

### Current special forms (22):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`

## Compiler Development

### Architecture
`src/jolt/compiler.janet` (721 lines). Two emitter paths:
- `compile-form` → `emit-ast` → Janet source string (debug/display)
- `compile-and-eval` → `emit-expr` → Janet data structures (direct eval, resolved fn values)

### Adding a compiled op
1. **analyze-form**: add `match head-name` arm returning `{:op :your-op ...}`
2. **emit-ast**: add str function + `:your-op` case in `set emit-ast` dispatch
3. **emit-expr**: add expr function + `:your-op` case in `set emit-expr` dispatch
4. Add tests in `test/compiler-test.janet`

### Emit-expr critical rules
- **Vectors**: wrap with `['tuple ...]` — bare tuples eval as fn calls
- **try/catch**: `[(tuple ;[err-sym]) handler]` NOT `(catch [err] body)`
- **quote**: use `raw-form->janet` converter, don't re-analyze
- **Core fns**: resolve via `core-fn-values` table, embed fn VALUES not names

### Macro expansion
`analyze-form` checks `resolve-macro` first — if head is a macro var, applies fn, re-analyzes expanded form (only when ctx passed).

## Persistent Data Structures

Located in:
- `src/jolt/clojure/lang/persistent_vector.clj`
- `src/jolt/clojure/lang/persistent_hash_map.clj`

Loaded at init time by `load-persistent-structures` in `api.janet`. Use `{:mutable? true}` to skip and use Janet-native types.

### Implementation detail
Simple array-based implementation (node-assoc/node-find/find-key-index), NOT HAMT bit-trie.
HAMT failed because Janet uses 64-bit doubles and bit operations require 32-bit signed ints.

## Janet Gotchas

- Bit operations (brshift, brushift, band) use 32-bit signed integers. Hash values can exceed 32-bit range. Use `(band x 0xFFFFFFFF)` before shifting.
- `deftype` creates tables, not structs. `struct?` returns false.
- `(get child :key)` DOES follow table prototype chain — resolved and confirmed working.
- Janet LSP produces many false positives on `.janet` files — safe to ignore.

## Symbol representation

Jolt symbols are `{:jolt/type :symbol :ns <string-or-nil> :name <string>}` as produced by the reader.