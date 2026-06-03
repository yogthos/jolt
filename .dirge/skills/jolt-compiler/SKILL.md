# jolt-compiler

Source-to-source Clojure→Janet compiler. Two-phase: analyze-form (classify + macro expand) → emit-ast (generate).

## Architecture

```
Clojure form → analyze-form [form bindings ctx] → AST {:op ...}
                               ↓ (if head = macro var)
                          expand → re-analyze expanded form
                    ↓
              emit-ast (source string) or emit-expr (data structure)
```

Three public entry points:
- `(compile-form form &opt ctx)` → Janet source string (debug/display)
- `(compile-ast form &opt ctx)` → Janet data structure (for eval)
- `(compile-and-eval form ctx)` → compile-ast + eval + ns interning

## Why data structures, not source strings

Janet's `eval` does NOT have access to `use`-imported symbols. Emit Janet tuples with embedded function VALUES via `core-fn-values` table.

Source-to-source (`compile-form` + `emit-ast`) exists for debugging, NOT used by `compile-and-eval`.

## Macro expansion

`analyze-form` checks `resolve-macro` before special form dispatch:
1. Look up symbol in current ns → core ns
2. If `var-macro?`, apply fn, re-analyze expanded form

## Symbol classification

Order: qualified ns → local binding → core-symbol → bare symbol

core-renames MUST match actual fn names: `"-"` → `"core-sub"` (not `"core--"`).

## core-fn-values

Maps Janet string names to actual function values. Must be kept in sync with core-renames.
Special mappings: `"apply"` → `apply` (built-in), `"some"` → `core-some?`, `"pr-str"` → `core-str`, `"nth"` → `core-nth`.

## compile-and-eval interning

`def`/`defn` results are interned in the Jolt namespace via `ns-intern` so the interpreter can resolve bare symbols. This is critical — without it, `(defn foo [x] x)` followed by `(foo 1)` would fail with "Unable to resolve symbol: foo".

## Loop/recur compilation

`loop*` → `(do (var name nil) (set name (fn [params] body)) (name init-vals...))`
`recur` → `(loop-name arg...)` via `:jolt/current-loop` binding

## Throw/try compilation

- `throw` → `(error val)` in Janet
- `try` → `(try body ([err] handler))` — Janet uses `([sym] handler)`, NOT `(catch sym handler)`

## Quote — use raw-form->janet

Don't re-analyze quoted forms. Use `raw-form->janet` to pass Jolt reader forms verbatim to Janet's `quote`.

## Remaining ops (interpreter only)

`syntax-quote`, `set!`, `deftype`, `defmulti`, `defmethod` — stateful/complex, always use interpreter.

## Stateful forms (interpreter only even in compile mode)

`defmacro`, `ns`, `deftype`, `defmulti`, `defmethod`, `require`, `in-ns`

Note: `def` IS handled by compiler (macros expanded at analyze time).

## eval-string dispatch (compile mode)

Stateful check: `defmacro`, `ns`, `deftype`, `defmulti`, `defmethod`, `require`, `in-ns`, `syntax-quote`, `set!`, `var`, `.`, `new` → interpreter. Everything else → `compile-and-eval`.

## Adding a new op

1. Add `analyze-form` match arm
2. Add `emit-ast` + `emit-expr` match arms
3. Update `core-renames` + `core-fn-values` if core fn
4. Add tests in `test/compiler-test.janet`

## Var system (Phase 3)

`var-get`, `var-set`, `var?`, `alter-var-root`, `find-var`, `alter-meta!`, `reset-meta!`, `intern` — all dispatched in evaluator, with Clojure wrappers in `core-bindings`. `find-var` takes a ctx + symbol, must eval args first (NOT pass raw form). `core-meta` handles vars via `var-meta` branch.

## PersistentHashMap (Phase 2)

`src/jolt/phm.janet` — separate module, bucket-based with `:jolt/deftype` tag. `core-binding` macro uses `array-map` (not `hash-map`) to avoid PHM get() incompatibility with `push-thread-bindings`.

## Test files

- `test/compiler-test.janet` — all compiler tests (Phases 0-3)
- `test/phase6-final.janet` — 47 comprehensive compile-mode tests

Run: `janet test/compiler-test.janet` or `jpm test`
