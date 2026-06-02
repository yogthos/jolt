---
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

## Special Form Checklist

To add a new special form to the evaluator:

1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form` (the full list). Use `(in form 1)` for first arg, etc.

**Non-symbol heads** (keywords, etc.): `eval-list` first checks `(and (struct? first-form) (= :symbol (...)))` before extracting `name`. If not a symbol, falls through to default function application. This means `(:ns &env)` works because the head `:ns` is a keyword, not a symbol, so it's evaluated and called as a lookup.

### Current special forms (22):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`

### defmacro details
- Supports optional docstring: `(defmacro name [args] body)` or `(defmacro name "doc" [args] body)`
- Implementation: `(tuple/slice form 2)` → check if first is string → adjust args-form and body start
- Implicit `&env` binding: `(put new-bindings "&env" @{})` — table, not struct (nil-safe)
- Uses `parse-arg-names` for `& rest` arg handling

### defmulti / defmethod
- `defmulti` stores the methods table on the **var** via `(put v :jolt/methods methods)`, NOT on the function
- Janet `put` on a function value fails silently
- `defmethod` retrieves methods via `(get mm-var :jolt/methods)` using `resolve-var` to get the var first

### set!
- If var doesn't exist, auto-creates it (`ns-intern`) rather than erroring
- Needed for sci's `(set! *warn-on-reflection* true)`

### defmethod (auto-create)
- If the multimethod var doesn't exist yet, auto-creates it with a dummy fn and empty methods table
- This allows sci's `defmethod print-method` to work before `defmulti print-method` is defined

### deftype
- Handles `^:meta` on type name via `with-meta` pattern
- Fields vector handles `^:meta` annotations and `^Type` hints — extracts actual symbol name
- Produces a table with `:jolt/deftype "ns.TypeName"` and keyword-keyed fields

## Janet Gotchas

- `var` declares mutable locals that can be `set` later; `def`/`let` are immutable
- `let` cannot bind to `nil` — use `(var x nil)` instead of `(let [x nil] ...)`
- `(get table key)` needs 2 args minimum — for single-arg checks use `(table :key)`
- Functions are not tables — `(put fn :prop val)` fails. Stash properties on vars
- `match` is Janet's pattern matching — no `case` or `cond` needed for simple dispatch
- Janet structs silently **drop entries with nil values**: `(struct ;[:x nil :y 1])` → `{:y 1}`. Use `@{}` mutable tables when nil-valued entries are needed (e.g., `&env` binding `@{}` for macro bodies)
- `match` with string patterns returns **nil** (not error) when no pattern matches. Used in `eval-list` to handle non-symbol heads cleanly — keyword heads like `:ns` fall through to default function application
- `break` in `while` does NOT return a value in Janet. Use `(var done nil)` + `(set done val)` + check pattern instead
- Janet `#{}` set literals can cause parse issues in some contexts — use `@[]` as fallback
- `(first struct)` calls `:jolt/type` method — use `(get struct :key)` instead of positional access
- Janet `(struct ;[:x nil])` silently drops the nil entry — the map becomes `{}`. Use `@{}` tables for nil-safe entries
- `(length struct)` counts key-value pairs, not keys. Use `(length (keys struct))` for key count
- **`(last string)` returns nil** — `last` works only on indexed types (tuple, array). For strings use `(s (- (length s) 1))` or `(string/slice s (- (length s) 1))`
- **`(set [a b] tuple)` doesn't work** — Janet's `set` doesn't support destructuring. Use `(tuple 0)` / `(tuple 1)` or explicit individual assignments

### unwrap-meta-name helper
Recursively unwraps `(with-meta sym meta)` forms to extract the underlying symbol. Used in `def`, `ns`, `deftype`, `defmethod` to handle metadata-wrapped names:
```janet
(defn- unwrap-meta-name [form]
  (if (and (array? form) (> (length form) 0)
           (struct? (in form 0))
           (= :symbol ((in form 0) :jolt/type))
           (= "with-meta" ((in form 0) :name)))
    (unwrap-meta-name (in form 1))
    form))
```

### Reader map k/v handling
The map reader must handle three special value types in both key and value positions:
- `:jolt/skip` — discarded form (comment, `#_`, nil `#?(:cljs ...)`): skip the K/V pair entirely
- `:jolt/splice` — `#?@` splicing: concat items into the kvs array. If splice has 0 items (nil `:cljs` branch), don't push the key

### `#?(:cljs X)` returns nil → `:jolt/skip`
The non-splicing `#?` reader now returns `{:jolt/type :jolt/skip}` for nil results (e.g., `#?(:cljs X)` on CLJ). This prevents orphaned nil keys/values in maps and lists. `parse-next` and `parse-string` skip past skip markers to return the next real form.

### deftype →TypeName constructor
`deftype` now interns both the type name and `->TypeName` arrow constructor (Clojure convention). The dot-suffix constructor check uses `(sym-name (- (length sym-name) 1))` instead of broken `(last sym-name)`.

## Comment Handling

Comments `;` in `read-form` return `{:jolt/type :jolt/skip}` sentinel:
```janet
(= c 59)  # ;
[{:jolt/type :jolt/skip} line-end])
```

`parse-next` and `parse-string` both skip over `:jolt/skip` results:
- `parse-next` uses inner `parse-next-loop` that recurses on skip
- `parse-string` recurses on skip to return next non-comment form

`read-map` checks both key AND value positions for `:jolt/skip` to skip `#_`-discarded entries.

Closing delimiters `)`, `]`, `}` in `read-form` produce explicit errors:
```janet
(= c 41) (error (string "Unmatched closing paren at " pos))
```

This prevents them from falling through to `read-symbol` which gave "Unrecognized character".

## `unwrap-meta-name` Utility

Recursively unwraps `(with-meta sym meta)` forms to extract the underlying symbol:
```janet
(defn- unwrap-meta-name [form]
  (if (and (array? form) (> (length form) 0)
           (struct? (in form 0))
           (= :symbol ((in form 0) :jolt/type))
           (= "with-meta" ((in form 0) :name)))
    (unwrap-meta-name (in form 1))
    form))
```

Used in: `def`, `ns` (ns name), `deftype` (type name + field names), `defmethod` (arg names).
Replaced duplicated `with-meta` unwrapping code in each of these forms.

## Bootstrap Patterns

### Class-name resolution in resolve-sym

When a simple symbol (unqualified) isn't found in current ns or clojure.core, checks for dotted class-name pattern:
`Foo.Bar.Baz` → finds last dot → ns "Foo.Bar", name "Baz" → tries ns-resolve.
This resolves symbols like `IVar` that are interned in `sci.impl.vars` but referred to unqualified from `sci.lang`.

### Reader conditionals
- `#?(:clj expr :cljs expr2)` — resolved at read time by `read-reader-conditional`
- `#?@(:clj expr :cljs expr2)` — splicing variant, wraps resolved items in `{:jolt/type :jolt/splice :items ...}` 
- List/vector/set readers check for splice and flatten items
- `#_` — discard reader macro, reads next form and returns it as position only

### Core macros (in core.janet)
- `core-macro-names` returns `@{"when" true "defn" true "declare" true "defprotocol" true "extend-type" true "extend-protocol" true "extend" true "reify" true "fn" true "proxy" true "definterface" true "comment" true "defn-" true}` — a table
- `init-core!` calls `(get (core-macro-names) name)` to check, then `(put v :macro true)`
- Order matters: macro functions must be defined BEFORE `core-bindings` map references them

### Core stubs for sci bootstrap
- `core-derive`, `core-isa?`, `core-ancestors`, `core-descendants` — minimal hierarchy
- `core-Object`, `core-Thread`, `core-ThreadLocal`, `core-IllegalStateException` — JVM class stubs
- `core-volatile!`, `core-vswap!`, `core-vreset!` — volatile (atom-like table with :val key)
- `core-defprotocol` emits `(do (def name @{}) (def method fn) ...)` — macro, returns do form
- `core-extend-type`, `core-extend-protocol`, `core-extend`, `core-reify`, `core-satisfies?`, `core-extends?`, `core-implements?`, `core-type->str` — protocol stubs

### Namespace handling
- `ns` form handles `^:meta` on ns name via `with-meta` pattern
- `def` form also handles `^:meta` on def name (extracts name-sym from `(with-meta Name meta)`)
- `require` clause in `ns` wraps each spec in `(when s ...)` for nil-safety
- `resolve-var` falls back to checking clojure.core namespace if var not found in current ns

### Bootstrap loading order
```
sci.impl.macros      (4/4 ok)
sci.impl.protocols   (15/17 ok)
sci.impl.utils       (39/47 ok)
sci.impl.types       (22/27 ok)
sci.impl.unrestrict  (2/2 ok)
sci.impl.vars        (28/28 ok — comment block parsed as skip)
sci.lang             (10/10 ok — IVar via class-name resolve)
sci.ctx-store        (6/6 ok)
sci.impl.namespaces  (93/98 ok — parse crash at unmatched brace)
sci.core             (60/69 ok — namespaces/*1/*2/*3/*e fail)
```
All .cljc files. #?(:clj ...) resolved at read time. #?(:cljs ...) returns nil.

### parse-arg-names
- Handles `& rest` args AND nested destructuring vectors
- When an arg is a vector (not a symbol), recurses to extract nested symbol names

## Project Structure

```
src/jolt/
  types.janet      — Var, Namespace, Context, symbol helpers
  reader.janet     — recursive descent parser for Clojure syntax
  evaluator.janet  — tree-walking interpreter (eval-form, eval-list, syntax-quote*)
  core.janet       — 95+ clojure.core functions (map, filter, reduce, etc.)
  api.janet        — public API: init, eval-string, eval-string*
  main.janet       — REPL entry point with (defn main [&])

test/
  evaluator-test.janet  — special form tests (22 forms tested)
  reader-test.janet     — parser tests (includes #?, #?@, #_)
  core-test.janet       — core library tests
  macro-test.janet      — syntax-quote and macro tests
  namespace-test.janet  — ns, require, in-ns tests
  types-test.janet      — Var and Namespace tests
  api-test.janet        — public API tests
  bootstrap-test.janet  — loads sci.impl.macros (deftime, usetime, ?)
  test-load-sci.janet   — loads all sci files, counts ok/fail
  test-eval.janet       — end-to-end sci.core/eval-string test
```
