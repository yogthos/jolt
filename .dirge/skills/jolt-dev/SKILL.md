# jolt-dev

Jolt development workflow — build, test, special form patterns, Janet gotchas

## Build & Test

```bash
cd /Users/yogthos/src/jolt
git submodule update --init  # pulls vendor/sci (required for SCI bootstrap)
jpm build                     # produces build/jolt
jpm test                      # runs all tests (9 suites + SCI load)
janet test/foo.janet          # run a single test file from project root
```

## Persistent Data Structures

`:mutable?` compile flag in `src/jolt/api.janet` `init`: persistent Clojure data structures loaded by default. Pass `{:mutable? true}` to use Janet native mutable tuples/tables:
```janet
(def ctx (init))                  # persistent vectors, maps
(def ctx (init {:mutable? true})) # Janet tuples/structs
```

### Loading .clj source into context
```janet
(def s (slurp "src/jolt/clojure/lang/persistent_vector.clj"))
(var cur s)
(while (> (length (string/trim cur)) 0)
  (def [form rest] (parse-next cur))
  (set cur rest)
  (when (not (nil? form))
    (eval-form ctx @{} form)))
;; Then swap bindings:
(let [core-ns (ctx-find-ns ctx "clojure.core")
      pv-ns (ctx-find-ns ctx "jolt.lang.persistent-vector")]
  (ns-intern core-ns "vec" (var-get (ns-find pv-ns "vector")))
  (ns-intern core-ns "vector" (var-get (ns-find pv-ns "vector")))
  (ns-intern core-ns "vector?" (var-get (ns-find pv-ns "vector?"))))
```

### deftype table gotchas
- `struct?` returns false for Janet tables, but deftype creates tables. Use `(get val :jolt/deftype)` instead of `(and (struct? val) (get val :jolt/deftype))` for instance? checks.
- `.` special form strips leading `-` from member names before looking up field on deftype instances (e.g., `(.-cnt pv)` → `(get target :cnt)`).
- Default function application path handles `.-field obj` accessor syntax directly.

### Prototype-chain binding lookup
`resolve-sym` needs `binding-get` that walks Janet table prototype chain for nested `let`/`fn` bindings. Two-stage lookup: direct `get` first, then prototype walk:
```janet
(defn- binding-get [bindings name]
  (var result :jolt/not-found)
  (var t bindings)
  (while (not (nil? t))
    (when (in t name) (set result (in t name)) (break))
    (set t (table/getproto t)))
  result)
```

## Macro Patterns

### and/or macros
```janet
;; (and x y) → (let* [and__x x] (if and__x (and y) and__x))
;; (or x y)  → (let* [or__x x] (if or__x or__x (or y)))
```
Registered as macros in core-macro-names and bindings.

### loop macro
Expands `(loop [bindings] body...)` → `(loop* [bindings] body...)`. Registered as macro.

### defn multi-arity
Vectors are Janet tuples, not arrays. Use `indexed?` not `array?` for arg pattern matching:
```janet
(if (and (> (length rest) 0) (array? (first rest)) (indexed? (first (first rest))))
  ;; multi-arity: (defn name ([args] body)...)
  ...
  ;; single-arity: (defn name [args] body...)
  ...)
```

### defn- fix
`defn-` expands to `(def name (fn* ...))` not a reference to the `defn` symbol:
```janet
(defn core-defn- [fn-name & rest]
  ;; Same logic as defn, emits (def fn-name (fn* ...))
  ...)
```

### defrecord macro
Builds key-value pairs at macro-expansion time (not eval time — `interleave` doesn't work at eval time in Janet):
```janet
(var kvs @[])
(each f fields-vec
  (array/push kvs (keyword (f :name)))
  (array/push kvs f))
(def map-expr @[{:jolt/type :symbol :ns nil :name "array-map"} ;kvs])
```

## SCI Bootstrap

SCI added as git submodule at `vendor/sci`. 317/317 forms from 9 core files load with 0 failures in order: macros→protocols→types→unrestrict→vars→lang→utils→namespaces→core. 46 namespaces populated. SCI's `eval-string` is replaced with Jolt-native implementation that delegates to Jolt's reader/evaluator, bypassing SCI's internal pipeline (interpreter, parser, analyzer, opts).

Internal SCI namespaces need edamame/tools.reader stubs. See `test/test-load-sci.janet` for the canonical load test.

## Special Form Checklist

To add a new special form to the evaluator:

1. Add the name to `special-symbol?` in `src/jolt/evaluator.janet`
2. Add a match arm in `eval-list` (the match on `name`)
3. Add tests in `test/evaluator-test.janet`

The match arm receives `ctx`, `bindings`, and `form` (the full list). Use `(in form 1)` for first arg, etc.

**Non-symbol heads** (keywords, etc.): `eval-list` first checks `(and (struct? first-form) (= :symbol (...)))` before extracting `name`. If not a symbol, falls through to default function application. This means `(:ns &env)` works because the head `:ns` is a keyword, not a symbol, so it's evaluated and called as a lookup.

### Current special forms (22):
`quote`, `syntax-quote`, `unquote`, `unquote-splicing`, `do`, `if`, `def`, `defmacro`, `fn*`, `let*`, `loop*`, `recur`, `throw`, `try`, `set!`, `var`, `locking`, `instance?`, `defmulti`, `defmethod`, `deftype`, `new`, `.`

## Janet Gotchas

- `var` declares mutable locals that can be `set` later; `def`/`let` are immutable
- `let` cannot bind to `nil` — use `(var x nil)` instead of `(let [x nil] ...)`
- `(get table key)` needs 2 args minimum — for single-arg checks use `(table :key)`
- Functions are not tables — `(put fn :prop val)` fails. Stash properties on vars
- Janet structs silently **drop entries with nil values**: `(struct ;[:x nil :y 1])` → `{:y 1}`. Use `@{}` mutable tables when nil-valued entries are needed (e.g., `&env` binding `@{}` for macro bodies)
- Janet `(put table key nil)` silently drops the key. Use `:jolt/nil` sentinel via `bind-put` helper, unwrapped in `resolve-sym`
- `struct?` returns false for tables — deftype creates tables, use `(get val :key)` for field access
- **Bit operations**: use Janet built-ins `blshift`/`brshift`/`brushift`/`bnot`/`bor`/`band`/`bxor` (not `lshift`/`rshift`/etc.)
- Janet `mod` returns float, not integer
- `#{}` set literals can cause parse issues — use `@[]` as fallback
- `(first struct)` calls `:jolt/type` method — use `(get struct :key)` instead of positional access
- **`(last string)` returns nil** — `last` works only on indexed types (tuple, array). For strings use `(s (- (length s) 1))` or `(string/slice s (- (length s) 1))`

### unwrap-meta-name helper
Recursively unwraps `(with-meta sym meta)` forms to extract the underlying symbol. Used in `def`, `ns`, `deftype`, `defmethod` to handle metadata-wrapped names.

### Reader map k/v handling
The map reader must handle three special value types in both key and value positions:
- `:jolt/skip` — discarded form: skip the K/V pair entirely
- `:jolt/splice` — `#?@` splicing: concat items into the kvs array

### `#?(:cljs X)` returns nil → `:jolt/skip`
The non-splicing `#?` reader returns `{:jolt/type :jolt/skip}` for nil results (e.g., `#?(:cljs X)` on CLJ). This prevents orphaned nil keys/values. `parse-next` and `parse-string` skip past skip markers to return the next real form.

Closing delimiters `)`, `]`, `}` in `read-form` produce explicit errors (no fallthrough to `read-symbol`).

## Core Bindings (145+)

Key bindings in `core-bindings` map (in `src/jolt/core.janet`):
- Predicates, math, collections, sequences, higher-order functions
- Macros: `when`, `when-not`, `if-let`, `when-let`, `if-some`, `when-some`, `doto`, `and`, `or`, `defn`, `defn-`, `fn`, `let`, `loop`, `defrecord`, `defprotocol`, `declare`, `comment`
- Array primitives: `alength`, `aget`, `aset`, `aclone`, `object-array`, `int-array`, `to-array`
- Bit ops: `bit-and`, `bit-or`, `bit-xor`, `bit-not`, `bit-shift-left`, `bit-shift-right`, `unsigned-bit-shift-right`
- Unchecked math: `int`, `unchecked-inc`, `unchecked-dec`, `unchecked-add`, `unchecked-subtract`
- `hash` delegates to Janet built-in `hash`
- `name` returns name string of keyword/symbol/string
- `namespace` returns namespace of keyword/symbol or nil

### core-macro-names
Table `@{"when" true "defn" true ...}` — maps symbol name → `true` for all macro bindings. `init-core!` checks this to set `:macro true` on vars.

## Project Structure

```
src/jolt/
  types.janet      — Var, Namespace, Context, symbol helpers
  reader.janet     — recursive descent parser for Clojure syntax
  evaluator.janet  — tree-walking interpreter (eval-form, eval-list, syntax-quote*)
  core.janet       — 145+ clojure.core functions and macros
  api.janet        — public API: init, eval-string, eval-string*
  main.janet       — REPL entry point
  clojure/lang/
    persistent_vector.clj      — 32-way branching trie vector (17 forms)
    persistent_hash_map.clj     — HAMT hash map (24 forms, WIP)

test/               — 9 test suites + SCI load test
vendor/sci/         — SCI submodule
```