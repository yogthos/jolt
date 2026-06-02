---
triggers:
  - "compile jolt"
  - "jolt compiler"
  - "Clojure to Janet compilation"
  - "add new op to compiler"
  - "fix compiler"
---

# Jolt Compiler

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
- `(compile-and-eval form ctx)` → compile-ast + eval

## Why data structures, not source strings

Janet's `eval` does NOT have access to `use`-imported symbols from the calling file. `(eval "(core-inc 1)")` fails with "unknown symbol core-inc". The fix: emit Janet tuples where function VALUES are embedded: `[core-inc 1]`.

```
core-fn-values table:  "core-inc" → core-inc (the actual function)
emit-core-symbol-expr → (get core-fn-values janet-name)
```

Source-to-source (`compile-form` + `emit-ast`) still exists for debugging but is NOT used by `compile-and-eval`.

## Macro expansion

`analyze-form` checks whether the head symbol of a list resolves to a macro var before dispatching to special form handling:

1. Look up symbol in current ns → core ns via `resolve-macro`
2. If `var-macro?` is true, call `(var-get macro-var)` to get the fn
3. `(apply macro-fn (tuple/slice form 1))` to expand
4. `(analyze-form expanded ...)` to re-analyze the result

Macros expand at analyze time, before emission. `defn` expands to `(def name (fn* ...))`, `when` to `(if test (do ...) nil)`, etc.

## Symbol classification (in analyze-form)

Order: qualified ns → local binding → core-symbol → bare symbol

```
(if (form :ns) → :qualified-symbol
    (get bindings name) → :local
    (get core-renames name) → :core-symbol
    → :symbol)
```

core-renames MUST match actual fn names: `"-"` → `"core-sub"` (not `"core--"`), `"not"` → `"core-not"`. Verify against `core.janet` bindings.

## core-fn-values

Maps Janet string names to actual function values. Must be kept in sync with core-renames. When adding a new core fn, update BOTH tables.

Functions that need special mapping (name differs):
- `"apply"` → `apply` (Janet built-in)
- `"-"` → `"core-sub"` (not `core--`)
- `"some"` → `core-some?` (shared with `core-some?`)
- `"pr-str"` → `core-str` (alias)
- `"nth"` → `core-get` (alias)

## Stateful forms (must use interpreter, NOT compiler)

These forms modify context state and cannot be compiled:
- `defmacro`, `ns`, `deftype`, `defmulti`, `defmethod`, `require`, `in-ns`

Note: `def` IS handled by the compiler (compiles to Janet `def`).

## Adding a new op

1. Add `analyze-form` match arm for the special form
2. Add `emit-ast` match arm (source string path)
3. Add `emit-expr` match arm (data structure path)
4. Add `core-renames` entry if it's a core fn (name → Janet string name)
5. Add `core-fn-values` entry (Janet string name → actual fn value)
6. Add tests in `test/compiler-test.janet`

## Test patterns

- Source output tests: `(assert (= "(expected)" (compile-str "(input)")) "label")`
- Round-trip tests: `(assert (= val (compile-eval-str "(input)")) "label")`
- Compile flag tests: `(eval-string ctx "(input)")` with `{:compile? true}`

Run: `janet test/compiler-test.janet` or `jpm test`
