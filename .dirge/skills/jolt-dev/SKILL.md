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
- Janet `and` returns the last truthy value, NOT boolean `true`. Wrap with `(if (and ...) true false)` for predicates.
- `set!` field mutation: `(set! (.-x obj) val)` reader creates `(. -x obj)` array — must check for `.` head in set! handler BEFORE the var mutation branch.

## deftype/defrecord Patterns

**deftype** produces a table with `:jolt/deftype` key (format: `"ns.TypeName"`):
- Constructor: `(TypeName. args...)` — evaluator creates `@{:jolt/deftype "ns.TypeName" :key1 val1 ...}`
- Field access: `(. obj field)` — evaluator does `(get obj (keyword field-name))`
- Mutation: `(set! (.-field obj) val)` — reader creates `(. -field obj)` array form

**Defrecord** macro emits `(do (deftype Name [fields]) (def ->Name ...) (def map->Name ...))`.

**core-map?** for records: `(or (phm? x) (struct? x) (if (and (table? x) (get x :jolt/deftype)) true false))`

**core-count** for records: `(- (length (keys coll)) 1)` (skip `:jolt/deftype` key)

## Symbol representation

Jolt symbols are `{:jolt/type :symbol :ns <string-or-nil> :name <string>}` as produced by the reader.