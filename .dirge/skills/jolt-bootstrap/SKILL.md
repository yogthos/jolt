---
name: jolt-bootstrap
description: TDD workflow for bootstrapping a Clojure interpreter on Janet
---

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

**Loaded (all .cljc, #? resolved at read time):**
- `sci.impl.macros` — 4/4 (ns, defmacro deftime, defmacro usetime, deftime(? macro))
- `sci.impl.protocols` — 15/17 
- `sci.impl.utils` — 39/47 
- `sci.impl.types` — 22/27
- `sci.impl.unrestrict` — 2/2
- `sci.impl.vars` — 28/28 (comment block parses via :jolt/skip sentinel)
- `sci.lang` — 10/10 (IVar resolves via class-name pattern lookup)
- `sci.ctx-store` — 6/6
- `sci.impl.namespaces` — 93/98 (parse crash at unmatched brace)
- `sci.core` — 60/69 (namespaces/*1/*2/*3/*e unresolved)

**Special forms (22):** quote, syntax-quote, unquote, unquote-splicing, do, if, def, defmacro, fn*, let*, loop*, recur, throw, try, set!, var, locking, instance?, defmulti, defmethod, deftype, new, .

**Reader:** `#?(:clj ...)`, `#?@(:clj ...)` with splicing, `#_` discard (returns :jolt/skip sentinel), `#\` var-quote, `^` metadata. Comments `;` skip via :jolt/skip. Closing delimiters `)`, `]`, `}` produce explicit "Unmatched" errors.

**Core macros:** when, defn (with docstring), defn-, declare, fn (wraps fn*), defprotocol, extend-type, extend-protocol, extend, reify, proxy, definterface, comment (ignores body), prefer-method (stub)

**Key utilities:** `unwrap-meta-name` — recursively unwraps `(with-meta sym meta)` to extract raw symbol. Used in def, ns, deftype, defmethod.

**Class-name resolution:** unqualified symbols with dots (`Foo.Bar.Baz`) are resolved by splitting at last dot into ns+name.

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

### Callable forms check
```janet
(if (function? f)
  (apply f args)
  (get f (first args)))  ; table/struct lookup
```

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
- **`read-reader-conditional`** for `#?(:cljs X)` with no `:clj` branch returns `[nil new-pos]`. For `#?@(:cljs X)` wrapping, nil gets wrapped in splice struct with `@[nil]` items
- **`#_` discard** now works in lists, vectors, and sets — wraps the skipped form in `{:jolt/type :jolt/skip}` and readers check for this
- **`read-regex`** now works with `(var done nil)` pattern to return value from while loop
- **`#?@` splicing inside vectors** — if the resolved :clj branch is itself a vector, items are extracted and spliced. Works for both lists and vectors.
