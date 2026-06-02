## Persistent Data Structures

Load `.clj` source files into a context via the reader/evaluator:

```janet
(use ./src/jolt/api) (use ./src/jolt/reader) (use ./src/jolt/evaluator)
(def ctx (init))
(def s (slurp "src/jolt/clojure/lang/persistent_vector.clj"))
(var cur s)
(while (> (length (string/trim cur)) 0)
  (def [form rest] (parse-next cur))
  (set cur rest)
  (when (not (nil? form))
    (try (eval-form ctx @{} form) ([err] nil))))
```

**`:mutable?` flag:** `(init)` loads persistent structures by default. Pass `{:mutable? true}` to use Janet native mutable types instead: `(def ctx (init {:mutable? true}))`.

### PersistentVector (17 forms, fully working)
`src/jolt/clojure/lang/persistent_vector.clj` — 32-way branching trie with tail optimization.

### PersistentHashMap (18 forms, bitmap WIP)
`src/jolt/clojure/lang/persistent_hash_map.clj` — HAMT-based persistent hash map. 328-closing-parens balanced. `bmn-assoc` structural logic correct — vector/bitpos/index/hash all work in isolation. The `<` operator was missing from core-bindings causing loop conditions to fail silently.

## Gotchas (Critical)

### Missing comparison operators
`<`, `>`, `<=`, `>=` are NOT in `core-bindings` by default. Add them before any Clojure code with loop conditions:
```
"<" core-<   ">" core->   "<=" core-<=   ">=" core->=
```
Symptom: `(loop [i 0] (if (< i 3) (recur (inc i)) i))` returns nil because `<` resolves to nil → apply fails silently.

### `struct?` vs tables
Janet `struct?` returns **false** for deftype instances (tables). Use `(get val :jolt/deftype)` for `instance?` checks, not `(and (struct? val) ...)`.

### `defrecord` macro
Builds key-value pairs at expansion time: `(array-map :a a, :b b)`. Does NOT use `interleave` at eval time.

### `and`/`or` macros  
`(and x y)` → `(let* [and__x x] (if and__x (and y) and__x))`. `(or x y)` → `(let* [or__x x] (if or__x or__x (or y)))`. Registered as macros.

### `loop` macro
Explicit macro: `(defn core-loop [bindings & body] (list* (sym "loop*") bindings ...))` + `"loop" core-loop` in core-bindings + `"loop" true` in core-macro-names.

### `.` special form field access
For deftype instances: `(.-cnt obj)` → `(get obj :cnt)`. The `-` prefix is stripped.