# jolt-bootstrap

TDD workflow for bootstrapping a Clojure interpreter on Janet

# Bootstrapping a Clojure interpreter on Janet

## Prerequisites
- Janet ≥ 1.36, jpm
- Target Clojure sources (e.g. sci) to load
- Jolt sources in `src/jolt/`, tests in `test/`

## TDD Loop
1. Write a failing test in `test/<feature>-test.janet` using `(use ../src/jolt/...)` relative paths
2. Run with `janet test/<file>.janet` (faster than `jpm test` for iteration)
3. If test involves `init` (which loads clojure.core), also `(use ../src/jolt/api)`
4. Implement in `src/jolt/<module>.janet`
5. Run test → see failure message → fix → repeat
6. After passing: `jpm test` to ensure no regressions

## Current bootstrap progress

**All files parse cleanly. Eval status:**

| File | Forms | Eval OK | Failures |
|------|-------|---------|----------|
| sci.impl.macros | 4/4 | 4 | 0 |
| sci.impl.protocols | 15/17 | 15 | 2 (resolution stubs) |
| sci.impl.utils | 39/47 | 39 | 8 (multi-arity, missing deps) |
| sci.impl.types | 22/27 | 22 | 5 (resolution stubs) |
| sci.impl.unrestrict | 2/2 | 2 | 0 |
| sci.impl.vars | 28/28 | 28 | 0 |
| sci.lang | 10/10 | 10 | 0 |
| sci.ctx-store | 6/6 | 6 | 0 |
| sci.impl.namespaces | 93/98 | 93 | 5 (missing copy-core-var dep) |
| sci.core | 60/69 | 60 | 4 (*1/*2/*3/*e unresolved) |

**Loading order:** macros → protocols → types → unrestrict → vars(27/28, skip comment block) → lang → utils → ctx-store → namespaces → core

**Added special forms:** quote, syntax-quote, unquote, unquote-splicing, do, if, def, defmacro, fn*, let*, loop*, recur, throw, try, set!, var, locking, instance?, defmulti, defmethod, deftype, new, . (22 total)

**Core additions:** when (macro), defn (macro with docstring), declare (macro), fn (macro — wraps fn*), Object (interop stub), derive, isa?, ancestors, descendants (hierarchy stubs), defprotocol (macro), extend-type, extend-protocol (macro), extend (macro), reify, satisfies?, extends?, implements?, type->str, comment (macro), prefer-method (stub), *unchecked-math* (false), *clojure-version* ({:major 1 :minor 11})

**Reader:** `#?(:clj ...)`, `#?@(:clj ...)` with splicing, `#_` discard, `#\` var-quote, `^` metadata, `;` comments → skip, nil `#?(:cljs ...)` → skip (non-splicing), empty `#?@(:cljs ...)` → empty splice, unmatched `)]}` → explicit errors

## Current blockers
1. `sci.impl.copy-vars` not yet loaded — needed for `copy-core-var`, `copy-var`, `macrofy`, `new-var`
2. `sci.impl.resolve`, `sci.impl.cljs`, `sci.impl.multimethods`, `sci.impl.deftype` not yet loaded
3. Multi-arity function dispatch edge cases in utils (forms 36-37, 44-45)
4. ~9 remaining eval failures across namespaces (5) and sci.core (4) — all tracing back to missing deps

## Key patterns

### Symbol structs
```janet
{:jolt/type :symbol :ns <string-or-nil> :name <string>}
```

### Macro intern marks var
```janet
(def v (ns-intern ns name macro-fn))
(put v :macro true)
```

### Reader conditional `#?`
Resolves at read time: scans for `:clj` keyword, picks next form.
`#?@` wraps resolved form in `:jolt/splice` struct for list/vec/set splicing.
Nil results (e.g. `#?(:cljs X)` on CLJ) now return `{:jolt/type :jolt/skip}` for non-splicing
and `{:jolt/type :jolt/splice :items @[]}` for splicing — preventing orphaned keys in maps.

### Callable forms check
```janet
(if (function? f)
  (apply f args)
  (get f (first args)))  ; table/struct lookup
```

### unwrap-meta-name helper
Recursively unwraps `(with-meta sym meta)` to extract the underlying symbol.
Used in `def`, `ns`, `deftype`, `defmethod` to handle metadata-wrapped names.

### deftype →TypeName constructor
`deftype` interns both `TypeName` and `->TypeName` (Clojure arrow constructor convention).

## Pitfalls
- Janet `let` can't bind to nil; use `(var x nil)` then `(set x val)`
- `(get table)` with 1 arg = compile error, use `(table :key)` shorthand
- `(put fn :key val)` fails on functions; stash metadata on vars instead
- `deftype` field names must be keywords (not strings) for `(inst :field)` access
- `defn` placed after `core-bindings` that reference it → compile error; order matters
- Janet's `try` macro: `(try body ([err] handler))` — catch clause is tuple `[binding body...]`
- **`core-macro-names`** is a zero-arg fn returning a table: `(get (core-macro-names) name)`. Don't call it as `(core-macro-names name)` — that's arity mismatch
- **Janet `#{}` sets** can cause parse issues — use `@[]` instead for stub collections
- **`break` in `while`** doesn't return a value in Janet — use `(var done nil)` + `(while (and cond (not done)) ... (set done result))` pattern instead
- **`(last string)` returns nil** — `last` works only on indexed types. Use `(s (- (length s) 1))` for last char of string
- **`(set [a b] tuple)` doesn't work** — Janet's `set` doesn't support destructuring. Use `(tuple 0)` / `(tuple 1)`
- **`#_` discard** works in lists, vectors, sets, and maps — wraps skipped form in `{:jolt/type :jolt/skip}` and readers check for this
- **Map reader** must handle `:jolt/skip` and `:jolt/splice` in both key and value positions
- **`comment` macro** must be registered in `core-macro-names` to avoid evaluating its body